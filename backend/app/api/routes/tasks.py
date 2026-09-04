import asyncio
from datetime import date
from uuid import UUID

from fastapi import APIRouter, Query, status
from sqlmodel import select

from app.ai import mock_question, resolve_engine
from app.ai.subagents import build_subagent
from app.ai.subagents.base import SubAgentContext
from app.api.deps import CurrentChild, CurrentParent, CurrentUser, SessionDep
from app.core.errors import AppErrorException, ErrCode
from app.crud import (
    _SENTINEL_NO_QUESTIONS,
    _SENTINEL_PROMOTE_REQUIRED,
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
    get_task,
    get_task_question,
    get_task_questions,
    list_wrong_questions,
    promote_task_question,
    regenerate_all_task_questions,
    regenerate_one_task_question,
    remove_task_question,
    update_task_question,
    upsert_wrong_question,
)
from app.domain import Grader, build_provider, build_retriever
from app.domain.provider import GeneratedQuestion
from app.models import (
    AnswerResult,
    AnswerSubmit,
    BankQuestionsAdd,
    CheckinResult,
    ProgressResp,
    Question,
    QuestionResp,
    Task,
    TaskBatchCreate,
    TaskFromBankCreate,
    TaskFromGenerated,
    TaskQuestion,
    TaskQuestionEdit,
    TaskResp,
    TaskSpec,
    User,
    WrongQuestion,
    WrongQuestionResp,
)

router = APIRouter(prefix="/tasks", tags=["tasks"])

# ⚠️ 路由顺序：静态路径（/today、/wrong-questions、/children/*）必须放在
# 带路径参数的路由（/{task_id}、/{task_id}/questions/...）前面，否则
# FastAPI 会把 "/today" 当作 task_id="today" 命中 get_task_detail，
# 走到 CurrentParent 依赖而娃娃 token 报 AUTH_30004（角色错）。


def _tq_to_resp(tq: TaskQuestion, *, include_answer: bool) -> QuestionResp:
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


def _task_to_resp(
    task: Task, questions: list[TaskQuestion], *, include_answer: bool
) -> TaskResp:
    return TaskResp(
        id=task.id,
        title=task.title,
        status=task.status,
        specs=task.specs,
        questions=[_tq_to_resp(q, include_answer=include_answer) for q in questions],
        child_id=task.child_id,
        created_at=task.created_at,
    )


def _wrong_to_resp(
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


def _parent_owns_task(*, task: Task | None, parent: User) -> Task:
    if task is None or task.parent_id != parent.id:
        raise AppErrorException(ErrCode.TASK_NOT_FOUND, "任务不存在")
    return task


def _require_draft(task: Task) -> None:
    if task.status != "draft":
        raise AppErrorException(
            ErrCode.TASK_STATUS_DRAFT_REQUIRED, "仅草稿态可执行该操作"
        )


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
    """出题单题：经「出题」业务 SubAgent 派发（ADR-0021），内部接 RAG + 学科 Persona。

    统一单栈（迁移 08b）：MockProvider / LangChainProvider 已退役，mock 分支即 flow 内的
    _mock_question（确定性假数据）；真实模型产出不安全（check_output 未过）时同样回退 mock，
    保证题量完整且不落库违规内容。

    engine 为 None（无真实引擎）时直接走确定性 mock，与历史行为一致，不重复解析引擎。
    """
    g = None
    if engine is not None:
        agent = build_subagent(
            "question",
            provider=build_provider(),
            retriever=build_retriever(),
            engine=engine,
        )
        if agent is not None:
            try:
                g = asyncio.run(
                    agent.handle(
                        {
                            "subject": subject,
                            "grade": grade,
                            "knowledge_point": knowledge_point,
                            "qtype": qtype,
                            "difficulty": difficulty,
                            "interests": interests,
                            "focus_interest": focus_interest,
                        },
                        SubAgentContext(
                            subject=subject,
                            grade=grade,
                            knowledge_point=knowledge_point,
                        ),
                    )
                )
            except Exception:
                g = None
    if g is None:
        q = mock_question(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            qtype=qtype,
            difficulty=difficulty,
            interests=interests,
            focus_interest=focus_interest,
        )
        return GeneratedQuestion(
            subject=q.subject,
            grade=q.grade,
            knowledge_point=q.knowledge_point,
            qtype=q.qtype,
            stem=q.stem,
            options=q.options,
            answer=q.answer,
            explanation=q.explanation,
            difficulty=q.difficulty,
        )
    return g


def _generate_task_questions_for_specs(
    specs: list[TaskSpec] | list[dict],
    *,
    interests: list[str] | None = None,
    focus_interests: list[str] | None = None,
    engine=None,
) -> list[TaskQuestion]:
    """调用出题引擎产草稿 TaskQuestion（R-Q1=c：不写 Question 表）。

    specs 可以是 TaskSpec 对象（来自请求体的 Pydantic）或 dict（来自 Task.specs 持久化）。
    engine 为 resolve_engine 解析结果（None = 无真实引擎，回退 mock 分支）。

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
                    task_id=None,  # 由 crud.batch_generate_task / regenerate_all 回填
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


# ───────────────────────── 草稿生成 + 草稿动作 ─────────────────────────


@router.post("/batch-generate", response_model=TaskResp, status_code=status.HTTP_201_CREATED)
def batch_generate(
    *, session: SessionDep, parent: CurrentParent, payload: TaskBatchCreate
) -> TaskResp:
    """多学科一卷批量生成（草稿页入口）。

    R-Q1=c：只写 TaskQuestion 草稿项，不预写 Question；原始规格存 Task.specs
    以便整卷重生成。返回 draft 态 Task（家长端可见答案，供审阅）。
    """
    if not payload.specs:
        raise AppErrorException(ErrCode.TASK_EMPTY_SPECS, "生成规格 specs 不能为空")

    child_id = payload.child_id
    interests_pool: list[str] | None = None
    if child_id is not None:
        child = session.get(User, child_id)
        if child is None or child.parent_id != parent.id:
            raise AppErrorException(
                ErrCode.TASK_CHILD_NOT_OWNED, "该娃娃不属于你的账号"
            )
        interests_pool = _extract_interests_pool(child)

    # 兴趣题模式（WF-4）：显式聚焦主题直接来自请求；否则后端自动轻融入画像。
    focus_interests = payload.focus_interest
    # 多模型（票据 08）：把家长所选模型（内置 id / ModelConfig id）解析为真实引擎；
    # 解析不到（含缺省）则走 build_provider 回退（mock 分支）。
    engine = resolve_engine(payload.model, parent_id=parent.id, session=session)
    draft_questions = _generate_task_questions_for_specs(
        payload.specs,
        interests=interests_pool,
        focus_interests=focus_interests,
        engine=engine,
    )
    specs_dicts = [s.model_dump() for s in payload.specs]
    task = batch_generate_task(
        session=session,
        parent_id=parent.id,
        title=payload.title,
        child_id=child_id,
        specs_dicts=specs_dicts,
        task_questions=draft_questions,
        focus_interest=focus_interests,
        model=payload.model,
    )
    task_questions = get_task_questions(session=session, task_id=task.id)
    return _task_to_resp(task, task_questions, include_answer=True)


# 兼容老单学科端点（内部转调 batch-generate）。保留不删，避免老前端 / 测试坏掉。
@router.post("", response_model=TaskResp, status_code=status.HTTP_201_CREATED)
def create_single_subject_task(
    *, session: SessionDep, parent: CurrentParent, title: str, child_id: UUID,
    subject: str, grade: int, knowledge_point: str, qtype: str, difficulty: str = "medium",
    count: int = 5,
) -> TaskResp:
    spec = TaskSpec(
        subject=subject, grade=grade, knowledge_point=knowledge_point,
        qtype=qtype, difficulty=difficulty, count=count,
    )
    payload = TaskBatchCreate(title=title, child_id=child_id, specs=[spec])
    return batch_generate(session=session, parent=parent, payload=payload)  # type: ignore[call-arg]


# ───────────────────────── 题库复用闭环（选项 A / 草稿选择器） ─────────────────────────


@router.post("/from-bank", response_model=TaskResp, status_code=status.HTTP_201_CREATED)
def create_from_bank(
    *, session: SessionDep, parent: CurrentParent, payload: TaskFromBankCreate
) -> TaskResp:
    """选项 A：从题库新建任务（draft）。深拷贝选中题为 TaskQuestion 并回填 question_id。"""
    if not payload.question_ids:
        raise AppErrorException(ErrCode.TASK_EMPTY_SPECS, "请至少选择一道题")
    task = create_task_from_bank(
        session=session,
        parent_id=parent.id,
        title=payload.title,
        child_id=payload.child_id,
        question_ids=payload.question_ids,
    )
    return _task_to_resp(
        task, get_task_questions(session=session, task_id=task.id), include_answer=True
    )


@router.post("/from-generated", response_model=TaskResp, status_code=status.HTTP_201_CREATED)
def create_from_generated(
    *, session: SessionDep, parent: CurrentParent, payload: TaskFromGenerated
) -> TaskResp:
    """流式题卡落库：把 /ai/tasks/generate 逐题返回的题卡一次性建为 draft 任务。

    用于「生成任务」按钮的流式渲染 + 落库两步法：前端先连流式端点逐题渲染题卡
    （消除超时），流结束后再把已生成题卡 POST 到此端点落库，避免二次生成。
    `questions` 已是前端渲染用的同一批题卡（QuestionPreview.toJson，snake_case），
    此处仅做归属/非空校验并构造成 TaskQuestion 落库，不重新调用出题引擎。
    """
    if not payload.questions:
        raise AppErrorException(ErrCode.TASK_EMPTY_SPECS, "请先生成题目再保存")

    # child 归属校验（防越权把题卡挂到他人娃娃下）。
    if payload.child_id is not None:
        child = session.get(User, payload.child_id)
        if child is None or child.parent_id != parent.id:
            raise AppErrorException(
                ErrCode.TASK_CHILD_NOT_OWNED, "该娃娃不属于你的账号"
            )

    # 已生成题卡 → TaskQuestion 草稿项（不预写 Question，与 batch-generate 一致）。
    draft_questions: list[TaskQuestion] = []
    for q in payload.questions:
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

    specs_dicts = [s.model_dump() for s in payload.specs]
    task = batch_generate_task(
        session=session,
        parent_id=parent.id,
        title=payload.title,
        child_id=payload.child_id,
        specs_dicts=specs_dicts,
        task_questions=draft_questions,
        focus_interest=payload.focus_interest,
        model=payload.model,
    )
    task_questions = get_task_questions(session=session, task_id=task.id)
    return _task_to_resp(task, task_questions, include_answer=True)


@router.get("", response_model=list[TaskResp])
def list_parent_tasks(
    *,
    session: SessionDep,
    parent: CurrentParent,
    status_filter: str | None = Query(None, alias="status"),
) -> list[TaskResp]:
    """家长任务列表（供选项 B 草稿选择器拉取 draft 列表）。"""
    stmt = select(Task).where(Task.parent_id == parent.id)
    if status_filter:
        stmt = stmt.where(Task.status == status_filter)
    tasks = session.exec(stmt.order_by(Task.created_at.desc())).all()
    return [
        _task_to_resp(
            t, get_task_questions(session=session, task_id=t.id), include_answer=True
        )
        for t in tasks
    ]


# ───────────────────────── 静态路径：娃娃端今日任务 / 错题 / 家长错题 / 进度 ──
# 必须放在 /{task_id} 等参数路由之前，否则 FastAPI 把 "/today" 等当 task_id 匹配。


@router.get("/today", response_model=list[TaskResp])
def today(*, session: SessionDep, child: CurrentChild) -> list[TaskResp]:
    tasks = get_child_tasks_today(session=session, child_id=child.id)
    return [
        _task_to_resp(
            t,
            get_task_questions(session=session, task_id=t.id),
            include_answer=False,
        )
        for t in tasks
    ]


@router.get("/wrong-questions", response_model=list[WrongQuestionResp])
def my_wrong_questions(
    *, session: SessionDep, child: CurrentChild
) -> list[WrongQuestionResp]:
    """娃娃自查错题本：不含答案（复习走 /review/*）。"""
    rows = list_wrong_questions(session=session, child_id=child.id)
    return [_wrong_to_resp(wq, q, include_answer=False) for wq, q in rows]


@router.get("/children/{child_id}/wrong-questions", response_model=list[WrongQuestionResp])
def child_wrong_questions(
    *, session: SessionDep, parent: CurrentParent, child_id: UUID
) -> list[WrongQuestionResp]:
    """家长查某娃娃错题本（含答案/解析，供核查）。"""
    child = session.get(User, child_id)
    if child is None or child.parent_id != parent.id:
        raise AppErrorException(ErrCode.TASK_NOT_YOUR_CHILD, "该娃娃不属于你的账号")
    rows = list_wrong_questions(session=session, child_id=child_id)
    return [_wrong_to_resp(wq, q, include_answer=True) for wq, q in rows]


@router.get("/children/{child_id}/progress", response_model=ProgressResp)
def progress(
    *, session: SessionDep, parent: CurrentParent, child_id: UUID
) -> ProgressResp:
    child = session.get(User, child_id)
    if child is None or child.parent_id != parent.id:
        raise AppErrorException(ErrCode.TASK_NOT_YOUR_CHILD, "该娃娃不属于你的账号")
    total, correct, checkin_days, streak = get_progress(
        session=session, child_id=child.id
    )
    accuracy = round(correct / total, 2) if total else 0.0
    return ProgressResp(
        child_id=child.id,
        total=total,
        correct=correct,
        accuracy=accuracy,
        streak_days=streak,
        checkin_days=checkin_days,
    )


# ───────────────────────── 参数路径：单个 Task 详情 / 草稿动作 ──────────────────


@router.get("/{task_id}", response_model=TaskResp)
def get_task_detail(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID
) -> TaskResp:
    """家长查单个 Task（草稿 / 锁定 / 派发 / 完成 都能看）。"""
    task = _parent_owns_task(task=get_task(session=session, task_id=task_id), parent=parent)
    tqs = get_task_questions(session=session, task_id=task.id)
    # 家长端：草稿/锁定/派发后都能看到答案（审阅 + 核查）。
    include_answer = task.status in ("draft", "ready") or task.parent_id == parent.id
    return _task_to_resp(task, tqs, include_answer=include_answer)


@router.post("/{task_id}/questions/{tq_id}/promote", response_model=QuestionResp)
def promote_one(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID, tq_id: UUID
) -> QuestionResp:
    """草稿题 → 加入题库（R-Q1=c：写 Question 行并回填 question_id）。幂等。"""
    task = _parent_owns_task(task=get_task(session=session, task_id=task_id), parent=parent)
    _require_draft(task)
    tq = get_task_question(session=session, tq_id=tq_id)
    if tq is None or tq.task_id != task.id:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    updated = promote_task_question(session=session, tq_id=tq_id)
    if updated is None:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    return _tq_to_resp(updated, include_answer=True)


@router.post("/{task_id}/promote-all", response_model=TaskResp)
def promote_all(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID
) -> TaskResp:
    """一键把当前草稿所有未入库的题批量加入题库。已入库的跳过（幂等）。"""
    task = _parent_owns_task(task=get_task(session=session, task_id=task_id), parent=parent)
    _require_draft(task)
    for tq in get_task_questions(session=session, task_id=task.id):
        if tq.question_id is None:
            promote_task_question(session=session, tq_id=tq.id)
    tqs = get_task_questions(session=session, task_id=task.id)
    return _task_to_resp(task, tqs, include_answer=True)


@router.post("/{task_id}/questions/from-bank", response_model=TaskResp)
def add_from_bank(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID, payload: BankQuestionsAdd
) -> TaskResp:
    """选项 B：把题库题追加到已有草稿任务（仅 draft；同题去重；越权题忽略）。"""
    task = _parent_owns_task(task=get_task(session=session, task_id=task_id), parent=parent)
    _require_draft(task)
    if not payload.question_ids:
        raise AppErrorException(ErrCode.TASK_EMPTY_SPECS, "请至少选择一道题")
    updated = add_bank_questions_to_task(
        session=session, task_id=task.id, question_ids=payload.question_ids
    )
    if updated is None:
        raise AppErrorException(ErrCode.TASK_NOT_FOUND, "任务不存在")
    return _task_to_resp(
        updated,
        get_task_questions(session=session, task_id=updated.id),
        include_answer=True,
    )
def remove_one(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID, tq_id: UUID
) -> None:
    """删除草稿项。R-Q5=b：同时物理删关联 Question 行（若 question_id 非空）。"""
    task = _parent_owns_task(task=get_task(session=session, task_id=task_id), parent=parent)
    _require_draft(task)
    tq = get_task_question(session=session, tq_id=tq_id)
    if tq is None or tq.task_id != task.id:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    ok = remove_task_question(session=session, tq_id=tq_id)
    if not ok:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")


@router.post("/{task_id}/questions/{tq_id}/regenerate", response_model=QuestionResp)
def regenerate_one(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID, tq_id: UUID
) -> QuestionResp:
    """单题重生成：沿用原题的 subject/grade/knowledge_point/qtype/difficulty 拉新。"""
    task = _parent_owns_task(task=get_task(session=session, task_id=task_id), parent=parent)
    _require_draft(task)
    tq = get_task_question(session=session, tq_id=tq_id)
    if tq is None or tq.task_id != task.id:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    # 沿用本任务所选模型（无则回退 mock 分支）；与整卷重生成保持一致。
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
    updated = regenerate_one_task_question(
        session=session, tq_id=tq_id, gen_question=new_q
    )
    if updated is None:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    return _tq_to_resp(updated, include_answer=True)


@router.post("/{task_id}/regenerate", response_model=TaskResp)
def regenerate_all(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID
) -> TaskResp:
    """整卷重生成（R-Q2=c）：按 Task.specs 原规格重跑，全量替换草稿项。

    若 Task.specs 为空（非本版流程创建的草稿），则抛 VALIDATION 错误，要求家长
    返回出题页重新生成。
    """
    task = _parent_owns_task(task=get_task(session=session, task_id=task_id), parent=parent)
    _require_draft(task)
    specs = task.specs
    if not specs:
        raise AppErrorException(
            ErrCode.TASK_EMPTY_SPECS, "当前草稿无生成规格，无法整卷重生成，请返回出题页重新创建"
        )
    # 整卷重生成复现兴趣设定（WF-3/WF-4）：沿用原娃娃画像轻融入 + 原聚焦主题。
    child = session.get(User, task.child_id) if task.child_id else None
    interests_pool = _extract_interests_pool(child)
    focus_interests = task.focus_interest
    # 沿用本任务所选模型（无则回退 mock 分支）。
    engine = resolve_engine(task.model, parent_id=parent.id, session=session)
    new_tqs = _generate_task_questions_for_specs(
        specs,
        interests=interests_pool,
        focus_interests=focus_interests,
        engine=engine,
    )
    updated = regenerate_all_task_questions(
        session=session, task_id=task.id, new_task_questions=new_tqs
    )
    if updated is None:
        raise AppErrorException(
            ErrCode.TASK_STATUS_DRAFT_REQUIRED, "仅草稿态可整卷重生成"
        )
    tqs = get_task_questions(session=session, task_id=updated.id)
    return _task_to_resp(updated, tqs, include_answer=True)


@router.put("/{task_id}/questions/{tq_id}", response_model=QuestionResp)
def edit_question(
    *,
    session: SessionDep,
    parent: CurrentParent,
    task_id: UUID,
    tq_id: UUID,
    edits: TaskQuestionEdit,
) -> QuestionResp:
    """编辑草稿快照题（仅 draft 态，R-Q4：仅题干/选项/答案/解析，知识点/题型等过滤）。"""
    task = _parent_owns_task(task=get_task(session=session, task_id=task_id), parent=parent)
    _require_draft(task)
    tq = get_task_question(session=session, tq_id=tq_id)
    if tq is None or tq.task_id != task.id:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    edit_dict = edits.model_dump(exclude_unset=True)
    # 严格按 R-Q4：只允许 stem/options/answer/explanation；剔除 knowledge_point 等。
    allowed = {"stem", "options", "answer", "explanation"}
    edit_dict = {k: v for k, v in edit_dict.items() if k in allowed}
    updated = update_task_question(session=session, tq_id=tq_id, edits=edit_dict)
    if updated is None:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    return _tq_to_resp(updated, include_answer=True)


@router.post("/{task_id}/confirm", response_model=TaskResp)
def confirm(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID
) -> TaskResp:
    """draft → ready：锁定题集成卷。

    R-Q1=c 业务前自动补齐：锁定前把所有未入题库的草稿题批量 promote 入题库
    （家长"锁定成卷"即表示已经认可这些题可入题库，无需额外两次点击）。
    """
    task = _parent_owns_task(task=get_task(session=session, task_id=task_id), parent=parent)
    _require_draft(task)
    # 自动 promote-all：未入题库的题在锁定前一次性写 Question + 回填 question_id
    for tq in get_task_questions(session=session, task_id=task.id):
        if tq.question_id is None:
            promote_task_question(session=session, tq_id=tq.id)
    updated = confirm_task(session=session, task_id=task_id)
    if updated is _SENTINEL_NO_QUESTIONS:
        raise AppErrorException(ErrCode.TASK_NO_QUESTIONS, "草稿没有题目，请先生成再锁定")
    if updated is _SENTINEL_PROMOTE_REQUIRED:
        # promote-all 跑完还没补全（理论不可达），抛明确错误
        raise AppErrorException(
            ErrCode.TASK_LOCK_REQUIRES_ALL_PROMOTED,
            "锁定失败：部分题目仍未加入题库，请重试",
        )
    if updated is None:
        raise AppErrorException(
            ErrCode.TASK_STATUS_DRAFT_REQUIRED, "仅草稿态可执行锁定"
        )
    tqs = get_task_questions(session=session, task_id=updated.id)
    return _task_to_resp(updated, tqs, include_answer=True)


@router.post("/{task_id}/assign", response_model=TaskResp)
def assign(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID, child_id: UUID
) -> TaskResp:
    """ready → assigned：派发给娃娃，绑 child_id。"""
    child = session.get(User, child_id)
    if child is None or child.parent_id != parent.id:
        raise AppErrorException(
            ErrCode.TASK_CHILD_NOT_OWNED, "该娃娃不属于你的账号"
        )
    _parent_owns_task(task=get_task(session=session, task_id=task_id), parent=parent)
    updated = assign_task(session=session, task_id=task_id, child_id=child_id)
    if updated is None:
        raise AppErrorException(
            ErrCode.TASK_STATUS_READY_REQUIRED, "Task 不在 ready 态，无法派发"
        )
    tqs = get_task_questions(session=session, task_id=task_id)
    return _task_to_resp(updated, tqs, include_answer=True)


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def discard(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID
) -> None:
    """作废草稿（draft/ready 可删，assigned/done 不允许）。

    R-Q5=b：级联删所有草稿 TaskQuestion 及其已入题库的 Question 行。
    """
    task = _parent_owns_task(task=get_task(session=session, task_id=task_id), parent=parent)
    if task.status in ("assigned", "done"):
        raise AppErrorException(
            ErrCode.FORBIDDEN, "已派发/完成的任务不可作废，请在娃娃端处理"
        )
    ok = discard_draft_task(session=session, task_id=task_id)
    if not ok:
        raise AppErrorException(ErrCode.TASK_NOT_FOUND, "作废失败，任务不存在或状态不允许")


# ───────────────────────── 答题 / 打卡 ─────────────────────────


@router.post("/{task_id}/answer", response_model=AnswerResult)
def answer_question(
    *, session: SessionDep, user: CurrentUser, task_id: UUID, submit: AnswerSubmit
) -> AnswerResult:
    """娃娃答题 / 家长代答。身份 + 状态双校验，作答/错题归集统一挂 task.child_id。"""
    task = get_task(session=session, task_id=task_id)
    if task is None:
        raise AppErrorException(ErrCode.TASK_NOT_FOUND, "任务不存在")
    if task.child_id is None:
        raise AppErrorException(
            ErrCode.TASK_NOT_ASSIGNED, "Task 尚未派发给任何娃娃"
        )
    if task.status not in ("assigned", "done"):
        raise AppErrorException(
            ErrCode.TASK_STATUS_ASSIGNED_REQUIRED,
            "Task 未处于 assigned/done 态，无法作答",
        )

    if user.role == "child":
        if task.child_id != user.id:
            raise AppErrorException(ErrCode.TASK_NOT_OWNED, "这不是派发给你的任务")
        actor_child_id = user.id
    else:  # parent
        child = session.get(User, task.child_id)
        if child is None or child.parent_id != user.id:
            raise AppErrorException(
                ErrCode.TASK_NOT_YOUR_CHILD, "这不是你家娃娃的任务"
            )
        actor_child_id = task.child_id

    # submit.question_id 理论上是源 Question.id，但草稿期可能未入库（question_id 为 null）。
    # 两种口径兼容：若 TaskQuestion.question_id == submit.question_id，则命中；
    # 否则 fallback 按「TaskQuestion.id == submit.question_id」也能命中（review 新口径）。
    tq = session.exec(
        select(TaskQuestion).where(
            TaskQuestion.task_id == task_id,
            (TaskQuestion.question_id == submit.question_id)
            | (TaskQuestion.id == submit.question_id),
        )
    ).first()
    if tq is None:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不在当前任务里")

    grader = Grader(build_provider())
    result = grader.grade(question=tq, student_answer=submit.student_answer)
    record_question_id = tq.question_id or submit.question_id
    create_answer_record(
        session=session,
        question_id=record_question_id,
        child_id=actor_child_id,
        student_answer=submit.student_answer,
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


@router.post("/{task_id}/checkin", response_model=CheckinResult)
def checkin(
    *, session: SessionDep, user: CurrentUser, task_id: UUID
) -> CheckinResult:
    """娃娃打卡 / 家长代打卡。"""
    task = get_task(session=session, task_id=task_id)
    if task is None:
        raise AppErrorException(ErrCode.TASK_NOT_FOUND, "任务不存在")
    if task.child_id is None:
        raise AppErrorException(ErrCode.TASK_NOT_ASSIGNED, "Task 尚未派发，无法打卡")
    if task.status != "assigned":
        raise AppErrorException(
            ErrCode.TASK_STATUS_ASSIGNED_REQUIRED, "仅 assigned 态可打卡"
        )

    if user.role == "child":
        if task.child_id != user.id:
            raise AppErrorException(ErrCode.TASK_NOT_OWNED, "这不是派发给你的任务")
        actor_child_id = user.id
    else:  # parent
        child_row = session.get(User, task.child_id)
        if child_row is None or child_row.parent_id != user.id:
            raise AppErrorException(
                ErrCode.TASK_NOT_YOUR_CHILD, "这不是你家娃娃的任务"
            )
        actor_child_id = task.child_id

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
