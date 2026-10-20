"""路由能力清单（criteria）文案契约测试（ADR-0106 / ticket 12，零 LLM、零网络）。

决策模型与 LLM 分类读的都是 ``router._capability_text`` 的投影，那段文案的可分性
**实测决定路由质量**（ticket 12：34 条中文用例从 59% → 74%，「采纳且正确」15 → 24）。
本文件守的是「文案不许悄悄劣化」——不是逐字文案（那会让每次措辞迭代都碎），而是几条
从实测里总结出来的**不变量**：

- **双通道分离**：``routing_criteria`` 只影响路由，用户可见能力清单（``capability_catalog``
  直读 ``description``）不受影响——为路由改文案不得顺手删掉用户该知道的能力；
- **长度上限**：单条 criteria 不超过 120 字符，保住决策模型 1024 上下文里的长历史余量；
- **拒绝排他式否定**：实测「不查数据 / 不出题 / 不解答学科问题」这类排他句让准确率
  从 74% 掉到 35%、高置信错误涨到 6 条（变体 D / C4）。注意 capability 的
  「能做什么、**不能**做什么」是对称措辞，不在禁止之列；
- **各自有专属动词**：三条 criteria 必须各含自己的动作词，防止回潮到「一条泛泛句
  通吃所有问句」的状态；
- **不出示例问句**：实测堆「例子：…」会让准确率掉到 50%（变体 C）。
"""
from __future__ import annotations

import pytest

from agent_core.registry import SubAgentManifest, discover_subagent_manifests
from agent_core.router import _capability_text
from app.ai.subagents.capability import capability_catalog

# 长度上限：决策模型 laya:multilingual 上下文 1024 tok，长历史（12 轮）已占 ~719 字符
MAX_CRITERIA_CHARS = 120

# 排他式否定（实测有害）。capability 的「不能做什么」是对称措辞，不在其中。
BANNED_EXCLUSIONS = ("不查", "不出", "不解答", "不生成", "不调用", "不会")

# 各业务的专属动词（criteria 必须各含其一，保证三者互相可分）
DISTINCTIVE_VERBS = {
    "tasks": ("出题", "查数据"),
    "tutor": ("讲题",),
    "capability": ("能做什么",),
}


@pytest.fixture(scope="module")
def manifests():
    return discover_subagent_manifests()


# ───────────── 1. 双通道分离（ADR-0106 的核心不变量） ─────────────
def test_capability_text_prefers_routing_criteria_over_description(manifests):
    m = SubAgentManifest(
        business="x", name="X", description="给用户看的完整描述",
        routing_criteria="给模型看的短句", actions=["act"],
    )
    assert _capability_text(m) == "X\n给模型看的短句\nactions: act"


def test_capability_text_falls_back_to_description(manifests):
    """未声明 ``routing_criteria`` 时行为与声明前完全一致（存量/新业务不受影响）。"""
    m = SubAgentManifest(business="x", name="X", description="只有一份描述")
    assert _capability_text(m) == "X\n只有一份描述"


def test_user_facing_catalog_ignores_routing_criteria(manifests):
    """为路由改文案不得改变用户可见清单：清单直读 ``description``。

    ticket 12 实测：把「管理题库 / 组建草稿任务」留在路由文案里会让准确率从 74% 掉到
    56%，正确解法是把它只留在 ``description`` 里——这条测试就是那个决定的守门人，
    防止后来者「顺手统一两份文本」把用户的能力说明删掉。
    """
    for role in ("teacher", "student"):
        for line in capability_catalog(role):
            business_name, _, shown = line.partition("：")
            m = next(x for x in manifests.values() if x.name == business_name)
            assert shown == m.description, (
                f"{business_name} 的用户可见描述被路由文案污染了：{shown!r}"
            )


def test_descriptions_still_describe_full_capability(manifests):
    """用户可见描述仍覆盖题库管理等写能力（路由文案已将其剥离）。"""
    assert "题库" in manifests["tasks"].description
    assert "题库" not in _capability_text(manifests["tasks"])


# ───────────── 2. 文案不变量（防劣化，不断言逐字文案） ─────────────
@pytest.mark.parametrize("business", ["tasks", "tutor", "capability"])
def test_criteria_within_length_budget(manifests, business):
    text = _capability_text(manifests[business])
    assert len(text) <= MAX_CRITERIA_CHARS, f"{business} criteria 过长（{len(text)} 字符）：{text!r}"


@pytest.mark.parametrize("business", ["tasks", "tutor", "capability"])
def test_criteria_has_no_exclusive_negation(manifests, business):
    """排他式否定句实测有害（35% 且高置信错误 6 条），禁止回潮。"""
    text = _capability_text(manifests[business])
    for banned in BANNED_EXCLUSIONS:
        assert banned not in text, f"{business} criteria 出现排他否定 {banned!r}：{text!r}"


@pytest.mark.parametrize("business", ["tasks", "tutor", "capability"])
def test_criteria_carries_its_own_verb(manifests, business):
    """每条 criteria 必须含自己的专属动词，保证三者互相可分。"""
    text = _capability_text(manifests[business])
    assert any(v in text for v in DISTINCTIVE_VERBS[business]), (
        f"{business} criteria 缺少专属动词 {DISTINCTIVE_VERBS[business]}：{text!r}"
    )


@pytest.mark.parametrize("business", ["tasks", "tutor", "capability"])
def test_criteria_has_no_example_questions(manifests, business):
    """堆示例问句实测有害（50%），禁止回潮。"""
    assert "例子" not in _capability_text(manifests[business])


def test_criteria_pairwise_distinct(manifests):
    """三条 criteria 两两不同——同义文案会让模型无法分辨（ticket 12 的失败形态）。"""
    texts = {b: _capability_text(manifests[b]) for b in ("tasks", "tutor", "capability")}
    assert len(set(texts.values())) == 3
