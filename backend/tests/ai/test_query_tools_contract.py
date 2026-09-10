"""``query`` 工具集契约测试（ADR-0033 决策 9 的机制化兜底）。

守护三条不变量，全部**静态或确定性**，不接真实模型：

1. **工具集形状**：7 个只读工具、名称唯一、schema 合法、每个参数与工具本身都有
   描述（模型靠它选型）、handler 是 ``async (args, *, ctx, session)``。
2. **娃娃端无答案**（ADR-008 硬门槛）：遍历全部工具跑一遍娃娃视角，断言输出中
   **不出现** ``ANSWER_FIELDS``；并有**对照组**证明家长视角确实看得到答案——
   否则「娃娃端没有」可能只是数据本来就空，属假绿。
3. **越权不可达**：娃娃传别人的 ``child_id`` 无效；家长传别家的娃娃抛
   ``ToolArgumentError``（不静默返回空，避免模型把「没这个娃」读成「这个娃没数据」）。
   另断言全部工具**只读**（调用前后关键表行数不变）。
"""
from __future__ import annotations

import asyncio
import inspect
import json
from typing import Any
from uuid import UUID

import pytest
from sqlmodel import Session, func, select

from agent_core.subagent import SubAgentContext
from app.ai.subagents.query.tools._shared import (
    ANSWER_FIELDS,
    ToolArgumentError,
    project_for_role,
    resolve_children,
)
from app.ai.subagents.query.tools.registry import QUERY_TOOLS
from app.core.db import engine
from app.db.models import (
    AnswerRecord,
    Checkin,
    Question,
    Task,
    User,
    WrongQuestion,
)
from tests.utils.user import auth_headers, login, register_parent

EXPECTED_TOOL_NAMES = [
    "list_children",
    "list_parent_tasks",
    "list_today_tasks",
    "list_wrong_questions",
    "list_due_reviews",
    "get_progress",
    "get_mastery",
]

KID_PASSWORD = "kid123456"


# ───────────────────────── 装置 ─────────────────────────


def _spec(name: str):
    for spec in QUERY_TOOLS:
        if spec.name == name:
            return spec
    raise AssertionError(f"未注册的工具：{name}")


def _ctx(role: str, **extra: Any) -> SubAgentContext:
    return SubAgentContext(role=role, extra=extra)


def _run(spec, ctx: SubAgentContext, args: dict[str, Any] | None = None) -> Any:
    """在真实 session 上同步驱动 async handler（工具契约就是「同步直调 DB」）。"""
    with Session(engine) as session:
        return asyncio.run(spec.handler(args or {}, ctx=ctx, session=session))


def _keys(node: Any) -> set[str]:
    """递归收集 payload 中出现的全部 dict 键。"""
    if isinstance(node, dict):
        found = set(node)
        for value in node.values():
            found |= _keys(value)
        return found
    if isinstance(node, list):
        found: set[str] = set()
        for value in node:
            found |= _keys(value)
        return found
    return set()


def _create_child(client, ptoken: str, username: str, display_name: str) -> dict:
    r = client.post(
        "/api/v1/children",
        headers=auth_headers(ptoken),
        json={
            "username": username,
            "password": KID_PASSWORD,
            "display_name": display_name,
            "grade": 2,
            "role": "child",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def _make_task(
    client,
    ptoken: str,
    child_id: str | None,
    *,
    prefix: str = "",
    count: int = 1,
    publish: bool = True,
) -> dict:
    specs = [
        {
            "subject": "数学",
            "grade": 2,
            "knowledge_point": "加法",
            "qtype": "calc",
            "difficulty": "easy",
            "count": count,
        }
    ]
    questions = [
        {
            "subject": "数学",
            "grade": 2,
            "knowledge_point": "加法",
            "qtype": "calc",
            "difficulty": "easy",
            "stem": f"{prefix}加法运算 {i}",
            "options": None,
            "answer": f"ans{i}",
            "explanation": f"{prefix}第 {i} 题解析。",
        }
        for i in range(count)
    ]
    body: dict[str, Any] = {
        "title": f"{prefix}任务",
        "specs": specs,
        "questions": questions,
    }
    if child_id:
        body["child_id"] = child_id
    r = client.post(
        "/api/v1/tasks/from-generated", headers=auth_headers(ptoken), json=body
    )
    assert r.status_code == 201, r.text
    task_id = r.json()["id"]
    if not publish:
        return r.json()
    cf = client.post(f"/api/v1/tasks/{task_id}/confirm", headers=auth_headers(ptoken))
    assert cf.status_code == 200, cf.text
    ag = client.post(
        f"/api/v1/tasks/{task_id}/assign",
        headers=auth_headers(ptoken),
        params={"child_id": child_id},
    )
    assert ag.status_code == 200, ag.text
    return ag.json()


def _answer_wrong(client, ctoken: str, task: dict) -> None:
    r = client.post(
        f"/api/v1/tasks/{task['id']}/answer",
        headers=auth_headers(ctoken),
        json={
            "question_id": task["questions"][0]["question_id"],
            "student_answer": "__wrong__",
        },
    )
    assert r.status_code == 200, r.text
    assert r.json()["correct"] is False


def _setup(client, tag: str) -> dict:
    """一组完整数据：1 家长 + 2 娃娃 + 各自任务 + 小明的错题 + 一条未派发草稿。"""
    r = register_parent(client, username=f"qt_{tag}_parent", display_name="测试爸爸")
    assert r.status_code in (200, 201), r.text
    parent_token = r.json()["access_token"]

    a = _create_child(client, parent_token, f"qt_{tag}_a", "小明")
    b = _create_child(client, parent_token, f"qt_{tag}_b", "小红")

    task_a = _make_task(client, parent_token, a["id"], prefix="A")
    _make_task(client, parent_token, b["id"], prefix="B")
    draft = _make_task(client, parent_token, None, prefix="C", publish=False)

    child_token = login(client, f"qt_{tag}_a", KID_PASSWORD).json()["access_token"]
    _answer_wrong(client, child_token, task_a)

    with Session(engine) as session:
        parent_id = str(session.get(User, UUID(a["id"])).parent_id)
    return {
        "parent_id": parent_id,
        "parent_token": parent_token,
        "a": a,
        "b": b,
        "task_a": task_a,
        "draft": draft,
    }


def _counts() -> dict[str, int]:
    with Session(engine) as session:
        return {
            model.__name__: session.exec(select(func.count()).select_from(model)).one()
            for model in (User, Task, Question, WrongQuestion, AnswerRecord, Checkin)
        }


# ───────────────────────── 1. 工具集形状 ─────────────────────────


def test_tool_set_is_the_seven_readonly_tools():
    assert [s.name for s in QUERY_TOOLS] == EXPECTED_TOOL_NAMES
    assert len({s.name for s in QUERY_TOOLS}) == len(QUERY_TOOLS)


def test_every_tool_documents_itself_and_its_args():
    """模型选型完全依赖描述：工具与每个参数都必须有非空 description。"""
    for spec in QUERY_TOOLS:
        assert spec.description.strip(), f"{spec.name} 缺工具描述"
        assert spec.schema["type"] == "object"
        assert spec.schema.get("required") == []
        for arg, prop in spec.schema["properties"].items():
            assert prop.get("description", "").strip(), f"{spec.name}.{arg} 缺参数描述"
            assert prop.get("type"), f"{spec.name}.{arg} 缺类型"


def test_handlers_match_runtime_signature():
    """handler 必须是 ``async (args, *, ctx, session=...)``——runtime 按此调用。"""
    for spec in QUERY_TOOLS:
        assert inspect.iscoroutinefunction(spec.handler), spec.name
        params = inspect.signature(spec.handler).parameters
        assert list(params)[0] == "args", spec.name
        assert params["ctx"].kind is inspect.Parameter.KEYWORD_ONLY, spec.name
        assert params["session"].kind is inspect.Parameter.KEYWORD_ONLY, spec.name


# ───────────────────────── 2. 娃娃端无答案（ADR-008） ─────────────────────────


def test_all_tools_return_clean_payload_for_child(client):
    """核心契约：全部工具在孩子视角下都不得出现任何答案类字段。"""
    setup = _setup(client, "child_clean")
    ctx = _ctx("child", child_id=setup["a"]["id"], parent_id=setup["parent_id"])

    for spec in QUERY_TOOLS:
        leaked = _keys(_run(spec, ctx)) & ANSWER_FIELDS
        assert not leaked, f"{spec.name} 在娃娃视角泄漏字段：{sorted(leaked)}"


def test_parent_payload_does_contain_answers_control_group(client):
    """对照组：家长视角**确实**能看到答案——证明上一条的「没有」不是数据为空导致的假绿。"""
    setup = _setup(client, "parent_answer")
    ctx = _ctx("parent", parent_id=setup["parent_id"], child_id=setup["a"]["id"])

    wrong_payload = _run(_spec("list_wrong_questions"), ctx)
    assert wrong_payload["total_items"] == 1
    assert "answer" in _keys(wrong_payload)
    assert "ans0" in json.dumps(wrong_payload, ensure_ascii=False)

    tasks_payload = _run(_spec("list_parent_tasks"), ctx)
    assert "answer" in _keys(tasks_payload)


def test_project_for_role_strips_nested_answer_fields():
    """投影是递归的：嵌套在列表/字典深处的答案字段同样被剥掉。"""
    payload = {
        "children": [
            {
                "id": "x",
                "items": [{"stem": "题", "answer": "42", "explanation": "因为", "options": ["a"]}],
            }
        ]
    }
    projected = project_for_role(payload, "child")
    assert _keys(projected) & ANSWER_FIELDS == set()
    assert projected["children"][0]["items"][0]["stem"] == "题"
    assert projected["children"][0]["items"][0]["options"] == ["a"]
    # 家长视角原样（不被「顺手」裁剪）
    assert _keys(project_for_role(payload, "parent")) & ANSWER_FIELDS == ANSWER_FIELDS


# ───────────────────────── 3. 定位与越权 ─────────────────────────


def test_child_resolution_ignores_requested_child_id(client):
    """娃娃传别人的 child_id 无效：解析恒为自己，输出不得含兄弟任务。"""
    setup = _setup(client, "sibling")
    ctx = _ctx("child", child_id=setup["a"]["id"], parent_id=setup["parent_id"])

    payload = _run(_spec("list_today_tasks"), ctx, {"child_id": setup["b"]["id"]})
    assert [b["name"] for b in payload["children"]] == ["小明"]
    assert "B加法运算" not in json.dumps(payload, ensure_ascii=False)


def test_child_scoped_queries_only_see_own_data(client):
    """娃娃端每个工具都只应看到自己的数据。"""
    setup = _setup(client, "scope")
    ctx = _ctx("child", child_id=setup["a"]["id"], parent_id=setup["parent_id"])

    for spec in QUERY_TOOLS:
        blob = json.dumps(_run(spec, ctx), ensure_ascii=False)
        assert "小红" not in blob, f"{spec.name} 泄漏了兄弟娃娃"
        assert "B加法运算" not in blob, f"{spec.name} 泄漏了兄弟任务"


def test_parent_cannot_reach_other_parent_child(client):
    """别家的娃娃 → 抛 ToolArgumentError（明确失败，而非空列表）。"""
    setup = _setup(client, "cross")
    other = register_parent(client, username="qt_cross_other")
    other_token = other.json()["access_token"]
    outsider = _create_child(client, other_token, "qt_cross_outsider", "别人家的娃")

    ctx = _ctx("parent", parent_id=setup["parent_id"])
    for spec in QUERY_TOOLS:
        if spec.name == "list_children":
            continue  # 无入参，不需要越权路径
        with pytest.raises(ToolArgumentError):
            _run(spec, ctx, {"child_id": outsider["id"]})


def test_parent_child_name_resolution_and_miss(client):
    """child_name 模糊匹配命中；未命中抛错而不是静默空。"""
    setup = _setup(client, "byname")
    ctx = _ctx("parent", parent_id=setup["parent_id"])

    hit = _run(_spec("list_today_tasks"), ctx, {"child_name": "小"})
    assert sorted(b["name"] for b in hit["children"]) == ["小明", "小红"]

    exact = _run(_spec("list_today_tasks"), ctx, {"child_name": "小红"})
    assert [b["name"] for b in exact["children"]] == ["小红"]

    with pytest.raises(ToolArgumentError):
        _run(_spec("list_today_tasks"), ctx, {"child_name": "不存在"})


def test_resolve_children_defaults_to_all_for_parent_and_self_for_child(client):
    setup = _setup(client, "defaults")

    with Session(engine) as session:
        parent_scope = resolve_children(
            session=session, ctx=_ctx("parent", parent_id=setup["parent_id"])
        )
        child_scope = resolve_children(
            session=session,
            ctx=_ctx("child", child_id=setup["a"]["id"], parent_id=setup["parent_id"]),
        )

    assert sorted(u.display_name for u in parent_scope) == ["小明", "小红"]
    assert [u.display_name for u in child_scope] == ["小明"]


def test_parent_tasks_tool_scopes_to_today_for_child(client):
    """家长任务工具在娃娃端等价「今日任务」，绝不返回家长视角的全量任务表。"""
    setup = _setup(client, "kid_tasks")
    ctx = _ctx("child", child_id=setup["a"]["id"], parent_id=setup["parent_id"])

    payload = _run(_spec("list_parent_tasks"), ctx)
    assert [b["name"] for b in payload["children"]] == ["小明"]
    assert payload["unassigned_items"] == []
    blob = json.dumps(payload, ensure_ascii=False)
    assert "C任务" not in blob  # 未派发草稿对孩子不可见
    assert "B加法运算" not in blob


def test_unassigned_drafts_only_surface_without_explicit_target(client):
    """未派发草稿：不指定娃娃时进 ``unassigned_items``；精确指定时被剔除。"""
    setup = _setup(client, "unassigned")
    ctx = _ctx("parent", parent_id=setup["parent_id"])

    broad = _run(_spec("list_parent_tasks"), ctx)
    assert [i["title"] for i in broad["unassigned_items"]] == [setup["draft"]["title"]]
    assert broad["total_items"] >= 3

    narrow = _run(_spec("list_parent_tasks"), ctx, {"child_id": setup["a"]["id"]})
    assert narrow["unassigned_items"] == []
    assert "C任务" not in json.dumps(narrow, ensure_ascii=False)


# ───────────────────────── 4. 信封与只读 ─────────────────────────


def test_envelope_shape_is_uniform_across_tools(client):
    """全部工具同构：``children`` / ``unassigned_items`` / ``total_*`` 齐备。"""
    setup = _setup(client, "envelope")
    ctx = _ctx("parent", parent_id=setup["parent_id"])

    for spec in QUERY_TOOLS:
        payload = _run(spec, ctx)
        assert set(payload) == {
            "children",
            "unassigned_items",
            "total_children",
            "total_items",
        }, spec.name
        for block in payload["children"]:
            assert set(block) >= {"id", "name", "grade", "items", "meta"}
            assert isinstance(block["items"], list)


def test_tools_do_not_write_to_the_database(client):
    """全部工具只读：跑一轮后关键表行数不变。"""
    setup = _setup(client, "readonly")
    before = _counts()

    for role_ctx in (
        _ctx("parent", parent_id=setup["parent_id"]),
        _ctx("child", child_id=setup["a"]["id"], parent_id=setup["parent_id"]),
    ):
        for spec in QUERY_TOOLS:
            _run(spec, role_ctx)

    assert _counts() == before


def test_mastery_and_progress_tools_report_real_numbers(client):
    """抽查两个聚合工具的出参语义（掌握度看板 / 进度概况）。"""
    setup = _setup(client, "agg")
    ctx = _ctx("parent", parent_id=setup["parent_id"], child_id=setup["a"]["id"])

    progress = _run(_spec("get_progress"), ctx)
    block = progress["children"][0]
    assert block["name"] == "小明"
    assert block["items"][0]["total"] == 1
    assert block["items"][0]["correct"] == 0
    assert block["items"][0]["accuracy"] == 0.0

    mastery = _run(_spec("get_mastery"), ctx)
    block = mastery["children"][0]
    assert block["meta"]["total_knowledge_points"] == 1
    assert block["items"][0]["knowledge_point"] == "加法"
    assert block["items"][0]["active_wrong"] == 1
