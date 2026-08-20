from datetime import date
from uuid import UUID

from fastapi import APIRouter, HTTPException, status

from app.api.deps import CurrentChild, CurrentParent, SessionDep
from app.crud import (
    add_questions,
    create_answer_record,
    create_checkin,
    create_task,
    get_child_tasks_today,
    get_progress,
    get_questions,
    get_task,
    list_wrong_questions,
    upsert_wrong_question,
)
from app.domain import Grader, QuestionGenerator, build_provider
from app.models import (
    AnswerResult,
    AnswerSubmit,
    CheckinResult,
    ProgressResp,
    Question,
    QuestionResp,
    Task,
    TaskCreate,
    TaskResp,
    User,
    WrongQuestion,
    WrongQuestionResp,
)

router = APIRouter(prefix="/tasks", tags=["tasks"])


def _task_to_resp(task: Task, questions: list[Question], *, include_answer: bool) -> TaskResp:
    return TaskResp(
        id=task.id,
        title=task.title,
        subject=task.subject,
        grade=task.grade,
        knowledge_point=task.knowledge_point,
        qtype=task.qtype,
        difficulty=task.difficulty,
        count=task.count,
        status=task.status,
        questions=[
            QuestionResp(
                id=q.id,
                stem=q.stem,
                options=q.options,
                qtype=q.qtype,
                knowledge_point=q.knowledge_point,
                explanation=q.explanation or "",
                answer=q.answer if include_answer else None,
            )
            for q in questions
        ],
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


@router.post("", response_model=TaskResp, status_code=status.HTTP_201_CREATED)
def generate_task(
    *, session: SessionDep, parent: CurrentParent, payload: TaskCreate
) -> TaskResp:
    child = session.get(User, payload.child_id)
    if child is None or child.parent_id != parent.id:
        raise HTTPException(status_code=403, detail="Child not owned by parent")

    generator = QuestionGenerator(build_provider())
    generated = [
        generator.generate(
            subject=payload.subject,
            grade=payload.grade,
            knowledge_point=payload.knowledge_point,
            qtype=payload.qtype,
            difficulty=payload.difficulty,
        )
        for _ in range(payload.count)
    ]

    task = create_task(
        session=session,
        parent_id=parent.id,
        child_id=payload.child_id,
        title=payload.title,
        subject=payload.subject,
        grade=payload.grade,
        knowledge_point=payload.knowledge_point,
        qtype=payload.qtype,
        difficulty=payload.difficulty,
        count=payload.count,
        status="pending",
    )
    db_questions = [
        Question(
            task_id=task.id,
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
        for g in generated
    ]
    add_questions(session=session, questions=db_questions)

    # 家长端：返回题目且含标准答案，便于核查质量
    return _task_to_resp(task, db_questions, include_answer=True)


@router.get("/today", response_model=list[TaskResp])
def today(*, session: SessionDep, child: CurrentChild) -> list[TaskResp]:
    tasks = get_child_tasks_today(session=session, child_id=child.id)
    return [_task_to_resp(t, get_questions(session=session, task_id=t.id), include_answer=False) for t in tasks]


@router.get("/wrong-questions", response_model=list[WrongQuestionResp])
def my_wrong_questions(
    *, session: SessionDep, child: CurrentChild
) -> list[WrongQuestionResp]:
    """娃娃自查错题本：不含答案/解析细节外的泄题字段，防作弊（复习走 /review/*）。"""
    rows = list_wrong_questions(session=session, child_id=child.id)
    return [_wrong_to_resp(wq, q, include_answer=False) for wq, q in rows]


@router.get("/children/{child_id}/wrong-questions", response_model=list[WrongQuestionResp])
def child_wrong_questions(
    *, session: SessionDep, parent: CurrentParent, child_id: UUID
) -> list[WrongQuestionResp]:
    """家长查某娃娃错题本（含答案/解析，供核查）。"""
    child = session.get(User, child_id)
    if child is None or child.parent_id != parent.id:
        raise HTTPException(status_code=403, detail="Not your child")
    rows = list_wrong_questions(session=session, child_id=child_id)
    return [_wrong_to_resp(wq, q, include_answer=True) for wq, q in rows]


@router.post("/{task_id}/answer", response_model=AnswerResult)
def answer_question(
    *, session: SessionDep, child: CurrentChild, task_id: UUID, submit: AnswerSubmit
) -> AnswerResult:
    task = get_task(session=session, task_id=task_id)
    if task is None or task.child_id != child.id:
        raise HTTPException(status_code=403, detail="Not your task")
    question = session.get(Question, submit.question_id)
    if question is None or question.task_id != task.id:
        raise HTTPException(status_code=404, detail="Question not found")

    grader = Grader(build_provider())
    result = grader.grade(question=question, student_answer=submit.student_answer)
    create_answer_record(
        session=session,
        question_id=question.id,
        child_id=child.id,
        student_answer=submit.student_answer,
        correct=result["correct"],
        score=result["score"],
    )
    if not result["correct"]:
        upsert_wrong_question(
            session=session,
            question_id=question.id,
            child_id=child.id,
        )
    return AnswerResult(
        correct=result["correct"],
        score=result["score"],
        explanation=question.explanation or result.get("explanation", ""),
    )


@router.post("/{task_id}/checkin", response_model=CheckinResult)
def checkin(
    *, session: SessionDep, child: CurrentChild, task_id: UUID
) -> CheckinResult:
    task = get_task(session=session, task_id=task_id)
    if task is None or task.child_id != child.id:
        raise HTTPException(status_code=403, detail="Not your task")
    checkin = create_checkin(
        session=session,
        child_id=child.id,
        task_id=task.id,
        checkin_date=date.today(),
    )
    task.status = "done"
    session.add(task)
    session.commit()
    return CheckinResult(ok=True, checkin_date=checkin.checkin_date)


@router.get("/children/{child_id}/progress", response_model=ProgressResp)
def progress(
    *, session: SessionDep, parent: CurrentParent, child_id: UUID
) -> ProgressResp:
    child = session.get(User, child_id)
    if child is None or child.parent_id != parent.id:
        raise HTTPException(status_code=403, detail="Not your child")
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
