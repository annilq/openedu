"""Tasks feature service：任务域的全部业务逻辑（REST 路由与业务查询工具共用，ADR-0033 决策 13）。

读路径（今日任务 / 进度 / 错题 / 掌握度）与**写路径**（草稿生成、题卡落库、锁定、
派发、作答、打卡）都在这里。写路径此前留在 router 里——router 直接 import 20 个
repository 函数做多步编排，还把 repository 的私有 sentinel 当控制流用，导致：
路由层膨胀到 700+ 行、ORM 与领域类型泄漏到 HTTP 层、ADR-0033 的查询工具想复用
写逻辑时无门可入。现在 router 只剩「鉴权 → 调本模块 → 翻译响应」。

本模块不得 import fastapi / router（分层不变量 5/6）：查询工具在 SSE 请求内同步
直调这里的函数，不经 ASGI。
"""

from __future__ import annotations

from datetime import date
from uuid import UUID

from sqlmodel import Session, select

from app.ai import resolve_engine
from app.core.async_bridge import run_async
from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned, require_owned_child
from app.db.models import Question, Task, TaskQuestion, User, WrongQuestion
from app.domain import Grader, build_provider
from app.domain.provider import GeneratedQuestion
from app.features.tasks.repository import (
    add_bank_questions_to_task,
    assign_task,
    batch_generate_task,
    confirm_task,
    create_answer_record,
    create_checkin,
    create_task_from_bank,
    discard_draft_task,
    get_child_tasks_today,
    get_progress,
    get_task_question,
    get_task_questions,
    list_tasks_by_parent,
    promote_task_question,
    regenerate_all_task_questions,
    regenerate_one_task_question,
    remove_task_question,
    update_task_question,
    upsert_wrong_question,
)
from app.features.tasks.repository import (
    list_wrong_questions as repo_list_wrong_questions,
)
from app.features.tasks.schemas import (
    AnswerResult,
    CheckinResult,
    ProgressResp,
    QuestionResp,
    TaskResp,
    WrongQuestionResp,
)

# ───────────────────────── 序列化（ORM → 响应模型） ─────────────────────────


def question_to_resp(tq: TaskQuestion, *, include_answer: bool) -> QuestionResp:
    """TaskQuestion → QuestionResp；``include_answer=False`` 抹掉答案（娃娃端防作弊）。"""
    return QuestionResp(
        id=tq.id,
        question_id=tq.question_id,
        subject=tq.subject,
        grade=tq.grade,
        stem=tq.stem,
        options=tq.options,
        qtype=tq.qtype,
        knowledge_point=tq.knowledge_point,
        explanation=tq.explanation or "",
        answer=tq.answer if include_answer else None,
    )


def task_to_resp(
    task: Task, questions: list[TaskQuestion], *, include_answer: bool
) -> TaskResp:
    return TaskResp(
        id=task.id,
        title=task.title,
        status=task.status,
        specs=task.specs,
        questions=[question_to_resp(q, include_answer=include_answer) for q in questions],
        child_id=task.child_id,
        created_at=task.created_at,
    )


def wrong_question_to_resp(
    wq: WrongQuestion, q: Question, *, include_answer: bool
) -> WrongQuestionResp:
    return WrongQuestionResp(
        id=wq.id,
        question_id=q.id,
        subject=q.subject,
        grade=q.grade,
        knowledge_point=q.knowledge_point,
        qtype=q.qtype,
        stem=q.stem,
        options=q.options,
        answer=q.answer if include_answer else None,
        explanation=q.explanation or "",
        wrong_count=wq.wrong_count,
        first_wrong_at=wq.first_wrong_at,
        review_stage=wq.review_stage,
        due_at=wq.due_at,
    )


# ───────────────────────── 只读用例 ─────────────────────────


def list_parent_tasks(
    *, session: Session, parent_id: UUID, status: str | None = None
) -> list[TaskResp]:
    """家长任务列表（含答案，供审阅/核查）。"""
    return [
        task_to_resp(
            t,
            get_task_questions(session=session, task_id=t.id),
            include_answer=True,
        )
        for t in list_tasks_by_parent(
            session=session, parent_id=parent_id, status=status
        )
    ]


def list_today_tasks(*, session: Session, child_id: UUID) -> list[TaskResp]:
    """娃娃今日任务（assigned/done；不含答案）。"""
    return [
        task_to_resp(
            t,
            get_task_questions(session=session, task_id=t.id),
            include_answer=False,
        )
        for t in get_child_tasks_today(session=session, child_id=child_id)
    ]


def list_wrong_questions(
    *, session: Session, child_id: UUID, include_answer: bool
) -> list[WrongQuestionResp]:
    """错题本。``include_answer`` 由调用方按角色决定；查询工具恒传 True 后交
    ``project_for_role`` 统一裁剪（ADR-0033 决策 9）。"""
    rows = repo_list_wrong_questions(session=session, child_id=child_id)
    return [
        wrong_question_to_resp(wq, q, include_answer=include_answer) for wq, q in rows
    ]


def child_progress(*, session: Session, child_id: UUID) -> ProgressResp:
    """学习进度（纯读取，不做鉴权）。"""
    total, correct, checkin_days, streak = get_progress(
        session=session, child_id=child_id
    )
    return ProgressResp(
        child_id=child_id,
        total=total,
        correct=correct,
        accuracy=round(correct / total, 2) if total else 0.0,
        streak_days=streak,
        checkin_days=checkin_days,
    )


# ───────────────────────── 家长视角复合用例（鉴权 + 读取） ─────────────────────────


def list_owned_child_wrong_questions(
    *, session: Session, parent: User, child_id: UUID
) -> list[WrongQuestionResp]:
    """家长查某娃娃错题本（含答案/解析供核查）；先校验归属。"""
    require_owned_child(session=session, owner_id=parent.id, child_id=child_id)
    return list_wrong_questions(session=session, child_id=child_id, include_answer=True)


def owned_child_progress(*, session: Session, parent: User, child_id: UUID) -> ProgressResp:
    """家长查某娃娃学习进度；先校验归属。"""
    require_owned_child(session=session, owner_id=parent.id, child_id=child_id)
    return child_progress(session=session, child_id=child_id)


# ───────────────────────── 写路径：内部构件 ─────────────────────────


def _extract_interests_pool(child: User | None) -> list[str] | None:
    """从娃娃画像抽取轻融入兴趣池（WF-3）：受控分类叶子 + 自由文本。

    返回扁平字符串列表（如 ["恐龙", "太空", "养蚕"]），空则 None。
    注：自由文本（free_text）经生成 _SYSTEM 年龄/内容约束兜底；显式安全闸门见 WF-6。
    """
    if child is None or not child.interests:
        return None
    cat = child.interests.get("categories") or []
    pool = [c for c in cat if isinstance(c, str)]
    free = child.interests.get("free_text")
    if isinstance(free, str) and free.strip():
        pool.append(free.strip())
    return pool or None


def _gen_question(
    engine,
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
    interests: list[str] | None = None,
    focus_interest: str | None = None,
) -> GeneratedQuestion:
    """出题单题：统一走共享出题管线 ``app.ai.subagents.question.pipeline``
    （ADR-0023 收敛 / ADR-0032：只依赖 ``LLMProvider``，不再直连 genkit 引擎）。

    mock 兜底已移除：engine 为 None 或真实产出不安全（check_output 未过）时生成失败，
    由上层以 LLM_UNAVAILABLE 报错，不再静默回退假数据。
    """
    from app.ai.subagents.question.pipeline import (
        generate_question as _generate_question,
    )
    from app.domain import build_provider

    g: GeneratedQuestion | None = None
    try:
        provider = build_provider(engine=engine)
        g = run_async(
            _generate_question(
                provider,
                subject=subject,
                grade=grade,
                knowledge_point=knowledge_point,
                qtype=qtype,
                difficulty=difficulty,
                interests=interests,
                focus_interest=focus_interest,
            )
        )
    except Exception:
        g = None
    if g is None:
        raise AppErrorException(
            ErrCode.LLM_UNAVAILABLE,
            "无可用 LLM 引擎或题目生成不安全，无法重生成（请配置 LLM_PROVIDER 与 API key）",
        )
    return g


def _generate_task_questions_for_specs(
    specs: list[dict],
    *,
    interests: list[str] | None = None,
    focus_interests: list[str] | None = None,
    engine=None,
) -> list[TaskQuestion]:
    """调用出题引擎产草稿 TaskQuestion（R-Q1=c：不写 Question 表）。

    engine 为 resolve_engine 解析结果（None = 无真实引擎，出题核心将失败并抛 LLM_UNAVAILABLE）。

    兴趣注入（WF-3/WF-4）：
    - `interests`：轻融入兴趣池（娃娃画像 categories），整卷统一下传。
    - `focus_interests`：兴趣题模式聚焦主题（list）；非空时按题轮询均分（第 i 题取
      focus_interests[i % n]），且此时不再轻融入兴趣池（避免双模式叠加）。
    """
    out: list[TaskQuestion] = []
    n_focus = len(focus_interests) if focus_interests else 0
    idx = 0
    for sp in specs:
        if isinstance(sp, dict):
            subject = str(sp.get("subject", ""))
            grade = int(sp.get("grade", 0))
            knowledge_point = str(sp.get("knowledge_point", ""))
            qtype = str(sp.get("qtype", ""))
            difficulty = str(sp.get("difficulty", "medium"))
            count = int(sp.get("count", 1))
        else:
            subject = sp.subject
            grade = sp.grade
            knowledge_point = sp.knowledge_point
            qtype = sp.qtype
            difficulty = sp.difficulty
            count = sp.count
        for _ in range(max(0, count)):
            # 兴趣题模式：轮询取一个聚焦主题；否则轻融入兴趣池。
            focus = focus_interests[idx % n_focus] if n_focus else None
            idx += 1
            g = _gen_question(
                engine,
                subject=subject,
                grade=grade,
                knowledge_point=knowledge_point,
                qtype=qtype,
                difficulty=difficulty,
                interests=interests if focus is None else None,
                focus_interest=focus,
            )
            out.append(
                TaskQuestion(
                    task_id=None,  # 由 batch_generate_task / regenerate_all 回填
                    question_id=None,  # R-Q1=c：草稿期不入题库
                    subject=g.subject,
                    grade=g.grade,
                    knowledge_point=g.knowledge_point,
                    qtype=g.qtype,
                    stem=g.stem,
                    options=g.options,
                    answer=g.answer,
                    explanation=g.explanation,
                    difficulty=g.difficulty,
                )
            )
    return out


def _owned_task(*, session: Session, parent: User, task_id: UUID) -> Task:
    """取任务并断言归属当前家长；不存在/越权统一报「任务不存在」（404）。

    「越权伪装成不存在」是本端点的对外契约，判归属本身委托 ``core.guard``。
    """
    return require_owned(
        session=session,
        owner_id=parent.id,
        model=Task,
        obj_id=task_id,
        code=ErrCode.TASK_NOT_FOUND,
        message="任务不存在",
    )


def _require_draft(task: Task) -> None:
    if task.status != "draft":
        raise AppErrorException(
            ErrCode.TASK_STATUS_DRAFT_REQUIRED, "仅草稿态可执行该操作"
        )


def _draft_item(*, session: Session, task: Task, tq_id: UUID) -> TaskQuestion:
    """取草稿项并断言它属于 ``task``。"""
    tq = get_task_question(session=session, tq_id=tq_id)
    if tq is None or tq.task_id != task.id:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    return tq


# ───────────────────────── 写路径：命令 ─────────────────────────


def create_from_bank(
    *,
    session: Session,
    parent_id: UUID,
    title: str,
    child_id: UUID | None,
    question_ids: list[UUID],
) -> TaskResp:
    """选项 A：从题库新建任务（draft）。深拷贝选中题为 TaskQuestion 并回填 question_id。"""
    if not question_ids:
        raise AppErrorException(ErrCode.TASK_EMPTY_SPECS, "请至少选择一道题")
    task = create_task_from_bank(
        session=session,
        parent_id=parent_id,
        title=title,
        child_id=child_id,
        question_ids=question_ids,
    )
    return task_to_resp(
        task, get_task_questions(session=session, task_id=task.id), include_answer=True
    )


def create_from_generated(
    *,
    session: Session,
    parent_id: UUID,
    title: str,
    child_id: UUID | None,
    questions: list[dict],
    specs: list[dict],
    focus_interest: list[str] | None,
    model: str | None,
) -> TaskResp:
    """流式题卡落库：把逐题返回的题卡一次性建为 draft 任务。

    用于「生成任务」按钮的流式渲染 + 落库两步法：前端先连流式端点逐题渲染题卡
    （消除超时），流结束后再把已生成题卡 POST 到此处落库，避免二次生成。
    `questions` 是前端渲染用的同一批题卡（QuestionPreview.toJson，snake_case），
    这里只做归属/非空校验并构造成 TaskQuestion 落库，不重新调用出题引擎。
    """
    if not questions:
        raise AppErrorException(ErrCode.TASK_EMPTY_SPECS, "请先生成题目再保存")

    # child 归属校验（防越权把题卡挂到他人娃娃下）。
    if child_id is not None:
        require_owned_child(
            session=session,
            owner_id=parent_id,
            child_id=child_id,
            code=ErrCode.TASK_CHILD_NOT_OWNED,
            message="该娃娃不属于你的账号",
        )

    # 已生成题卡 → TaskQuestion 草稿项（不预写 Question，与 batch-generate 一致）。
    draft_questions: list[TaskQuestion] = []
    for q in questions:
        if not isinstance(q, dict):
            continue
        draft_questions.append(
            TaskQuestion(
                task_id=None,  # 由 batch_generate_task 回填
                question_id=None,  # R-Q1=c：草稿期不入题库
                subject=str(q.get("subject", "")),
                grade=int(q.get("grade", 0) or 0),
                knowledge_point=str(q.get("knowledge_point", "")),
                qtype=str(q.get("qtype", "open")),
                stem=str(q.get("stem", "")),
                options=q.get("options"),  # list[str] | None
                answer=q.get("answer"),
                explanation=q.get("explanation") or "",
                difficulty=str(q.get("difficulty") or "medium"),
            )
        )
    if not draft_questions:
        raise AppErrorException(ErrCode.TASK_EMPTY_SPECS, "生成的题目为空，无法保存")

    task = batch_generate_task(
        session=session,
        parent_id=parent_id,
        title=title,
        child_id=child_id,
        specs_dicts=specs,
        task_questions=draft_questions,
        focus_interest=focus_interest,
        model=model,
    )
    return task_to_resp(
        task, get_task_questions(session=session, task_id=task.id), include_answer=True
    )


def task_detail(*, session: Session, parent: User, task_id: UUID) -> TaskResp:
    """家长查单个 Task（草稿 / 锁定 / 派发 / 完成 都能看）。"""
    task = _owned_task(session=session, parent=parent, task_id=task_id)
    tqs = get_task_questions(session=session, task_id=task.id)
    # 家长端：草稿/锁定/派发后都能看到答案（审阅 + 核查）。
    include_answer = task.status in ("draft", "ready") or task.parent_id == parent.id
    return task_to_resp(task, tqs, include_answer=include_answer)


def promote_one(
    *, session: Session, parent: User, task_id: UUID, tq_id: UUID
) -> QuestionResp:
    """草稿题 → 加入题库（R-Q1=c：写 Question 行并回填 question_id）。幂等。"""
    task = _owned_task(session=session, parent=parent, task_id=task_id)
    _require_draft(task)
    _draft_item(session=session, task=task, tq_id=tq_id)
    updated = promote_task_question(session=session, tq_id=tq_id)
    if updated is None:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    return question_to_resp(updated, include_answer=True)


def promote_all(*, session: Session, parent: User, task_id: UUID) -> TaskResp:
    """一键把当前草稿所有未入库的题批量加入题库。已入库的跳过（幂等）。"""
    task = _owned_task(session=session, parent=parent, task_id=task_id)
    _require_draft(task)
    for tq in get_task_questions(session=session, task_id=task.id):
        if tq.question_id is None:
            promote_task_question(session=session, tq_id=tq.id)
    tqs = get_task_questions(session=session, task_id=task.id)
    return task_to_resp(task, tqs, include_answer=True)


def add_from_bank(
    *, session: Session, parent: User, task_id: UUID, question_ids: list[UUID]
) -> TaskResp:
    """选项 B：把题库题追加到已有草稿任务（仅 draft；同题去重；越权题忽略）。"""
    task = _owned_task(session=session, parent=parent, task_id=task_id)
    _require_draft(task)
    if not question_ids:
        raise AppErrorException(ErrCode.TASK_EMPTY_SPECS, "请至少选择一道题")
    updated = add_bank_questions_to_task(
        session=session, task_id=task.id, question_ids=question_ids
    )
    if updated is None:
        raise AppErrorException(ErrCode.TASK_NOT_FOUND, "任务不存在")
    return task_to_resp(
        updated,
        get_task_questions(session=session, task_id=updated.id),
        include_answer=True,
    )


def remove_one(*, session: Session, parent: User, task_id: UUID, tq_id: UUID) -> None:
    """删除草稿项。R-Q5=b：同时物理删关联 Question 行（若 question_id 非空）。"""
    task = _owned_task(session=session, parent=parent, task_id=task_id)
    _require_draft(task)
    _draft_item(session=session, task=task, tq_id=tq_id)
    if not remove_task_question(session=session, tq_id=tq_id):
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")


def regenerate_one(
    *, session: Session, parent: User, task_id: UUID, tq_id: UUID
) -> QuestionResp:
    """单题重生成：沿用原题的 subject/grade/knowledge_point/qtype/difficulty 拉新。"""
    task = _owned_task(session=session, parent=parent, task_id=task_id)
    _require_draft(task)
    tq = _draft_item(session=session, task=task, tq_id=tq_id)
    # 沿用本任务所选模型（无则出题核心失败并抛 LLM_UNAVAILABLE）；与整卷重生成保持一致。
    engine = resolve_engine(task.model, parent_id=parent.id, session=session)
    # 单题重生成复现兴趣设定：沿用整卷聚焦主题的轮询分配（按当前题序），否则轻融入画像。
    interests_pool = _extract_interests_pool(
        session.get(User, task.child_id) if task.child_id else None
    )
    focus: str | None = None
    focus_interests = task.focus_interest
    if focus_interests:
        tqs = get_task_questions(session=session, task_id=task.id)
        try:
            qi = next(k for k, t in enumerate(tqs) if t.id == tq.id)
        except StopIteration:
            qi = 0
        focus = focus_interests[qi % len(focus_interests)]
    g = _gen_question(
        engine,
        subject=tq.subject,
        grade=tq.grade,
        knowledge_point=tq.knowledge_point,
        qtype=tq.qtype,
        difficulty=tq.difficulty or "medium",
        interests=interests_pool if focus is None else None,
        focus_interest=focus,
    )
    new_q = Question(
        subject=g.subject, grade=g.grade, knowledge_point=g.knowledge_point,
        qtype=g.qtype, stem=g.stem, options=g.options, answer=g.answer,
        explanation=g.explanation, difficulty=g.difficulty,
    )
    updated = regenerate_one_task_question(session=session, tq_id=tq_id, gen_question=new_q)
    if updated is None:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    return question_to_resp(updated, include_answer=True)


def regenerate_all(*, session: Session, parent: User, task_id: UUID) -> TaskResp:
    """整卷重生成（R-Q2=c）：按 Task.specs 原规格重跑，全量替换草稿项。

    若 Task.specs 为空（非本版流程创建的草稿），抛 VALIDATION 错误，要求家长
    返回出题页重新生成。
    """
    task = _owned_task(session=session, parent=parent, task_id=task_id)
    _require_draft(task)
    specs = task.specs
    if not specs:
        raise AppErrorException(
            ErrCode.TASK_EMPTY_SPECS, "当前草稿无生成规格，无法整卷重生成，请返回出题页重新创建"
        )
    # 整卷重生成复现兴趣设定（WF-3/WF-4）：沿用原娃娃画像轻融入 + 原聚焦主题。
    child = session.get(User, task.child_id) if task.child_id else None
    interests_pool = _extract_interests_pool(child)
    # 沿用本任务所选模型（无则出题核心失败并抛 LLM_UNAVAILABLE）。
    engine = resolve_engine(task.model, parent_id=parent.id, session=session)
    new_tqs = _generate_task_questions_for_specs(
        specs, interests=interests_pool, focus_interests=task.focus_interest, engine=engine
    )
    updated = regenerate_all_task_questions(
        session=session, task_id=task.id, new_task_questions=new_tqs
    )
    if updated is None:
        raise AppErrorException(
            ErrCode.TASK_STATUS_DRAFT_REQUIRED, "仅草稿态可整卷重生成"
        )
    return task_to_resp(
        updated, get_task_questions(session=session, task_id=updated.id), include_answer=True
    )


def edit_question(
    *, session: Session, parent: User, task_id: UUID, tq_id: UUID, edits: dict
) -> QuestionResp:
    """编辑草稿快照题（仅 draft 态，R-Q4：仅题干/选项/答案/解析，知识点/题型等过滤）。"""
    task = _owned_task(session=session, parent=parent, task_id=task_id)
    _require_draft(task)
    _draft_item(session=session, task=task, tq_id=tq_id)
    # 严格按 R-Q4：只允许 stem/options/answer/explanation；剔除 knowledge_point 等。
    allowed = {"stem", "options", "answer", "explanation"}
    filtered = {k: v for k, v in edits.items() if k in allowed}
    updated = update_task_question(session=session, tq_id=tq_id, edits=filtered)
    if updated is None:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    return question_to_resp(updated, include_answer=True)


def confirm(*, session: Session, parent: User, task_id: UUID) -> TaskResp:
    """draft → ready：锁定题集成卷。

    R-Q1=c 业务前自动补齐：锁定前把所有未入题库的草稿题批量 promote 入题库
    （家长"锁定成卷"即表示已经认可这些题可入题库，无需额外两次点击）。
    """
    task = _owned_task(session=session, parent=parent, task_id=task_id)
    _require_draft(task)
    # 自动 promote-all：未入题库的题在锁定前一次性写 Question + 回填 question_id
    for tq in get_task_questions(session=session, task_id=task.id):
        if tq.question_id is None:
            promote_task_question(session=session, tq_id=tq.id)
    updated = confirm_task(session=session, task_id=task_id)
    return task_to_resp(
        updated, get_task_questions(session=session, task_id=updated.id), include_answer=True
    )


def assign(
    *, session: Session, parent: User, task_id: UUID, child_id: UUID
) -> TaskResp:
    """ready → assigned：派发给娃娃，绑 child_id。"""
    require_owned_child(
        session=session,
        owner_id=parent.id,
        child_id=child_id,
        code=ErrCode.TASK_CHILD_NOT_OWNED,
        message="该娃娃不属于你的账号",
    )
    _owned_task(session=session, parent=parent, task_id=task_id)
    updated = assign_task(session=session, task_id=task_id, child_id=child_id)
    if updated is None:
        raise AppErrorException(
            ErrCode.TASK_STATUS_READY_REQUIRED, "Task 不在 ready 态，无法派发"
        )
    return task_to_resp(
        updated, get_task_questions(session=session, task_id=task_id), include_answer=True
    )


def discard(*, session: Session, parent: User, task_id: UUID) -> None:
    """作废草稿（draft/ready 可删，assigned/done 不允许）。

    R-Q5=b：级联删所有草稿 TaskQuestion 及其已入题库的 Question 行。
    """
    task = _owned_task(session=session, parent=parent, task_id=task_id)
    if task.status in ("assigned", "done"):
        raise AppErrorException(
            ErrCode.FORBIDDEN, "已派发/完成的任务不可作废，请在娃娃端处理"
        )
    if not discard_draft_task(session=session, task_id=task_id):
        raise AppErrorException(ErrCode.TASK_NOT_FOUND, "作废失败，任务不存在或状态不允许")


def _answerable_task(*, session: Session, user: User, task_id: UUID) -> tuple[Task, UUID]:
    """取可作答/打卡的任务并解析「实际作答的娃娃 id」。

    娃娃只能答派给自己的任务；家长代答需证明那是自家娃娃。返回 ``(task, actor_child_id)``。
    """
    task = session.get(Task, task_id)
    if task is None:
        raise AppErrorException(ErrCode.TASK_NOT_FOUND, "任务不存在")
    if task.child_id is None:
        raise AppErrorException(ErrCode.TASK_NOT_ASSIGNED, "Task 尚未派发给任何娃娃")
    if user.role == "child":
        if task.child_id != user.id:
            raise AppErrorException(ErrCode.TASK_NOT_OWNED, "这不是派发给你的任务")
        return task, user.id
    require_owned_child(
        session=session,
        owner_id=user.id,
        child_id=task.child_id,
        code=ErrCode.TASK_NOT_YOUR_CHILD,
        message="这不是你家娃娃的任务",
    )
    return task, task.child_id


def answer(
    *,
    session: Session,
    user: User,
    task_id: UUID,
    question_id: UUID,
    student_answer: str,
) -> AnswerResult:
    """娃娃答题 / 家长代答。身份 + 状态双校验，作答/错题归集统一挂 task.child_id。"""
    task, actor_child_id = _answerable_task(session=session, user=user, task_id=task_id)
    if task.status not in ("assigned", "done"):
        raise AppErrorException(
            ErrCode.TASK_STATUS_ASSIGNED_REQUIRED,
            "Task 未处于 assigned/done 态，无法作答",
        )

    # question_id 理论上是源 Question.id，但草稿期可能未入库（question_id 为 null）。
    # 两种口径兼容：若 TaskQuestion.question_id == question_id，则命中；
    # 否则 fallback 按「TaskQuestion.id == question_id」也能命中（review 新口径）。
    tq = session.exec(
        select(TaskQuestion).where(
            TaskQuestion.task_id == task_id,
            (TaskQuestion.question_id == question_id)
            | (TaskQuestion.id == question_id),
        )
    ).first()
    if tq is None:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不在当前任务里")

    result = Grader(build_provider()).grade(question=tq, student_answer=student_answer)
    record_question_id = tq.question_id or question_id
    create_answer_record(
        session=session,
        question_id=record_question_id,
        child_id=actor_child_id,
        student_answer=student_answer,
        correct=result["correct"],
        score=result["score"],
    )
    if not result["correct"]:
        upsert_wrong_question(
            session=session,
            question_id=record_question_id,
            child_id=actor_child_id,
        )
    return AnswerResult(
        correct=result["correct"],
        score=result["score"],
        explanation=tq.explanation or result.get("explanation", ""),
    )


def checkin(*, session: Session, user: User, task_id: UUID) -> CheckinResult:
    """娃娃打卡 / 家长代打卡。"""
    task, actor_child_id = _answerable_task(session=session, user=user, task_id=task_id)
    if task.status != "assigned":
        raise AppErrorException(
            ErrCode.TASK_STATUS_ASSIGNED_REQUIRED, "仅 assigned 态可打卡"
        )
    cin = create_checkin(
        session=session,
        child_id=actor_child_id,
        task_id=task.id,
        checkin_date=date.today(),
    )
    task.status = "done"
    session.add(task)
    session.commit()
    return CheckinResult(ok=True, checkin_date=cin.checkin_date)
