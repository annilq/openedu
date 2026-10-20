"""Laya-multilingual 决策模型适配器（T08，ticket 08）。

硬约束守护 + 冒烟（无权重时跳过真实推断）：
- 仅 ``convaiinnovations/laya-multilingual`` 可用，英文 ``laya`` 显式拒绝；
- 无服务地址 / 缺权重时 ``available()`` 为 False（路由回落 LLM 分类或兜底助手）；
- 注入引擎时 ``decide`` 路径正确（key 映射 / 阈值门控 / 不可映射回落）。
"""
from __future__ import annotations

import asyncio

import pytest

from agent_core.adapters.laya import LayaDecisionModel, get_decision_model
from agent_core.ports import DecisionOption, DecisionResult


# ── 硬约束：仅 multilingual ──
def test_rejects_english_laya():
    with pytest.raises(ValueError):
        LayaDecisionModel(repo="convaiinnovations/laya")


def test_rejects_arbitrary_repo():
    with pytest.raises(ValueError):
        LayaDecisionModel(repo="some/other-model")


def test_multilingual_constructs():
    # 不抛即代表守护通过
    assert LayaDecisionModel() is not None


# ── 无服务地址时不可用（生产未部署 laya-serve 即回落下一路由原语） ──
def test_available_false_without_service(monkeypatch):
    monkeypatch.delenv("LAYA_SERVE_URL", raising=False)
    model = LayaDecisionModel()
    assert model.available() is False
    # 不可用 → decide 直接返回 None（路由回落 LLM 分类 / 兜底助手）
    assert asyncio.run(
        model.decide(state="x", options=[DecisionOption(key="tasks", label="t")])
    ) is None


def test_get_decision_model_is_multilingual_singleton():
    m = get_decision_model()
    assert isinstance(m, LayaDecisionModel)
    assert get_decision_model() is m  # 单例


# ── 注入引擎冒烟（不依赖真实权重） ──
class _FakeEngine:
    def __init__(self, answers):
        self.answers = answers

    def predict(self, state, questions):  # noqa: ANN001 — 测试桩
        return self.answers


def _options():
    return [
        DecisionOption(key="tasks", label="任务学情与出题助手"),
        DecisionOption(key="tutor", label="伴学答疑"),
        DecisionOption(key="capability", label="能力自述"),
    ]


def test_decide_maps_choice_key():
    model = LayaDecisionModel(engine=_FakeEngine([{"choice": "tasks", "prob": 0.9}]))
    assert model.available() is True
    res = asyncio.run(model.decide(state="s", options=_options()))
    assert isinstance(res, DecisionResult)
    assert res.choice == "tasks"
    assert res.prob == 0.9


def test_decide_below_threshold_returns_none():
    model = LayaDecisionModel(
        threshold=0.95, engine=_FakeEngine([{"choice": "tasks", "prob": 0.9}])
    )
    assert asyncio.run(model.decide(state="s", options=_options())) is None


def test_decide_unmappable_choice_returns_none():
    model = LayaDecisionModel(engine=_FakeEngine([{"choice": "???", "prob": 0.9}]))
    assert asyncio.run(model.decide(state="s", options=_options())) is None


def test_decide_index_choice_maps_to_key():
    model = LayaDecisionModel(engine=_FakeEngine([{"choice": 1, "prob": 0.9}]))
    res = asyncio.run(model.decide(state="s", options=_options()))
    assert res is not None and res.choice == "tutor"


def test_decide_engine_failure_returns_none():
    class _Boom:
        def predict(self, state, questions):  # noqa: ANN001, D401 — 测试桩
            raise RuntimeError("boom")

    model = LayaDecisionModel(engine=_Boom())
    assert asyncio.run(model.decide(state="s", options=_options())) is None
