"""Tasks feature 路由层：只做「鉴权 → 调 service → 翻译响应」。

写路径（草稿生成 / 题卡落库 / 锁定 / 派发 / 作答 / 打卡）与读路径的聚合口径全部
在 ``features/tasks/service.py``：本文件的每个端点都是三行以内的薄壳，不含 ORM
查询、不含领域类型、不含多步编排。此前写路径直连 repository 并识别其私有
sentinel，导致本文件膨胀到 700+ 行且 ORM/领域类型泄漏到 HTTP 层；ADR-0033 的
业务查询工具也因此无法复用写逻辑。

⚠️ 路由顺序：静态路径（/today、/wrong-questions、/children/*）必须放在
带路径参数的路由（/{task_id}、/{task_id}/questions/...）前面，否则
FastAPI 会把 "/today" 当作 task_id="today" 命中 get_task_detail，
走到 CurrentParent 依赖而娃娃 token 报 AUTH_30004（角色错）。
"""
from uuid import UUID

from fastapi import APIRouter, Query, status

from app.core.deps import CurrentChild, CurrentParent, CurrentUser, SessionDep
from app.features.questions.schemas import BankQuestionsAdd, TaskFromBankCreate
from app.features.tasks import service as tasks_service
from app.features.tasks.schemas import (
    AnswerResult,
    AnswerSubmit,
    CheckinResult,
    ProgressResp,
    QuestionResp,
    TaskFromGenerated,
    TaskQuestionEdit,
    TaskResp,
    WrongQuestionResp,
)

router = APIRouter(prefix="/tasks", tags=["tasks"])


# ───────────────────────── 创建（题库 / 流式题卡落库） ─────────────────────────


@router.post("/from-bank", response_model=TaskResp, status_code=status.HTTP_201_CREATED)
def create_from_bank(
    *, session: SessionDep, parent: CurrentParent, payload: TaskFromBankCreate
) -> TaskResp:
    """选项 A：从题库新建任务（draft）。深拷贝选中题为 TaskQuestion 并回填 question_id。"""
    return tasks_service.create_from_bank(
        session=session,
        parent_id=parent.id,
        title=payload.title,
        child_id=payload.child_id,
        question_ids=payload.question_ids,
    )


@router.post("/from-generated", response_model=TaskResp, status_code=status.HTTP_201_CREATED)
def create_from_generated(
    *, session: SessionDep, parent: CurrentParent, payload: TaskFromGenerated
) -> TaskResp:
    """流式题卡落库：把流式端点逐题返回的题卡一次性建为 draft 任务（两步法的第二步）。"""
    return tasks_service.create_from_generated(
        session=session,
        parent_id=parent.id,
        title=payload.title,
        child_id=payload.child_id,
        questions=payload.questions,
        specs=[s.model_dump() for s in payload.specs],
        focus_interest=payload.focus_interest,
        model=payload.model,
    )


@router.get("", response_model=list[TaskResp])
def list_parent_tasks(
    *,
    session: SessionDep,
    parent: CurrentParent,
    status_filter: str | None = Query(None, alias="status"),
) -> list[TaskResp]:
    """家长任务列表（供选项 B 草稿选择器拉取 draft 列表）。"""
    return tasks_service.list_parent_tasks(
        session=session, parent_id=parent.id, status=status_filter
    )


# ───────────────────────── 静态路径：娃娃端今日任务 / 错题 / 家长错题 / 进度 ──


@router.get("/today", response_model=list[TaskResp])
def today(*, session: SessionDep, child: CurrentChild) -> list[TaskResp]:
    return tasks_service.list_today_tasks(session=session, child_id=child.id)


@router.get("/wrong-questions", response_model=list[WrongQuestionResp])
def my_wrong_questions(
    *, session: SessionDep, child: CurrentChild
) -> list[WrongQuestionResp]:
    """娃娃自查错题本：不含答案（复习走 /review/*）。"""
    return tasks_service.list_wrong_questions(
        session=session, child_id=child.id, include_answer=False
    )


@router.get("/children/{child_id}/wrong-questions", response_model=list[WrongQuestionResp])
def child_wrong_questions(
    *, session: SessionDep, parent: CurrentParent, child_id: UUID
) -> list[WrongQuestionResp]:
    """家长查某娃娃错题本（含答案/解析，供核查）。"""
    return tasks_service.list_owned_child_wrong_questions(
        session=session, parent=parent, child_id=child_id
    )


@router.get("/children/{child_id}/progress", response_model=ProgressResp)
def progress(
    *, session: SessionDep, parent: CurrentParent, child_id: UUID
) -> ProgressResp:
    return tasks_service.owned_child_progress(
        session=session, parent=parent, child_id=child_id
    )


# ───────────────────────── 参数路径：单个 Task 详情 / 草稿动作 ──────────────────


@router.get("/{task_id}", response_model=TaskResp)
def get_task_detail(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID
) -> TaskResp:
    """家长查单个 Task（草稿 / 锁定 / 派发 / 完成 都能看）。"""
    return tasks_service.task_detail(session=session, parent=parent, task_id=task_id)


@router.post("/{task_id}/questions/{tq_id}/promote", response_model=QuestionResp)
def promote_one(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID, tq_id: UUID
) -> QuestionResp:
    """草稿题 → 加入题库（R-Q1=c：写 Question 行并回填 question_id）。幂等。"""
    return tasks_service.promote_one(
        session=session, parent=parent, task_id=task_id, tq_id=tq_id
    )


@router.post("/{task_id}/promote-all", response_model=TaskResp)
def promote_all(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID
) -> TaskResp:
    """一键把当前草稿所有未入库的题批量加入题库。已入库的跳过（幂等）。"""
    return tasks_service.promote_all(session=session, parent=parent, task_id=task_id)


@router.post("/{task_id}/questions/from-bank", response_model=TaskResp)
def add_from_bank(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID, payload: BankQuestionsAdd
) -> TaskResp:
    """选项 B：把题库题追加到已有草稿任务（仅 draft；同题去重；越权题忽略）。"""
    return tasks_service.add_from_bank(
        session=session,
        parent=parent,
        task_id=task_id,
        question_ids=payload.question_ids,
    )


@router.delete("/{task_id}/questions/{tq_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_one(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID, tq_id: UUID
) -> None:
    """删除草稿项。R-Q5=b：同时物理删关联 Question 行（若 question_id 非空）。"""
    tasks_service.remove_one(
        session=session, parent=parent, task_id=task_id, tq_id=tq_id
    )


@router.post("/{task_id}/questions/{tq_id}/regenerate", response_model=QuestionResp)
def regenerate_one(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID, tq_id: UUID
) -> QuestionResp:
    """单题重生成：沿用原题的 subject/grade/knowledge_point/qtype/difficulty 拉新。"""
    return tasks_service.regenerate_one(
        session=session, parent=parent, task_id=task_id, tq_id=tq_id
    )


@router.post("/{task_id}/regenerate", response_model=TaskResp)
def regenerate_all(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID
) -> TaskResp:
    """整卷重生成（R-Q2=c）：按 Task.specs 原规格重跑，全量替换草稿项。"""
    return tasks_service.regenerate_all(session=session, parent=parent, task_id=task_id)


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
    return tasks_service.edit_question(
        session=session,
        parent=parent,
        task_id=task_id,
        tq_id=tq_id,
        edits=edits.model_dump(exclude_unset=True),
    )


@router.post("/{task_id}/confirm", response_model=TaskResp)
def confirm(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID
) -> TaskResp:
    """draft → ready：锁定题集成卷（锁定前自动把未入库的草稿题批量 promote）。"""
    return tasks_service.confirm(session=session, parent=parent, task_id=task_id)


@router.post("/{task_id}/assign", response_model=TaskResp)
def assign(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID, child_id: UUID
) -> TaskResp:
    """ready → assigned：派发给娃娃，绑 child_id。"""
    return tasks_service.assign(
        session=session, parent=parent, task_id=task_id, child_id=child_id
    )


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def discard(
    *, session: SessionDep, parent: CurrentParent, task_id: UUID
) -> None:
    """作废草稿（draft/ready 可删，assigned/done 不允许）。"""
    tasks_service.discard(session=session, parent=parent, task_id=task_id)


# ───────────────────────── 答题 / 打卡 ─────────────────────────


@router.post("/{task_id}/answer", response_model=AnswerResult)
def answer_question(
    *, session: SessionDep, user: CurrentUser, task_id: UUID, submit: AnswerSubmit
) -> AnswerResult:
    """娃娃答题 / 家长代答。身份 + 状态双校验，作答/错题归集统一挂 task.child_id。"""
    return tasks_service.answer(
        session=session,
        user=user,
        task_id=task_id,
        question_id=submit.question_id,
        student_answer=submit.student_answer,
    )


@router.post("/{task_id}/checkin", response_model=CheckinResult)
def checkin(
    *, session: SessionDep, user: CurrentUser, task_id: UUID
) -> CheckinResult:
    """娃娃打卡 / 家长代打卡。"""
    return tasks_service.checkin(session=session, user=user, task_id=task_id)
