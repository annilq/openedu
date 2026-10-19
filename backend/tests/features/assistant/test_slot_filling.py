"""slot_filling 纯函数引擎单测（ADR-0095）。

只测外部行为：给定入参与已累积槽位，预检返回澄清还是放行、missing_slots 内容、
跨轮合并、默认填充、enum_ref 解析、多业务 schema 独立、空消息不抛不伪澄清。
不触 DB、不调模型。
"""
from __future__ import annotations

import importlib

from app.domain.subjects import SUBJECTS
from app.features.assistant.slot_filling import (
    fill_slots,
    resolve_enum_ref,
)
from app.features.assistant.slot_summary import summarize_slots, summary_payload


def _question_schema() -> list[dict]:
    # ADR-0098：question 域并入 tasks，出题（generate 意图）的槽位 schema 迁到
    # intent_schemas.generate——「_question_schema」这个名字留给出题意图的调用方。
    mod = importlib.import_module("app.ai.subagents.tasks.manifest")
    return mod.MANIFEST["intent_schemas"]["generate"]["schema"]


def _tasks_schema() -> list[dict]:
    mod = importlib.import_module("app.ai.subagents.tasks.manifest")
    return mod.MANIFEST["input_schema"]


def test_missing_required_slot_clarifies_with_correct_missing_slots():
    """缺 subject/grade/qtype → clarifying=True，missing 含 name/prompt/type/enum/min/max。"""
    result = fill_slots(_question_schema(), {}, incoming="出几道题", ctx_extra={})
    assert result["clarifying"] is True
    names = {m["name"] for m in result["missing"]}
    assert names == {"subject", "grade", "qtype"}
    subject_miss = next(m for m in result["missing"] if m["name"] == "subject")
    assert subject_miss["prompt"]
    assert subject_miss["type"] == "enum"
    assert subject_miss["enum"] == list(SUBJECTS)
    assert subject_miss["min"] is None and subject_miss["max"] is None
    grade_miss = next(m for m in result["missing"] if m["name"] == "grade")
    assert grade_miss["type"] == "int"
    assert grade_miss["min"] == 1 and grade_miss["max"] == 9
    assert grade_miss["enum"] is None


def test_all_required_present_is_complete_with_optional_defaults():
    """必填齐备 → clarifying=False，optional 默认值回填（count=1 / difficulty=medium）。"""
    collected = {"subject": "数学", "grade": 3, "qtype": "choice"}
    result = fill_slots(_question_schema(), collected, incoming="", ctx_extra={})
    assert result["clarifying"] is False
    merged = result["merged"]
    assert merged["subject"] == "数学"
    assert merged["grade"] == 3
    assert merged["qtype"] == "choice"
    # optional 默认回填
    assert merged["count"] == 1
    assert merged["difficulty"] == "medium"
    assert merged["multi"] is False


def test_merge_override_semantics():
    """本轮抽取覆盖已持久化：collected=数学，incoming=语文 → 合并后语文。"""
    collected = {"subject": "数学", "grade": 3, "qtype": "choice"}
    result = fill_slots(_question_schema(), collected, incoming="来几道语文题", ctx_extra={})
    assert result["extracted"]["subject"] == "语文"
    assert result["merged"]["subject"] == "语文"
    # 未在本轮出现的槽沿用 collected
    assert result["merged"]["grade"] == 3


def test_enum_ref_resolves_to_subjects():
    """subject 槽的 enum_ref 解析为 SUBJECTS（非字符串残留）。"""
    schema = _question_schema()
    subject_slot = next(s for s in schema if s["name"] == "subject")
    assert subject_slot["enum_ref"] == "app.domain.subjects.SUBJECTS"
    from app.features.assistant.slot_filling import _effective_enum

    assert _effective_enum(subject_slot) == list(SUBJECTS)


def test_resolve_enum_ref_handles_bad_ref():
    resolve_enum_ref.cache_clear() if hasattr(resolve_enum_ref, "cache_clear") else None
    assert resolve_enum_ref("app.domain.subjects.NOPE") == []
    assert resolve_enum_ref("not_a_ref") == []


def test_question_and_tasks_schemas_load_independently():
    """多意图载入各自 schema 互不串：generate 意图缺槽阻塞，默认意图全 optional 不阻塞。"""
    q_result = fill_slots(_question_schema(), {}, incoming="查一下", ctx_extra={})
    assert q_result["clarifying"] is True  # subject/grade/qtype 缺失
    tasks_result = fill_slots(_tasks_schema(), {}, incoming="查一下", ctx_extra={})
    assert tasks_result["clarifying"] is False  # 全部 optional


def test_context_passthrough_fills_slots():
    """source=both 的槽可从 ctx.extra 透传：课件 subject=数学 / grade=4 兜底。"""
    ctx_extra = {"subject": "数学", "grade": 4}
    result = fill_slots(_question_schema(), {}, incoming="出选择题", ctx_extra=ctx_extra)
    # subject/grade 来自上下文，qtype 来自文本「选择题」
    assert result["merged"]["subject"] == "数学"
    assert result["merged"]["grade"] == 4
    assert result["merged"]["qtype"] == "choice"
    assert result["clarifying"] is False


def test_empty_message_no_exception_and_no_fake_clarification():
    """空消息不抛；必填已满足时不产生伪澄清（clarifying=False）。"""
    # 必填已满足 + 空消息 → 放行，不伪澄清
    result = fill_slots(
        _question_schema(),
        {"subject": "数学", "grade": 3, "qtype": "choice"},
        incoming="",
        ctx_extra={},
    )
    assert result["clarifying"] is False
    # 必填全缺 + 空消息 → 合法缺失（clarifying=True），但不抛异常
    empty = fill_slots(_question_schema(), {}, incoming="", ctx_extra={})
    assert empty["clarifying"] is True


def test_int_range_rejects_out_of_range_grade():
    """grade 超出 1-9 不抽取（0 年级被范围拒绝，不被误装进槽位）。"""
    result = fill_slots(_question_schema(), {}, incoming="出0年级的题", ctx_extra={})
    assert "grade" not in result["extracted"]


def test_summarize_slots_covers_defaults():
    """汇总文案覆盖被默认填充项；缺知识点显示（未指定）。

    英文码必须翻译：念给用户「题型=choice / 难度=medium」等于没给修正机会
    （US5），故断言的是中文。
    """
    merged = {"subject": "数学", "grade": 3, "qtype": "choice", "count": 1, "difficulty": "medium"}
    text = summarize_slots(merged)
    assert "科目=数学" in text
    assert "年级=3" in text
    assert "题型=选择题" in text
    assert "数量=1" in text
    assert "难度=中等" in text
    assert "知识点=（未指定）" in text


def test_summary_payload_resolves_enum_ref_and_labels():
    """汇总载荷：enum_ref 解析为具体选项（前端才渲染得出修改项），值带中文文案。"""
    merged = {"subject": "数学", "grade": 3, "qtype": "choice"}
    slots = summary_payload(_question_schema(), merged)
    subject = next(s for s in slots if s["name"] == "subject")
    assert subject["enum"], "enum_ref 必须解析成具体可选项"
    assert "语文" in subject["enum"]
    assert subject["label"] == "科目"
    assert subject["value"] == "数学"
    qtype = next(s for s in slots if s["name"] == "qtype")
    assert qtype["value_label"] == "选择题"


def test_subject_alias_outside_enum_is_rejected():
    """别名必须收敛到本槽枚举：「道法→政治」「科学→科学」都不在 SUBJECTS 内。

    回归：不过滤会把非枚举值写进 Conversation.slots，下游按三学科处理即炸。
    """
    for text in ("出道法题", "出科学题"):
        result = fill_slots(_question_schema(), {}, incoming=text, ctx_extra={})
        assert result["merged"].get("subject") in (None, ""), f"{text} 不应命中学科"


def test_grade_and_count_are_not_conflated():
    """grade 与 count 必须按槽名分派：「2 道三年级…」→ count=2、grade=3。

    回归：二者同为 int，若共用「N年级」正则顺序尝试，count 会被年级 3 污染
    （实测「帮我出 2 道三年级数学选择题」多出一道题）。
    """
    result = fill_slots(
        _question_schema(), {}, incoming="帮我出 2 道三年级数学选择题", ctx_extra={}
    )
    assert result["clarifying"] is False
    assert result["merged"]["count"] == 2, "数量必须取「2 道」"
    assert result["merged"]["grade"] == 3, "年级必须取「三年级」"
    assert result["merged"]["subject"] == "数学"
    assert result["merged"]["qtype"] == "choice"


def test_count_defaults_to_one_when_absent():
    """未提数量 → count 回落默认 1（不因年级误填数量）。"""
    result = fill_slots(
        _question_schema(), {}, incoming="出一道三年级数学选择题", ctx_extra={}
    )
    assert result["merged"]["grade"] == 3
    assert result["merged"]["count"] == 1
