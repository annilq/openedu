"""列表游标分页的不变量测试（ADR-0053）。

接缝：repository / service 函数 + conftest 的临时 SQLite session，不走 HTTP——
分页的正确性在数据访问层，套一层 TestClient 只会让失败更难定位。

这里守的是**选游标而不要 offset 的唯一理由**：两次取页之间插入新数据时，
翻页不重复、不漏行。offset 分页在这个场景下必然错位，这条测试会一直盯着它。
"""
from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from app.core.pagination import (
    DEFAULT_PAGE_SIZE,
    MAX_PAGE_SIZE,
    clamp_page_size,
    encode_cursor,
)
from app.db.models import Question, Task, TaskQuestion, User, WrongQuestion
from app.features.questions.repository import list_bank_questions
from app.features.tasks import service as tasks_service
from app.features.tasks.repository import (
    count_tasks_by_parent,
    count_tasks_by_parent_grouped,
    list_wrong_questions,
    task_question_breakdown,
)
from tests.utils.user import auth_headers, register_parent

_BASE = datetime(2026, 1, 1, tzinfo=UTC)


def _parent(db, client, name: str) -> uuid.UUID:
    """注册家长并返回其 id（题目 / 任务的 owner 隔离需要真实 user 行）。"""
    r = register_parent(client, username=name)
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    me = client.get("/api/v1/auth/me", headers=auth_headers(token))
    return uuid.UUID(me.json()["id"])


def _questions(db, parent_id: uuid.UUID, n: int, *, start: int = 0) -> list[Question]:
    """建 n 道题，created_at 逐个递增 1 分钟（保证排序键互不相同）。"""
    made: list[Question] = []
    for i in range(start, start + n):
        q = Question(
            parent_id=parent_id,
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


def _cursor_of(q: Question) -> str:
    return encode_cursor(created_at=q.created_at, id_=q.id)


# ── 游标不变量 ──


def test_cursor_pages_cover_all_items_once(db, client):
    """游标逐页走完：条目不重、不漏。"""
    parent_id = _parent(db, client, "pg_parent_1")
    made = _questions(db, parent_id, 5)
    expected = {q.id for q in made}

    seen: list[uuid.UUID] = []
    cursor: str | None = None
    for _ in range(10):
        items, _total, _usage = list_bank_questions(
            session=db, parent_id=parent_id, page_size=2, cursor=cursor
        )
        if not items:
            break
        seen.extend(q.id for q in items)
        if len(items) < 2:
            break
        cursor = _cursor_of(items[-1])

    assert set(seen) == expected, "游标翻页漏了条目"
    assert len(seen) == len(set(seen)), "游标翻页出现了重复条目"
    # 倒序：最新的在前
    assert seen[0] == made[-1].id


def test_cursor_unaffected_by_insert_between_pages(db, client):
    """两次取页之间插入新题：不重复也不漏（offset 分页在这里会错位）。"""
    parent_id = _parent(db, client, "pg_parent_2")
    made = _questions(db, parent_id, 5)

    items, _t, _u = list_bank_questions(
        session=db, parent_id=parent_id, page_size=2, cursor=None
    )
    seen = [q.id for q in items]
    cursor = _cursor_of(items[-1])

    # 页间插入一条更新的题：它排在游标之前，不该出现在后续页里
    _questions(db, parent_id, 1, start=99)

    while True:
        items, _t, _u = list_bank_questions(
            session=db, parent_id=parent_id, page_size=2, cursor=cursor
        )
        if not items:
            break
        seen.extend(q.id for q in items)
        if len(items) < 2:
            break
        cursor = _cursor_of(items[-1])

    assert len(seen) == len(set(seen)), "插入新数据后出现了重复条目"
    assert set(seen) == {q.id for q in made}, "插入新数据后漏掉了旧条目"


def test_total_matches_filter(db, client):
    """total 随过滤条件变化（且不再靠把全表读进内存来数）。"""
    parent_id = _parent(db, client, "pg_parent_3")
    _questions(db, parent_id, 4)
    db.add(
        Question(
            parent_id=parent_id,
            subject="语文",
            grade=2,
            knowledge_point="拼音",
            qtype="fill",
            stem="语文题",
            created_at=_BASE + timedelta(minutes=50),
        )
    )
    db.commit()

    assert list_bank_questions(session=db, parent_id=parent_id, page_size=10)[1] == 5
    assert (
        list_bank_questions(
            session=db, parent_id=parent_id, subject="语文", page_size=10
        )[1]
        == 1
    )
    assert (
        list_bank_questions(
            session=db, parent_id=parent_id, keyword="拼音", page_size=10
        )[1]
        == 1
    )


def test_owner_isolation(db, client):
    """分页过滤不能越权：另一个家长看不到这些题。"""
    parent_id = _parent(db, client, "pg_parent_4")
    _questions(db, parent_id, 3)
    stranger = _parent(db, client, "pg_parent_5")

    items, total, _u = list_bank_questions(session=db, parent_id=stranger, page_size=10)
    assert total == 0
    assert items == []


def test_page_size_clamped():
    assert clamp_page_size(None) == DEFAULT_PAGE_SIZE
    assert clamp_page_size(0) == 1
    assert clamp_page_size(9999) == MAX_PAGE_SIZE


# ── 任务列表摘要（载荷不再 O(任务数 × 题数)）──


def test_task_list_summaries_do_not_embed_questions(db, client):
    """列表项不带题目，只带题目数与学科；完整题目由详情端点给。"""
    parent_id = _parent(db, client, "pg_parent_6")
    task = Task(parent_id=parent_id, title="卷子", status="draft")
    db.add(task)
    db.commit()
    db.refresh(task)
    for i in range(3):
        db.add(
            TaskQuestion(
                task_id=task.id,
                subject="数学" if i < 2 else "语文",
                grade=2,
                knowledge_point="加法运算",
                qtype="calc",
                stem=f"t{i}",
            )
        )
    db.commit()

    page = tasks_service.list_parent_tasks_page(
        session=db, parent_id=parent_id, page_size=10
    )
    item = next(i for i in page.items if i.id == task.id)
    assert item.question_count == 3
    assert item.subjects == ["数学", "语文"]  # 按题数降序
    # 摘要模型根本没有 questions 字段——列表响应不可能再内嵌题目。
    assert not hasattr(item, "questions")

    grouped = task_question_breakdown(session=db, task_ids=[task.id])
    assert sum(n for _, n in grouped[task.id]) == 3


def test_task_counts_match_statuses(db, client):
    """三个 Tab 的徽标：一次 group by 的结果与各状态单独计数一致。"""
    parent_id = _parent(db, client, "pg_parent_7")
    for status, n in (("draft", 2), ("assigned", 3), ("done", 1)):
        for i in range(n):
            db.add(Task(parent_id=parent_id, title=f"{status}{i}", status=status))
    db.commit()

    page = tasks_service.list_parent_tasks_page(
        session=db, parent_id=parent_id, page_size=10
    )
    assert (page.counts.draft, page.counts.assigned, page.counts.done) == (2, 3, 1)
    assert page.counts.ready == 0
    assert page.total == 6
    assert count_tasks_by_parent_grouped(session=db, parent_id=parent_id).get("draft") == 2
    assert count_tasks_by_parent(session=db, parent_id=parent_id, status="draft") == 2


# ── 错题分页 ──


def test_wrong_question_page_hides_answer_for_child_role(db, client):
    """娃娃端 page 的 answer 恒为 None（能不能看答案是鉴权问题，不由客户端选）。"""
    parent_id = _parent(db, client, "pg_parent_8")
    child = User(
        username="pg_kid_1",
        hashed_password="x",
        role="child",
        display_name="娃娃",
        grade=2,
        parent_id=parent_id,
    )
    db.add(child)
    db.commit()
    db.refresh(child)
    q = Question(
        parent_id=parent_id,
        subject="数学",
        grade=2,
        knowledge_point="加法运算",
        qtype="calc",
        stem="1+1=",
        answer="2",
        created_at=_BASE,
    )
    db.add(q)
    db.commit()
    db.refresh(q)
    db.add(
        WrongQuestion(
            child_id=child.id,
            question_id=q.id,
            first_wrong_at=_BASE,
            wrong_count=1,
        )
    )
    db.commit()

    page = tasks_service.list_wrong_questions_page(
        session=db, child_id=child.id, include_answer=False, page_size=10
    )
    assert page.total == 1
    assert page.items[0].answer is None
    assert page.next_cursor is None  # 取不满一页 = 到底

    rows = list_wrong_questions(session=db, child_id=child.id, page_size=10)
    assert len(rows) == 1
