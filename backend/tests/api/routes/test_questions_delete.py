"""DELETE /questions 批量硬删题库题 + 全量级联回归测试。

验证：
  1) 正常：未被引用的题被硬删，返回在 deleted；
  2) 被任务引用的题现在也会被删，并级联清掉：
     - 任务里的题目副本（TaskQuestion）一并删除；
     - 该题的作答记录（AnswerRecord）/ 错题（WrongQuestion）一并删除；
     - 若任务因此失去全部题目，则连任务（含 Checkin，并置空引用它的会话）一并删除；
  3) 任务仍有其他题目（含 question_id=None 的再生题）时，任务保留、仅删被删题的副本；
  4) 非本家长所有的题不删，返回在 skipped_forbidden（owner 隔离）。
"""
from __future__ import annotations

import uuid

from sqlmodel import Session as DBSession
from sqlmodel import select

from app.core.db import engine
from app.db.models import (
    AnswerRecord,
    Checkin,
    Conversation,
    Question,
    Task,
    TaskQuestion,
    User,
    WrongQuestion,
)
from tests.utils.user import auth_headers, register_parent


def _parent_id(client, token: str) -> uuid.UUID:
    r = client.get("/api/v1/auth/me", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return uuid.UUID(r.json()["id"])


def _make_question(pid: uuid.UUID, qid: uuid.UUID, subject: str, stem: str) -> Question:
    return Question(
        id=qid, parent_id=pid, subject=subject, grade=2,
        knowledge_point="kp", qtype="calc", stem=stem, answer="2",
        explanation="", difficulty="easy",
    )


def test_delete_questions_cascades_referenced(client):
    r = register_parent(client, username="del_parent_1")
    ptoken = r.json()["access_token"]
    pid = _parent_id(client, ptoken)

    # 一个真实娃娃，供作答 / 错题记录引用。
    child_id = uuid.uuid4()
    with DBSession(engine) as s:
        s.add(User(
            id=child_id, username="del_child_1", display_name="娃",
            hashed_password="x",
        ))
        s.commit()

    q_free = uuid.uuid4()       # 未被任何任务引用 → 正常删
    q_used = uuid.uuid4()       # 仅被 T1 引用，T1 删后变空 → 连带删 T1
    q_other = uuid.uuid4()      # 被 T2 引用，但 T2 还有另一题 → T2 保留
    q_keep = uuid.uuid4()       # T2 里的另一题（再生题，question_id=None）
    with DBSession(engine) as s:
        s.add(_make_question(pid, q_free, "数学", "1+1=?"))
        s.add(_make_question(pid, q_used, "语文", "填空A"))
        s.add(_make_question(pid, q_other, "语文", "填空B"))
        s.add(_make_question(pid, q_keep, "数学", "2+2=?"))
        s.commit()

        t1 = Task(title="仅含q_used", status="draft", parent_id=pid)
        t2 = Task(title="含q_other+再生题", status="draft", parent_id=pid)
        s.add(t1)
        s.add(t2)
        s.commit()
        s.refresh(t1)
        s.refresh(t2)
        t1_id = t1.id
        t2_id = t2.id

        s.add(TaskQuestion(
            task_id=t1.id, question_id=q_used, subject="语文", grade=2,
            knowledge_point="kp", qtype="calc", stem="填空A", answer="x",
            explanation="", difficulty="easy",
        ))
        s.add(TaskQuestion(
            task_id=t2.id, question_id=q_other, subject="语文", grade=2,
            knowledge_point="kp", qtype="calc", stem="填空B", answer="x",
            explanation="", difficulty="easy",
        ))
        # 再生题：question_id=None，不指向任何题库题，删除 q_keep 时不应被波及。
        s.add(TaskQuestion(
            task_id=t2.id, question_id=None, subject="数学", grade=2,
            knowledge_point="kp", qtype="calc", stem="2+2=?", answer="4",
            explanation="", difficulty="easy",
        ))
        s.commit()

        # q_used 的作答 / 错题记录。
        s.add(AnswerRecord(
            question_id=q_used, child_id=child_id, student_answer="1",
            correct=False,
        ))
        s.add(WrongQuestion(child_id=child_id, question_id=q_used))
        # T1 的一条签到记录（应随 T1 删除）。
        s.add(Checkin(child_id=child_id, task_id=t1.id))
        s.commit()

        # 一条引用 T1 的会话（ref_task_id 应被置空而非报错）。
        s.add(Conversation(
            kind="grade", parent_id=pid, child_id=child_id, ref_task_id=t1.id,
        ))
        s.commit()

    r = client.request(
        "DELETE",
        "/api/v1/questions",
        headers=auth_headers(ptoken),
        json={"ids": [str(q_free), str(q_used), str(q_other)]},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert set(body["deleted"]) == {str(q_free), str(q_used), str(q_other)}
    # T1 因变空被连带删除；T2 仍有再生题，保留。
    assert body["deleted_tasks"] == [str(t1_id)]

    with DBSession(engine) as s:
        remaining = s.exec(select(Question).where(Question.parent_id == pid)).all()
        remaining_ids = {str(q.id) for q in remaining}
    assert str(q_free) not in remaining_ids
    assert str(q_used) not in remaining_ids
    assert str(q_other) not in remaining_ids
    assert str(q_keep) in remaining_ids  # 未删，仍在

    # 级联清理校验
    with DBSession(engine) as s:
        tq_used = s.exec(
            select(TaskQuestion).where(TaskQuestion.question_id == q_used)
        ).all()
        tq_other = s.exec(
            select(TaskQuestion).where(TaskQuestion.question_id == q_other)
        ).all()
        # T2 仍应有那条再生题（question_id=None）保留。
        tq_t2_total = s.exec(
            select(TaskQuestion).where(TaskQuestion.task_id == t2_id)
        ).all()
        ar = s.exec(
            select(AnswerRecord).where(AnswerRecord.question_id == q_used)
        ).all()
        wq = s.exec(
            select(WrongQuestion).where(WrongQuestion.question_id == q_used)
        ).all()
        t1_row = s.get(Task, t1_id)
        t2_row = s.get(Task, t2_id)
        checkin = s.exec(select(Checkin).where(Checkin.task_id == t1_id)).all()
        conv = s.exec(
            select(Conversation).where(Conversation.ref_task_id == t1_id)
        ).all()

    assert tq_used == []  # q_used 的副本已删
    assert tq_other == []  # q_other 的副本已删
    assert len(tq_t2_total) == 1  # T2 再生题保留
    assert ar == []  # 作答记录已删
    assert wq == []  # 错题已删
    assert t1_row is None  # T1 变空 → 连带删
    assert t2_row is not None  # T2 保留
    assert checkin == []  # T1 的签到已删
    assert conv == []  # 引用 T1 的会话 ref_task_id 已置空


def test_delete_questions_owner_isolation(client):
    pa = register_parent(client, username="del_parent_a").json()["access_token"]
    pb = register_parent(client, username="del_parent_b").json()["access_token"]
    pida = _parent_id(client, pa)

    q_other_id = uuid.uuid4()
    with DBSession(engine) as s:
        s.add(_make_question(pida, q_other_id, "数学", "1+1=?"))
        s.commit()

    # 家长 B 删除家长 A 的题 → 不删，归为 skipped_forbidden
    r = client.request(
        "DELETE",
        "/api/v1/questions",
        headers=auth_headers(pb),
        json={"ids": [str(q_other_id)]},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert str(q_other_id) in body["skipped_forbidden"]
    assert str(q_other_id) not in body["deleted"]

    with DBSession(engine) as s:
        assert s.get(Question, q_other_id) is not None  # 仍保留
