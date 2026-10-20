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

from collections.abc import AsyncIterator
from datetime import date
from uuid import UUID

from sqlmodel import Session, select

from agent_core.errors import ProviderRequestError
from agent_core.ports import RuntimeDeps
from agent_core.runtime import AgentRuntime
from agent_core.runtime_singleton import get_runtime
from agent_core.subagent import SubAgentContext
from app.core.ai_plumbing import build_ai_provider
from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned, require_owned_student
from app.core.pagination import clamp_page_size, encode_cursor
from app.db.models import (
    Question,
    Role,
    Task,
    TaskAssignment,
    TaskQuestion,
    User,
    WrongQuestion,
)
from app.domain import Grader, build_retriever
from app.domain.structured import normalize_options, option_texts
from app.features.materials.figure_stamp import (
    allowed_keys_for_question,
    stamp_figures,
)
from app.features.materials.scene_fusion import (
    build_scene_spec_for_question,
    scene_spec_for_read,
)
from app.features.tasks.repository import (
    add_bank_questions_to_task,
    assign_task,
    batch_generate_task,
    bulk_create_assignments,
    cancel_assignments,
    confirm_task,
    count_assignments,
    count_completed_assignments,
    count_incomplete_assignments_by_teacher,
    count_tasks_by_teacher,
    count_tasks_by_teacher_grouped,
    count_wrong_questions,
    create_answer_record,
    create_checkin,
    create_task_assignment,
    create_task_from_bank,
    discard_draft_task,
    get_progress,
    get_student_tasks_today,
    get_task_question,
    get_task_questions,
    is_student_assigned,
    list_tasks_by_teacher,
    mark_assignment_completed,
    promote_task_question,
    rejoin_wrong_question,
    remove_task_question,
    task_question_breakdown,
    update_task_meta,
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
    TaskCounts,
    TaskGenerateReq,
    TaskListResp,
    TaskResp,
    TaskSummaryResp,
    TeacherTodoSummary,
    WrongQuestionListResp,
    WrongQuestionResp,
)

# ───────────────────────── 序列化（ORM → 响应模型） ─────────────────────────


def question_to_resp(tq: TaskQuestion, *, include_answer: bool) -> QuestionResp:
    """TaskQuestion → QuestionResp；``include_answer=False`` 抹掉答案（学生端防作弊）。"""
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
        semester=tq.semester,
        multi=tq.multi,
        # 交互讲解快照（ADR-0061 §M）：草稿期算好的那份直接下发，无需再查知识点。
        scene_spec=tq.scene_spec,
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
        student_id=task.student_id,
        created_at=task.created_at,
    )


def wrong_question_to_resp(
    wq: WrongQuestion,
    q: Question,
    *,
    session: Session,
    include_answer: bool,
    scene_cache: dict | None = None,
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
        semester=q.semester,
        wrong_count=wq.wrong_count,
        first_wrong_at=wq.first_wrong_at,
        review_stage=wq.review_stage,
        due_at=wq.due_at,
        multi=q.multi,
        graduated_at=wq.graduated_at,
        # 交互讲解（ADR-0061 §U）：走与题库/错题本共用的 ``scene_spec_for_read``
        # —— 快照优先（出题时算好的那份贴合本题图形/角度，模板后续改动不影响
        # 它）；老数据没有快照才实时解析（按知识点 + 学期找模板，再无则图库兜底）。
        scene_spec=scene_spec_for_read(
            session,
            snapshot=q.scene_spec,
            teacher_id=q.teacher_id,
            subject=q.subject,
            grade=q.grade,
            knowledge_point=q.knowledge_point,
            semester=q.semester,
            cache=scene_cache,
        ),
    )


def _valid_choice_options(options: object) -> bool:
    """选择题必须有 ≥2 个非空选项，否则落库后学生端会退化成文本框、无法选择。

    这是「选择题必须可选项」的硬约束：模型偶发会把 ``qtype`` 标成 ``choice`` 却
    不给 ``options``（或不给够），若照存，今日练习里就变成填空题输入框。在落库前
    拦掉，让教师重新生成，而不是存一份答不了的残缺题。

    判「非空」只看**选项文字**（``option_texts``，ADR-0089）：图形不参与判定。
    """
    if not isinstance(options, list):
        return False
    non_empty = [t for t in option_texts(options) if t.strip()]
    return len(non_empty) >= 2


def _stamp_option_figures(
    session: Session,
    options: list[dict] | None,
    *,
    teacher_id: UUID,
    subject: str,
    grade: int,
    knowledge_point: str,
    semester: str,
) -> list[dict] | None:
    """把选项的**图形身份键**盖章成内联几何（ADR-0089 决策 2）。

    落库边界的关键一步：模型只引用身份键，顶点由后端从 ``figure_library``
    （几何唯一权威）取——**模型绝不产出坐标**。产物选项形如
    ``{"text": ..., "figure": {key,label,points,edges} | None}``。

    规则：
    - 本题**没有任何选项引用图形** → 不查目录、不盖章，直接回 ``figure: None``
      （普通文字题的零成本路径）。
    - 有引用则按**本次可用目录**（``allowed_keys_for_question``）校验；**全-or-无**：
      任一键不合法 / 图库无此行 / 部分选项没图 → 整题退化纯文字，不半套出图。
    """
    if not options:
        return options
    keys = [o.get("figure_key") for o in options]
    if not any(keys):
        return [{"text": o["text"], "figure": None} for o in options]
    allowed = allowed_keys_for_question(
        session,
        teacher_id=teacher_id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        semester=semester,
    )
    figures = stamp_figures(session, keys, allowed=allowed)
    if figures is None:
        return [{"text": o["text"], "figure": None} for o in options]
    return [
        {"text": o["text"], "figure": fig.model_dump()}
        for o, fig in zip(options, figures, strict=True)
    ]


# ───────────────────────── 只读用例 ─────────────────────────


def list_teacher_tasks(
    *, session: Session, teacher_id: UUID, status: str | None = None
) -> list[TaskResp]:
    """教师任务列表（含答案，供审阅/核查）。"""
    return [
        task_to_resp(
            t,
            get_task_questions(session=session, task_id=t.id),
            include_answer=True,
        )
        for t in list_tasks_by_teacher(
            session=session, teacher_id=teacher_id, status=status
        )
    ]


def list_teacher_tasks_page(
    *,
    session: Session,
    teacher_id: UUID,
    status: str | None = None,
    cursor: str | None = None,
    page_size: int | None = None,
) -> TaskListResp:
    """教师任务列表（REST，ADR-0053）：摘要分页 + 三个 Tab 的状态计数。

    与 :func:`list_teacher_tasks` 的区别只有投影：那个返回完整 ``TaskResp``（内嵌题目，
    供 AI 查询工具一次取够），这个返回摘要（列表卡片只需要题目数与学科）。
    两者共用同一条 repository 查询，不复制过滤逻辑。
    """
    size = clamp_page_size(page_size)
    tasks = list_tasks_by_teacher(
        session=session,
        teacher_id=teacher_id,
        status=status,
        cursor=cursor,
        page_size=size,
    )
    breakdown = task_question_breakdown(
        session=session, task_ids=[t.id for t in tasks]
    )
    grouped = count_tasks_by_teacher_grouped(session=session, teacher_id=teacher_id)
    # 本页取满才可能有下一页：取不满说明已是最后一批（不能拿 total 判断，它是快照）。
    next_cursor = (
        encode_cursor(created_at=tasks[-1].created_at, id_=tasks[-1].id)
        if tasks and len(tasks) == size
        else None
    )
    return TaskListResp(
        items=[
            TaskSummaryResp(
                id=t.id,
                title=t.title,
                status=t.status,
                student_id=t.student_id,
                created_at=t.created_at,
                question_count=sum(n for _, n in breakdown.get(t.id, [])),
                subjects=[
                    subject
                    for subject, _ in sorted(
                        breakdown.get(t.id, []), key=lambda sc: (-sc[1], sc[0])
                    )
                ],
            )
            for t in tasks
        ],
        total=count_tasks_by_teacher(
            session=session, teacher_id=teacher_id, status=status
        ),
        page_size=size,
        next_cursor=next_cursor,
        counts=TaskCounts(
            draft=grouped.get("draft", 0),
            ready=grouped.get("ready", 0),
            assigned=grouped.get("assigned", 0),
            done=grouped.get("done", 0),
        ),
    )


def teacher_todo_summary(
    *, session: Session, teacher_id: UUID
) -> TeacherTodoSummary:
    """教师工作台待办聚合（ticket 20）：待审核 / 待派发 / 谁没交。

    前两项复用 :func:`count_tasks_by_teacher_grouped` 的分组计数
    （draft=待教师确认；ready=已确认未派发）；第三项统计教师名下任务中
    尚未提交作答的派发对象数（``completed_at`` 为空），按 ``Task.teacher_id`` 收敛。
    """
    grouped = count_tasks_by_teacher_grouped(session=session, teacher_id=teacher_id)
    not_submitted = count_incomplete_assignments_by_teacher(
        session=session, teacher_id=teacher_id
    )
    return TeacherTodoSummary(
        pending_review=grouped.get("draft", 0),
        pending_dispatch=grouped.get("ready", 0),
        not_submitted=not_submitted,
    )


def list_today_tasks(*, session: Session, student_id: UUID) -> list[TaskResp]:
    """学生今日任务（assigned/done；不含答案）。"""
    return [
        task_to_resp(
            t,
            get_task_questions(session=session, task_id=t.id),
            include_answer=False,
        )
        for t in get_student_tasks_today(session=session, student_id=student_id)
    ]


def list_wrong_questions(
    *, session: Session, student_id: UUID, include_answer: bool
) -> list[WrongQuestionResp]:
    """错题本。``include_answer`` 由调用方按角色决定；查询工具恒传 True 后交
    ``project_for_role`` 统一裁剪（ADR-0033 决策 9）。"""
    rows = repo_list_wrong_questions(session=session, student_id=student_id)
    scene_cache: dict = {}
    return [
        wrong_question_to_resp(
            wq, q, session=session, include_answer=include_answer, scene_cache=scene_cache
        )
        for wq, q in rows
    ]


def list_wrong_questions_page(
    *,
    session: Session,
    student_id: UUID,
    include_answer: bool,
    cursor: str | None = None,
    page_size: int | None = None,
    scope: str = "active",
) -> WrongQuestionListResp:
    """错题本（REST，ADR-0053）：游标分页信封。

    ``include_answer`` 由**调用方按角色**决定（教师 True / 学生 False），不进查询参数——
    答案能不能看是鉴权问题，不能让客户端自己选。

    ``scope``（ADR-0053 P2）：``active``（默认）/ ``graduated``（只看已掌握）。
    """
    size = clamp_page_size(page_size)
    rows = repo_list_wrong_questions(
        session=session,
        student_id=student_id,
        cursor=cursor,
        page_size=size,
        scope=scope,
    )
    next_cursor = (
        encode_cursor(created_at=rows[-1][0].first_wrong_at, id_=rows[-1][0].id)
        if rows and len(rows) == size
        else None
    )
    scene_cache: dict = {}
    return WrongQuestionListResp(
        items=[
            wrong_question_to_resp(
                wq, q, session=session, include_answer=include_answer, scene_cache=scene_cache
            )
            for wq, q in rows
        ],
        total=count_wrong_questions(
            session=session, student_id=student_id, scope=scope
        ),
        page_size=size,
        next_cursor=next_cursor,
        # 「已掌握（N）」是全量计数，不能拿已加载的页统计（P0 刚修掉的老问题）。
        graduated_total=(
            count_wrong_questions(
                session=session, student_id=student_id, scope="graduated"
            )
            if scope == "active"
            else 0
        ),
    )


def student_progress(*, session: Session, student_id: UUID) -> ProgressResp:
    """学习进度（纯读取，不做鉴权）。"""
    total, correct, checkin_days, streak = get_progress(
        session=session, student_id=student_id
    )
    return ProgressResp(
        student_id=student_id,
        total=total,
        correct=correct,
        accuracy=round(correct / total, 2) if total else 0.0,
        streak_days=streak,
        checkin_days=checkin_days,
    )


# ───────────────────────── 教师视角复合用例（鉴权 + 读取） ─────────────────────────


def list_owned_student_wrong_questions(
    *, session: Session, teacher: User, student_id: UUID
) -> list[WrongQuestionResp]:
    """教师查某学生错题本（含答案/解析供核查）；先校验归属。"""
    require_owned_student(session=session, owner_id=teacher.id, student_id=student_id)
    return list_wrong_questions(session=session, student_id=student_id, include_answer=True)


def owned_student_wrong_questions_page(
    *,
    session: Session,
    teacher: User,
    student_id: UUID,
    cursor: str | None = None,
    page_size: int | None = None,
    scope: str = "active",
) -> WrongQuestionListResp:
    """教师查某学生错题本（REST 分页版，含答案/解析供核查）；先校验归属。"""
    require_owned_student(session=session, owner_id=teacher.id, student_id=student_id)
    return list_wrong_questions_page(
        session=session,
        student_id=student_id,
        include_answer=True,
        cursor=cursor,
        page_size=page_size,
        scope=scope,
    )


def rejoin_student_wrong_question(
    *, session: Session, teacher: User, student_id: UUID, wrong_id: UUID
) -> WrongQuestionResp:
    """教师把某条「已掌握」的错题重新加入复习（ADR-0053 P2）。

    先校验归属（教师 → 学生），再由 repository 按 student 作用域改数据。
    """
    require_owned_student(session=session, owner_id=teacher.id, student_id=student_id)
    wq = rejoin_wrong_question(
        session=session, student_id=student_id, wrong_id=wrong_id
    )
    question = session.get(Question, wq.question_id)
    if question is None:
        raise AppErrorException(ErrCode.QUESTION_NOT_FOUND, "原题不存在")
    return wrong_question_to_resp(
        wq, question, session=session, include_answer=True
    )


def owned_student_progress(*, session: Session, teacher: User, student_id: UUID) -> ProgressResp:
    """教师查某学生学习进度；先校验归属。"""
    require_owned_student(session=session, owner_id=teacher.id, student_id=student_id)
    return student_progress(session=session, student_id=student_id)


# ───────────────────────── 写路径：内部构件 ─────────────────────────


def _owned_task(*, session: Session, teacher: User, task_id: UUID) -> Task:
    """取任务并断言归属当前教师；不存在/越权统一报「任务不存在」（404）。

    「越权伪装成不存在」是本端点的对外契约，判归属本身委托 ``core.guard``。
    """
    return require_owned(
        session=session,
        owner_id=teacher.id,
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
    teacher_id: UUID,
    title: str,
    student_id: UUID | None,
    question_ids: list[UUID],
) -> TaskResp:
    """选项 A：从题库新建任务（draft）。深拷贝选中题为 TaskQuestion 并回填 question_id。"""
    if not question_ids:
        raise AppErrorException(ErrCode.TASK_EMPTY_SPECS, "请至少选择一道题")
    task = create_task_from_bank(
        session=session,
        teacher_id=teacher_id,
        title=title,
        student_id=student_id,
        question_ids=question_ids,
    )
    return task_to_resp(
        task, get_task_questions(session=session, task_id=task.id), include_answer=True
    )


def create_from_generated(
    *,
    session: Session,
    teacher_id: UUID,
    title: str,
    student_id: UUID | None,
    questions: list[dict],
    specs: list[dict],
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

    # student 归属校验（防越权把题卡挂到他人学生下）。
    if student_id is not None:
        require_owned_student(
            session=session,
            owner_id=teacher_id,
            student_id=student_id,
            code=ErrCode.TASK_CHILD_NOT_OWNED,
            message="该学生不属于你的账号",
        )

    # 已生成题卡 → TaskQuestion 草稿项（不预写 Question，与 batch-generate 一致）。
    draft_questions: list[TaskQuestion] = []
    for q in questions:
        if not isinstance(q, dict):
            continue
        subject = str(q.get("subject", ""))
        grade = int(q.get("grade", 0) or 0)
        kp = str(q.get("knowledge_point", ""))
        semester = str(q.get("semester", "") or "")
        stem = str(q.get("stem", ""))
        # 模型不守 output_schema 时可能把选项揉成一个字符串 / 一个列表元素；
        # 落库前切分成「每项一段」，否则学生端选项挤在一行无法选择。
        options = normalize_options(q.get("options"))  # list[dict] | None
        qtype = str(q.get("qtype", "open"))
        # 多选题标记（ADR-0004 D5）：随题卡透传；非 choice / 无选项题恒 False。
        multi = bool(q.get("multi", False)) and qtype == "choice" and bool(_valid_choice_options(options))
        # 选择题必须带有效选项：模型偶发把 qtype 标成 choice 却不给 options，
        # 照存会让学生端渲染成文本框、无法选择。落库前拦掉，让教师重新生成。
        if qtype == "choice" and not _valid_choice_options(options):
            raise AppErrorException(
                ErrCode.TASK_CHOICE_NO_OPTIONS,
                "选择题缺少有效选项，无法保存，请重新生成任务",
            )
        # 选项图形（ADR-0089）：模型只给身份键；落库前按本次可用目录**校验 + 盖几何章**
        # （全-or-无：任一键不合法 / 部分选项没图 → 整题退化纯文字）。
        options = _stamp_option_figures(
            session,
            options,
            teacher_id=teacher_id,
            subject=subject,
            grade=grade,
            knowledge_point=kp,
            semester=semester,
        )
        # 交互讲解快照（ADR-0061 §M）：优先用前端回传的（出题时已算好的），
        # 没有就地按「知识点模板 + 本题数值」融合一份。写null 也要归一化成
        # None——JSON `null` 存进JSON 列会让「非空」计数失真。
        raw_scene = q.get("scene_spec")
        if isinstance(raw_scene, dict) and raw_scene:
            scene_spec: dict | None = raw_scene
        else:
            built = build_scene_spec_for_question(
                session,
                teacher_id=teacher_id,
                subject=subject,
                grade=grade,
                knowledge_point=kp,
                semester=semester,
            )
            # ADR-0091 ticket 02：生产端产有类型 SceneSpec，JSON 列只收 dict——
            # 落库边界序列化（响应侧 model_dump 归 ticket 03，此处是持久化侧）。
            scene_spec = built.model_dump() if built is not None else None
        draft_questions.append(
            TaskQuestion(
                task_id=None,  # 由 batch_generate_task 回填
                question_id=None,  # R-Q1=c：草稿期不入题库
                subject=subject,
                grade=grade,
                knowledge_point=kp,
                qtype=qtype,
                stem=stem,
                options=options,
                multi=multi,
                answer=q.get("answer"),
                explanation=q.get("explanation") or "",
                difficulty=str(q.get("difficulty") or "medium"),
                semester=semester,
                scene_spec=scene_spec,
            )
        )
    if not draft_questions:
        raise AppErrorException(ErrCode.TASK_EMPTY_SPECS, "生成的题目为空，无法保存")

    task = batch_generate_task(
        session=session,
        teacher_id=teacher_id,
        title=title,
        student_id=student_id,
        specs_dicts=specs,
        task_questions=draft_questions,
        model=model,
    )
    return task_to_resp(
        task, get_task_questions(session=session, task_id=task.id), include_answer=True
    )


def task_detail(*, session: Session, teacher: User, task_id: UUID) -> TaskResp:
    """教师查单个 Task（草稿 / 锁定 / 派发 / 完成 都能看）。"""
    task = _owned_task(session=session, teacher=teacher, task_id=task_id)
    tqs = get_task_questions(session=session, task_id=task.id)
    # 教师端：草稿/锁定/派发后都能看到答案（审阅 + 核查）。
    include_answer = task.status in ("draft", "ready") or task.teacher_id == teacher.id
    return task_to_resp(task, tqs, include_answer=include_answer)


def promote_one(
    *, session: Session, teacher: User, task_id: UUID, tq_id: UUID
) -> QuestionResp:
    """草稿题 → 加入题库（R-Q1=c：写 Question 行并回填 question_id）。幂等。"""
    task = _owned_task(session=session, teacher=teacher, task_id=task_id)
    _require_draft(task)
    _draft_item(session=session, task=task, tq_id=tq_id)
    updated = promote_task_question(session=session, tq_id=tq_id)
    if updated is None:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    return question_to_resp(updated, include_answer=True)


def promote_all(*, session: Session, teacher: User, task_id: UUID) -> TaskResp:
    """一键把当前草稿所有未入库的题批量加入题库。已入库的跳过（幂等）。"""
    task = _owned_task(session=session, teacher=teacher, task_id=task_id)
    _require_draft(task)
    for tq in get_task_questions(session=session, task_id=task.id):
        if tq.question_id is None:
            promote_task_question(session=session, tq_id=tq.id)
    tqs = get_task_questions(session=session, task_id=task.id)
    return task_to_resp(task, tqs, include_answer=True)


def add_from_bank(
    *, session: Session, teacher: User, task_id: UUID, question_ids: list[UUID]
) -> TaskResp:
    """选项 B：把题库题追加到已有草稿任务（仅 draft；同题去重；越权题忽略）。"""
    task = _owned_task(session=session, teacher=teacher, task_id=task_id)
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


def remove_one(*, session: Session, teacher: User, task_id: UUID, tq_id: UUID) -> None:
    """删除草稿项。R-Q5=b：同时物理删关联 Question 行（若 question_id 非空）。"""
    task = _owned_task(session=session, teacher=teacher, task_id=task_id)
    _require_draft(task)
    _draft_item(session=session, task=task, tq_id=tq_id)
    if not remove_task_question(session=session, tq_id=tq_id):
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")


def edit_question(
    *, session: Session, teacher: User, task_id: UUID, tq_id: UUID, edits: dict
) -> QuestionResp:
    """编辑草稿快照题（仅 draft 态，R-Q4：仅题干/选项/答案/解析，知识点/题型等过滤）。"""
    task = _owned_task(session=session, teacher=teacher, task_id=task_id)
    _require_draft(task)
    _draft_item(session=session, task=task, tq_id=tq_id)
    # 严格按 R-Q4：只允许 stem/options/answer/explanation；剔除 knowledge_point 等。
    allowed = {"stem", "options", "answer", "explanation"}
    filtered = {k: v for k, v in edits.items() if k in allowed}
    updated = update_task_question(session=session, tq_id=tq_id, edits=filtered)
    if updated is None:
        raise AppErrorException(ErrCode.TASK_QUESTION_NOT_FOUND, "题目不存在")
    return question_to_resp(updated, include_answer=True)


def edit_task_meta(
    *, session: Session, teacher: User, task_id: UUID, edits: dict
) -> TaskResp:
    """编辑任务元信息（仅 draft 态；当前仅 title，见 TaskMetaEdit）。

    specs / status / student_id 有各自的专属流转（重生成 / confirm / assign），
    本端点刻意不放开——生成产物必须与规格一致，改规格等价于重新生成。
    """
    task = _owned_task(session=session, teacher=teacher, task_id=task_id)
    _require_draft(task)
    allowed = {"title"}
    filtered = {k: v for k, v in edits.items() if k in allowed}
    updated = update_task_meta(session=session, task_id=task_id, edits=filtered)
    if updated is None:
        raise AppErrorException(ErrCode.TASK_NOT_FOUND, "任务不存在")
    return task_to_resp(
        updated,
        get_task_questions(session=session, task_id=updated.id),
        include_answer=True,
    )


def confirm(*, session: Session, teacher: User, task_id: UUID) -> TaskResp:
    """draft → ready：锁定题集成卷。

    R-Q1=c 业务前自动补齐：锁定前把所有未入题库的草稿题批量 promote 入题库
    （教师"锁定成卷"即表示已经认可这些题可入题库，无需额外两次点击）。
    """
    task = _owned_task(session=session, teacher=teacher, task_id=task_id)
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
    *, session: Session, teacher: User, task_id: UUID, student_id: UUID
) -> TaskResp:
    """ready → assigned：派发给学生，绑 student_id。

    兼容路径：单学生派发仍写 ``task.student_id``（下游 legacy 读取），同时落一条
    派发关系行，使「多学生派发」与「单学生派发」走同一套关系事实源（ADR-0069）。
    """
    require_owned_student(
        session=session,
        owner_id=teacher.id,
        student_id=student_id,
        code=ErrCode.TASK_CHILD_NOT_OWNED,
        message="该学生不属于你的账号",
    )
    task = _owned_task(session=session, teacher=teacher, task_id=task_id)
    updated = assign_task(session=session, task_id=task_id, student_id=student_id)
    if updated is None:
        raise AppErrorException(
            ErrCode.TASK_STATUS_READY_REQUIRED, "Task 不在 ready 态，无法派发"
        )
    create_task_assignment(
        session=session, task_id=task.id, student_id=student_id
    )
    return task_to_resp(
        updated, get_task_questions(session=session, task_id=task_id), include_answer=True
    )


def _recompute_task_status(*, session: Session, task: Task) -> Task:
    """按派发关系重算任务整体状态（ADR-0069 状态语义）。

    - 无派发对象 → ready（待派发）；
    - 有派发对象且全部 completed_at 非空 → done；
    - 其余 → assigned。
    调用方负责先改完关系再调用本函数。
    """
    total = count_assignments(session=session, task_id=task.id)
    if total == 0:
        task.status = "ready"
    else:
        completed = count_completed_assignments(session=session, task_id=task.id)
        task.status = "done" if completed >= total else "assigned"
    session.add(task)
    session.commit()
    session.refresh(task)
    return task


def bulk_assign_task(
    *,
    session: Session,
    teacher: User,
    task_id: UUID,
    class_ids: list[UUID] | None = None,
    student_ids: list[UUID] | None = None,
) -> TaskResp:
    """整班 / 多学生批量派发（ADR-0069）。

    把「班级列表 + 学生列表」展开后按学生去重、原子写入派发关系；任务首次派发后置
    ``assigned``。下游作答/打卡/错题按各自 ``student_id`` 归集，不受影响。
    """
    task = _owned_task(session=session, teacher=teacher, task_id=task_id)
    if task.status not in ("ready", "assigned"):
        raise AppErrorException(
            ErrCode.TASK_STATUS_READY_REQUIRED, "任务不在 ready/assigned 态，无法派发"
        )

    target: set[UUID] = set(student_ids or [])
    if class_ids:
        rows = session.exec(
            select(User.id).where(
                User.class_id.in_(class_ids),  # type: ignore[union-attr]
                User.teacher_id == teacher.id,
                User.role == Role.STUDENT,
            )
        ).all()
        target.update(rows)
    if not target:
        raise AppErrorException(
            ErrCode.VALIDATION, "派发对象为空：班级列表与学生列表不能同时为空"
        )

    # 越权防护：派发对象必须都属于当前教师。
    owned = set(
        session.exec(
            select(User.id).where(
                User.id.in_(target), User.teacher_id == teacher.id  # type: ignore[union-attr]
            )
        ).all()
    )
    if len(owned) != len(target):
        raise AppErrorException(
            ErrCode.TASK_CHILD_NOT_OWNED, "部分学生不属于你的账号"
        )

    # 原子写入（去重 + 单事务），返回新增条数。
    bulk_create_assignments(
        session=session, task_id=task.id, student_ids=list(target)
    )
    # 单学生派发保留 legacy 单列（下游 today 列表兼容）；多学生则不写该列。
    if len(target) == 1:
        only = next(iter(target))
        if task.student_id != only:
            task.student_id = only
            session.add(task)
    if task.status == "ready":
        task.status = "assigned"
        session.add(task)
        session.commit()
        session.refresh(task)
    return task_to_resp(
        task, get_task_questions(session=session, task_id=task.id), include_answer=True
    )


def cancel_task_assignments(
    *,
    session: Session,
    teacher: User,
    task_id: UUID,
    student_ids: list[UUID] | None = None,
) -> TaskResp:
    """取消派发（ADR-0069）：``student_ids`` 为空 → 取消全部；否则仅移除指定学生。

    取消后按剩余派发关系重算任务状态（全部清空 → ready；其余按完成度 → assigned/done）。
    """
    task = _owned_task(session=session, teacher=teacher, task_id=task_id)
    if student_ids:
        for sid in student_ids:
            ta = session.exec(
                select(TaskAssignment).where(
                    TaskAssignment.task_id == task_id,
                    TaskAssignment.student_id == sid,
                )
            ).first()
            if ta is not None:
                session.delete(ta)
        session.commit()
    else:
        cancel_assignments(session=session, task_id=task_id)
    return task_to_resp(
        _recompute_task_status(session=session, task=task),
        get_task_questions(session=session, task_id=task.id),
        include_answer=True,
    )


def discard(*, session: Session, teacher: User, task_id: UUID) -> None:
    """作废草稿（draft/ready 可删，assigned/done 不允许）。

    R-Q5=b：级联删所有草稿 TaskQuestion 及其已入题库的 Question 行。
    """
    task = _owned_task(session=session, teacher=teacher, task_id=task_id)
    if task.status in ("assigned", "done"):
        raise AppErrorException(
            ErrCode.FORBIDDEN, "已派发/完成的任务不可作废，请在学生端处理"
        )
    if not discard_draft_task(session=session, task_id=task_id):
        raise AppErrorException(ErrCode.TASK_NOT_FOUND, "作废失败，任务不存在或状态不允许")


def _answerable_task(*, session: Session, user: User, task_id: UUID) -> tuple[Task, UUID]:
    """取可作答/打卡的任务并解析「实际作答的学生 id」。

    学生只能答派给自己的任务：多学生派发下以派发关系判定（不再只看 ``task.student_id``）；
    教师代答沿用 legacy 单列 ``task.student_id``（单学生路径）。返回 ``(task, actor_student_id)``。
    """
    task = session.get(Task, task_id)
    if task is None:
        raise AppErrorException(ErrCode.TASK_NOT_FOUND, "任务不存在")
    if user.role == Role.STUDENT:
        in_relation = is_student_assigned(
            session=session, task_id=task_id, student_id=user.id
        )
        if not in_relation and task.student_id != user.id:
            raise AppErrorException(ErrCode.TASK_NOT_OWNED, "这不是派发给你的任务")
        return task, user.id
    # 教师代答：沿用 legacy 单列判定（多学生派发不在代答范围）。
    if task.student_id is None:
        raise AppErrorException(ErrCode.TASK_NOT_ASSIGNED, "Task 尚未派发给任何学生")
    require_owned_student(
        session=session,
        owner_id=user.id,
        student_id=task.student_id,
        code=ErrCode.TASK_NOT_YOUR_STUDENT,
        message="这不是你家学生的任务",
    )
    return task, task.student_id


def answer(
    *,
    session: Session,
    user: User,
    task_id: UUID,
    question_id: UUID,
    student_answer: str,
) -> AnswerResult:
    """学生答题 / 教师代答。身份 + 状态双校验，作答/错题归集统一挂 task.student_id。"""
    task, actor_student_id = _answerable_task(session=session, user=user, task_id=task_id)
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

    # 批改经归一封装构造 provider：尊重 task.model / 教师 ModelConfig（ADR-0034 Phase 2），
    # 消除「批改忽略 model」的分裂；task.model 为 None 时回退本教师默认模型（模型管理）。
    try:
        result = Grader(
            build_ai_provider(task.model, teacher_id=task.teacher_id, session=session)
        ).grade(question=tq, student_answer=student_answer)
    except ProviderRequestError as exc:
        # 厂商拒绝请求（认证失败/限流/网络）：如实回报，不笼统归成「未配置模型」（ADR-0038）。
        raise AppErrorException(ErrCode.LLM_REQUEST_FAILED, exc.user_hint) from exc
    record_question_id = tq.question_id or question_id
    create_answer_record(
        session=session,
        question_id=record_question_id,
        student_id=actor_student_id,
        student_answer=student_answer,
        correct=result["correct"],
        score=result["score"],
    )
    if not result["correct"]:
        upsert_wrong_question(
            session=session,
            question_id=record_question_id,
            student_id=actor_student_id,
        )
    return AnswerResult(
        correct=result["correct"],
        score=result["score"],
        explanation=tq.explanation or result.get("explanation", ""),
    )


def checkin(*, session: Session, user: User, task_id: UUID) -> CheckinResult:
    """学生打卡 / 教师代打卡。

    打卡完成某学生在本次派发中的份额：标记派发关系的 ``completed_at``，再按整体完成度
    重算任务状态（全部完成 → done，否则保持 assigned，ADR-0069 状态语义）。
    """
    task, actor_student_id = _answerable_task(session=session, user=user, task_id=task_id)
    if task.status not in ("assigned", "done"):
        raise AppErrorException(
            ErrCode.TASK_STATUS_ASSIGNED_REQUIRED, "仅 assigned/done 态可打卡"
        )
    cin = create_checkin(
        session=session,
        student_id=actor_student_id,
        task_id=task.id,
        checkin_date=date.today(),
    )
    mark_assignment_completed(
        session=session, task_id=task.id, student_id=actor_student_id
    )
    _recompute_task_status(session=session, task=task)
    return CheckinResult(ok=True, checkin_date=cin.checkin_date)


async def generate_task_stream(
    *, req: TaskGenerateReq, teacher: User, session: Session,
    runtime: AgentRuntime | None = None,
) -> AsyncIterator[str]:
    """结构化出题流式端点（ADR-0034 Phase 1）的业务层。

    收 specs → 构造 tasks 子代理上下文（question 域已并入，ADR-0098）→ 流式逐题产出
    DATA 题卡（SSE 帧）。纯透传：题卡由前端收齐后走 ``create_from_generated`` 落库
    （两步法第二步），本函数不做任何持久化。``runtime`` 可选注入（默认
    ``get_runtime()`` 单例），便于单测。
    """
    rt = runtime or get_runtime()
    teacher_id = teacher.id
    student_id = req.student_id

    # 出题 provider 经归一封装构造（ADR-0034 Phase 2）：统一由 resolve_engine 解析
    # req.model / 教师 ModelConfig，与批改 / 伴学走同一条模型解析链。
    provider = build_ai_provider(req.model, teacher_id=teacher_id, session=session)
    # RAG（ADR-0055 §13）：vector 模式下传 (session, teacher_id) 启用教师私有资料库检索
    retriever = build_retriever(session=session, teacher_id=teacher_id)
    deps = RuntimeDeps(provider=provider, retriever=retriever, safety=None)

    # 反馈边（ADR-0060 D4）：把看板下发的代表错题解析为题干样例，注入出题 prompt。
    # 仅取本教师且 AI 生成的题（teacher_id + origin="ai"），避免把教师从教辅录入的
    # 题当仿写样例（版权红线，ADR-0020）。解析后在 ctx.extra 透传给 tasks 子代理
    # （出题域随 question 并入，ADR-0098）。
    weak_examples: list[dict] | None = None
    if req.weak_example_ids:
        from sqlmodel import select

        from app.db.models import Question
        from app.db.models.question import QUESTION_ORIGIN_AI

        rows = session.exec(
            select(Question).where(
                Question.id.in_(req.weak_example_ids),  # type: ignore[union-attr]
                Question.teacher_id == teacher_id,
                Question.origin == QUESTION_ORIGIN_AI,
            )
        ).all()
        weak_examples = [
            {
                "knowledge_point": q.knowledge_point,
                "qtype": q.qtype,
                "stem": q.stem,
                "options": option_texts(q.options),
                "answer": q.answer,
                "difficulty": q.difficulty,
            }
            for q in rows
        ]

    subject = req.specs[0].subject
    # 「有 N 份资料未参与本次出题」（ADR-0055 §13）：pending/failed/stale 计数。
    # 纯提示性遥测：session 替身 / 查询失败一律按 0，绝不阻塞出题主链路。
    try:
        from app.features.materials import repository as materials_repo

        unindexed = materials_repo.count_unindexed(session, teacher_id=teacher_id)
    except Exception:  # noqa: BLE001
        unindexed = 0
    ctx = SubAgentContext(
        role="teacher",
        message="",  # 结构化规格走 ctx.extra["specs"]，不依赖自由文本
        history=None,
        model=req.model,
        skills="",
        extra={
            "subject": subject,
            "teacher_id": teacher_id,
            "student_id": student_id,
            "grade": 0,
            "session_id": None,
            "weak_examples": weak_examples,
            "specs": [s.model_dump() for s in req.specs],
            "unindexed_materials": unindexed,
        },
    )

    # 复用与聊天路径同一道带闸入口 invoke_subagent（T03）：business 已知为 "tasks"，
    # 不重走自然语言路由，但仍过同一道安全 / 可见性闸，杜绝此前绕过 decide 的静默漂移。
    async for ev in rt.invoke_subagent(
        "", role="teacher", ctx=ctx, deps=deps, business="tasks", session=session
    ):
        yield ev.to_sse()
