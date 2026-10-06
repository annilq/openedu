"""归档 / 毕业的不变量测试（ADR-0053 P2）。

接缝：service 函数 + conftest 的临时 SQLite session，不走 HTTP——归档的正确性在
数据访问层（过滤条件 + 归属），套一层 TestClient 只会让失败更难定位。

三个模块的归档是**三件不同的事**，本文件按模块分组，每组盯各自的语义：
- 题库：教师显式归档，可恢复，被任务引用也能归档（这是它存在的理由）；
- 错题：毕业（末位阶段答对）打时间戳而非删除，痕迹留着、可重新加入复习。
"""
from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from app.db.models import Question, Task, TaskQuestion, User, WrongQuestion
from app.domain.review_scheduler import REVIEW_INTERVALS_DAYS, apply_review_outcome
from app.features.questions.repository import (
    list_bank_questions,
    set_bank_questions_archived,
)
from app.features.tasks import service as tasks_service
from app.features.tasks.repository import list_wrong_questions, rejoin_wrong_question
from tests.utils.user import auth_headers, register_teacher

_BASE = datetime(2026, 1, 1, tzinfo=UTC)


def _teacher(client, name: str) -> uuid.UUID:
    r = register_teacher(client, username=name)
    assert r.status_code == 200, r.text
    me = client.get(
        "/api/v1/auth/me", headers=auth_headers(r.json()["access_token"])
    )
    return uuid.UUID(me.json()["id"])


def _student(db, teacher_id: uuid.UUID, name: str) -> uuid.UUID:
    student = User(
        username=name,
        hashed_password="x",  # 本文件不经登录，不校验密码
        role="student",
        teacher_id=teacher_id,
        display_name=name,
    )
    db.add(student)
    db.commit()
    db.refresh(student)
    return student.id


def _questions(db, teacher_id: uuid.UUID, n: int) -> list[Question]:
    made = []
    for i in range(n):
        q = Question(
            teacher_id=teacher_id,
            subject="数学",
            grade=2,
            knowledge_point="加法运算",
            qtype="calc",
            stem=f"题 {i}",
            created_at=_BASE + timedelta(minutes=i),
        )
        db.add(q)
        made.append(q)
    db.commit()
    for q in made:
        db.refresh(q)
    return made


# ───────────────────────── 题库：显式归档 ─────────────────────────


def test_bank_hides_archived_by_default(db, client):
    """默认只出在用：归档的意义就是「不用再看到」。"""
    teacher_id = _teacher(client, "ar1_teacher")
    questions = _questions(db, teacher_id, 3)
    set_bank_questions_archived(
        session=db, teacher_id=teacher_id, question_ids=[questions[0].id], archived=True
    )

    items, total, _ = list_bank_questions(session=db, teacher_id=teacher_id)

    assert [q.id for q in items] == [questions[2].id, questions[1].id]
    assert total == 2


def test_bank_archived_scope_and_restore(db, client):
    """三态切换的两端：只看已归档 / 全部；且归档可恢复（不敢删的心理靠这个化解）。"""
    teacher_id = _teacher(client, "ar2_teacher")
    questions = _questions(db, teacher_id, 2)

    set_bank_questions_archived(
        session=db, teacher_id=teacher_id, question_ids=[questions[0].id], archived=True
    )

    only_archived, _, _ = list_bank_questions(
        session=db, teacher_id=teacher_id, archived="archived"
    )
    assert [q.id for q in only_archived] == [questions[0].id]

    both, _, _ = list_bank_questions(
        session=db, teacher_id=teacher_id, archived="all"
    )
    assert len(both) == 2

    # 恢复：archived_at 清空，回到默认列表里
    result = set_bank_questions_archived(
        session=db, teacher_id=teacher_id, question_ids=[questions[0].id], archived=False
    )
    assert result["updated"] == [questions[0].id]
    items, total, _ = list_bank_questions(session=db, teacher_id=teacher_id)
    assert total == 2


def test_bank_archives_question_referenced_by_task(db, client):
    """被任务引用的题也能归档——删除做不到这点，这正是归档存在的理由。"""
    teacher_id = _teacher(client, "ar3_teacher")
    student_id = _student(db, teacher_id, "ar3_kid")
    questions = _questions(db, teacher_id, 1)
    task = Task(
        teacher_id=teacher_id, student_id=student_id, title="卷", status="assigned"
    )
    db.add(task)
    db.commit()
    db.refresh(task)
    db.add(
        TaskQuestion(
            task_id=task.id,
            question_id=questions[0].id,
            subject="数学",
            grade=2,
            knowledge_point="加法运算",
            qtype="calc",
            stem="题 0",
        )
    )
    db.commit()

    result = set_bank_questions_archived(
        session=db, teacher_id=teacher_id, question_ids=[questions[0].id], archived=True
    )

    assert result["updated"] == [questions[0].id]
    assert result["skipped_forbidden"] == []
    # 题还在（只是默认不显示），历史任务不会被破坏
    assert db.get(Question, questions[0].id) is not None


def test_bank_archive_is_owner_scoped(db, client):
    """owner 隔离：别人的题归档不动，归为 skipped_forbidden。"""
    mine = _teacher(client, "ar4_teacher")
    other = _teacher(client, "ar4_other")
    mine_q = _questions(db, mine, 1)[0]
    other_q = _questions(db, other, 1)[0]

    result = set_bank_questions_archived(
        session=db,
        teacher_id=mine,
        question_ids=[mine_q.id, other_q.id],
        archived=True,
    )

    assert result["updated"] == [mine_q.id]
    assert result["skipped_forbidden"] == [other_q.id]
    assert db.get(Question, other_q.id).archived_at is None


# ───────────────────────── 错题：毕业而非删除 ─────────────────────────


def _wrong(db, student_id: uuid.UUID, teacher_id: uuid.UUID, i: int = 0) -> WrongQuestion:
    q = Question(
        teacher_id=teacher_id,
        subject="数学",
        grade=2,
        knowledge_point="加法运算",
        qtype="calc",
        stem=f"错 {i}",
        answer=str(i),
    )
    db.add(q)
    db.commit()
    db.refresh(q)
    wq = WrongQuestion(
        student_id=student_id,
        question_id=q.id,
        wrong_count=1,
        review_stage=0,
        first_wrong_at=_BASE + timedelta(minutes=i),
        due_at=_BASE,
    )
    db.add(wq)
    db.commit()
    db.refresh(wq)
    return wq


def test_graduation_stamps_instead_of_deleting(db, client):
    """末位阶段答对：写 graduated_at，不删行（「这题错过 5 次、现在掌握了」要留着）。"""
    teacher_id = _teacher(client, "gr1_teacher")
    student_id = _student(db, teacher_id, "gr1_kid")
    wq = _wrong(db, student_id, teacher_id)
    wq.review_stage = len(REVIEW_INTERVALS_DAYS) - 1
    db.add(wq)
    db.commit()

    out = apply_review_outcome(session=db, wq=wq, correct=True)

    assert out is not None
    assert out.graduated_at is not None
    assert db.get(WrongQuestion, wq.id) is not None


def test_graduated_hidden_by_default_and_visible_by_scope(db, client):
    """默认只出未毕业；scope=graduated 出「已掌握」分区。"""
    teacher_id = _teacher(client, "gr2_teacher")
    student_id = _student(db, teacher_id, "gr2_kid")
    active = _wrong(db, student_id, teacher_id, 1)
    graduated = _wrong(db, student_id, teacher_id, 2)
    graduated.graduated_at = _BASE
    db.add(graduated)
    db.commit()

    rows = list_wrong_questions(session=db, student_id=student_id)
    assert [wq.id for wq, _ in rows] == [active.id]

    done = list_wrong_questions(session=db, student_id=student_id, scope="graduated")
    assert [wq.id for wq, _ in done] == [graduated.id]


def test_graduated_total_reported_to_teacher(db, client):
    """教师端「已掌握（N）」是全量计数，不能拿已加载的页统计。"""
    teacher_id = _teacher(client, "gr3_teacher")
    student_id = _student(db, teacher_id, "gr3_kid")
    _wrong(db, student_id, teacher_id, 1)
    g1 = _wrong(db, student_id, teacher_id, 2)
    g2 = _wrong(db, student_id, teacher_id, 3)
    for wq in (g1, g2):
        wq.graduated_at = _BASE
        db.add(wq)
    db.commit()

    page = tasks_service.list_wrong_questions_page(
        session=db, student_id=student_id, include_answer=True
    )

    assert page.total == 1
    assert page.graduated_total == 2


def test_rejoin_clears_graduation_but_keeps_history(db, client):
    """重新加入复习：清毕业时间戳、阶段归 0，但 wrong_count / 首次答错时间不清零。"""
    teacher_id = _teacher(client, "gr4_teacher")
    student_id = _student(db, teacher_id, "gr4_kid")
    wq = _wrong(db, student_id, teacher_id)
    wq.graduated_at = _BASE
    wq.review_stage = len(REVIEW_INTERVALS_DAYS) - 1
    wq.wrong_count = 5
    db.add(wq)
    db.commit()

    rejoined = rejoin_wrong_question(
        session=db, student_id=student_id, wrong_id=wq.id
    )

    assert rejoined.graduated_at is None
    assert rejoined.review_stage == 0
    assert rejoined.due_at is not None
    # 痕迹保留：重新来过不该把「错过 5 次」或首次答错时间抹掉
    # （SQLite 存的是 naive UTC，比的是时刻不是 tzinfo）。
    assert rejoined.wrong_count == 5
    assert rejoined.first_wrong_at == _BASE.replace(tzinfo=None)
