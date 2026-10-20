"""Ollaya 决策模型适配器契约（T08 引入；2026-10-20 从 laya-serve 迁移到本地 ollaya）。

守住五条（全部确定性、不依赖真实权重；真实推断由 eval 脚本在 pytest 之外跑）：

- **多语言守护**：英文权重（``laya:en`` / ``laya:typed-decisions`` / ``von`` / ``nli`` /
  ``gliclass``）在中文上「自信但错误」，构造即 ``ValueError``；白名单只收实测过的多语言标签。
- **降级透明**：未配置 ``OLLAYA_URL`` → ``available()`` False；服务端非 2xx（含 state
  超长的 ``422 STATE_TRUNCATED``）→ ``predict`` 返回 ``None`` → ``decide`` 返回 ``None``，
  路由回落 LLM 分类 / 能力引导。
- **请求形状**符合 TypeSafe 契约：``model`` 字段 + ``questions`` 是**字典** + ``criteria``
  以**业务键**为 key（旧实现的 ``questions`` 是列表、无 ``model``，在 ollaya 上直连 422）。
- **门控概率**取 ``probabilities`` 的 top 值，而非 TypeSafe 的 ``confidence``——后者按
  ``(K·pmax − 1)/(K − 1)`` 归一化，同一个置信水平在教师端(K=3)与学生端(K=2)是不同的数字，
  固定阈值跨可见集不可比。
- **异常不击穿**：选项不可映射、answers 缺本题 id、引擎抛错一律返回 ``None``。
"""
from __future__ import annotations

import asyncio
import io
import json
import urllib.error
import urllib.request

import pytest

from agent_core.adapters.laya import (
    LayaDecisionModel,
    _OllayaEngine,
    get_decision_model,
)
from agent_core.ports import DecisionOption, DecisionResult

# 默认权重名（白名单内的多语言权重；断言里不再散落字符串字面量）
DEFAULT_MODEL = "laya:multilingual"


# ── 硬约束：仅多语言权重 ──
@pytest.mark.parametrize(
    "english_model",
    ["laya:en", "laya:typed-decisions", "von", "nli", "gliclass", "some/other-model"],
)
def test_rejects_non_multilingual_models(english_model):
    with pytest.raises(ValueError):
        LayaDecisionModel(model=english_model)


def test_multilingual_constructs():
    # 不抛即代表守护通过（白名单内的多语言权重：现任 + 已评测过的候选）
    assert LayaDecisionModel() is not None
    assert LayaDecisionModel(model="largha") is not None


# ── 服务未配置 → 不可用（生产未部署 ollaya 时回落下一路由原语） ──
def test_available_false_without_service(monkeypatch):
    monkeypatch.delenv("OLLAYA_URL", raising=False)
    model = LayaDecisionModel()
    assert model.available() is False
    # 不可用 → decide 直接返回 None（路由回落 LLM 分类 / 无命中引导）
    assert asyncio.run(
        model.decide(state="x", options=[DecisionOption(key="tasks", label="t")])
    ) is None


def test_available_true_when_service_configured(monkeypatch):
    monkeypatch.setenv("OLLAYA_URL", "http://127.0.0.1:11435")
    assert LayaDecisionModel().available() is True


def test_get_decision_model_is_multilingual_singleton():
    m = get_decision_model()
    assert isinstance(m, LayaDecisionModel)
    assert get_decision_model() is m  # 单例


# ── ollaya 响应体 ──
def _response(
    choice: str,
    probabilities: dict[str, float] | None = None,
    confidence: float | None = None,
) -> dict:
    """构造 TypeSafe 兼容响应（``answers`` 是以问题 id 为键的字典）。"""
    answer: dict = {"type": "choice", "choice": choice}
    if probabilities is not None:
        answer["probabilities"] = probabilities
    if confidence is not None:
        answer["confidence"] = confidence
    return {
        "model": "laya:multilingual",
        "answers": {"business": answer},
        "usage": {"input_tokens": 10, "output_tokens": 0},
    }


class _FakeEngine:
    """按 ``_OllayaEngine.predict`` 的形状回 canned 响应。"""

    def __init__(self, raw: dict | None):
        self.raw = raw
        self.calls: list[tuple[str, str, dict]] = []

    def predict(self, model, state, questions):  # noqa: ANN001 — 测试桩
        self.calls.append((model, state, questions))
        return self.raw


def _options():
    return [
        DecisionOption(key="tasks", label="任务学情与出题助手"),
        DecisionOption(key="tutor", label="伴学答疑"),
        DecisionOption(key="capability", label="能力自述"),
    ]


# ── 请求形状 ──
def test_decide_builds_criteria_keyed_by_business():
    engine = _FakeEngine(
        _response("tasks", {"tasks": 0.8, "tutor": 0.15, "capability": 0.05})
    )
    model = LayaDecisionModel(engine=engine)
    res = asyncio.run(model.decide(state="帮我出 2 道数学题", options=_options()))
    sent_model, sent_state, questions = engine.calls[0]
    assert sent_model == DEFAULT_MODEL
    assert sent_state == "帮我出 2 道数学题"
    assert isinstance(questions, dict) and "business" in questions
    question = questions["business"]
    assert question["type"] == "choice"
    assert question["instructions"]  # 缺 instructions 时模型会读问题 id，必须有值
    assert question["criteria"] == {o.key: o.label for o in _options()}
    assert isinstance(res, DecisionResult) and res.choice == "tasks" and res.prob == 0.8


# ── 门控概率：用 probabilities 的 top 值，不用 confidence ──
def test_decide_thresholds_on_top_probability_not_confidence():
    """同一份响应里 ``confidence`` 被设成 0.99（高于阈值 0.7），而 ``probabilities``
    的 top 值只有 0.6：正确行为是盯后者 → 不达阈值 → 返回 ``None``。

    ``confidence`` 是 ``(K·pmax − 1)/(K − 1)`` 归一化后的值，同一个 pmax 在教师端
    （K=3）与学生端（K=2）是两个不同的数字；使用它做固定阈值，跨可见集不可比。
    """
    engine = _FakeEngine(
        _response("tasks", {"tasks": 0.6, "tutor": 0.3, "capability": 0.1}, confidence=0.99)
    )
    model = LayaDecisionModel(threshold=0.7, engine=engine)
    assert asyncio.run(model.decide(state="s", options=_options())) is None


def test_decide_falls_back_to_confidence_without_probabilities():
    engine = _FakeEngine(_response("tutor", confidence=0.9))
    res = asyncio.run(LayaDecisionModel(engine=engine).decide(state="s", options=_options()))
    assert res is not None and res.choice == "tutor" and res.prob == 0.9


def test_decide_below_threshold_returns_none():
    engine = _FakeEngine(
        _response("tasks", {"tasks": 0.9, "tutor": 0.06, "capability": 0.04})
    )
    model = LayaDecisionModel(threshold=0.95, engine=engine)
    assert asyncio.run(model.decide(state="s", options=_options())) is None


# ── 解析失败一律回落 ──
def test_decide_unmappable_choice_returns_none():
    engine = _FakeEngine(_response("???", confidence=0.9))
    assert asyncio.run(LayaDecisionModel(engine=engine).decide(state="s", options=_options())) is None


def test_decide_index_choice_maps_to_key():
    engine = _FakeEngine(_response(1, confidence=0.9))
    res = asyncio.run(LayaDecisionModel(engine=engine).decide(state="s", options=_options()))
    assert res is not None and res.choice == "tutor"


def test_decide_missing_answer_returns_none():
    """answers 里没有本题 id（如服务端换字段名）→ 视为无决策。"""
    engine = _FakeEngine({"model": "laya:multilingual", "answers": {"other": {"choice": "tasks"}}})
    assert asyncio.run(LayaDecisionModel(engine=engine).decide(state="s", options=_options())) is None


def test_decide_engine_returns_none_returns_none():
    assert asyncio.run(LayaDecisionModel(engine=_FakeEngine(None)).decide(state="s", options=_options())) is None


def test_decide_engine_failure_returns_none():
    class _Boom:
        def predict(self, model, state, questions):  # noqa: ANN001, D401 — 测试桩
            raise RuntimeError("boom")

    model = LayaDecisionModel(engine=_Boom())
    assert asyncio.run(model.decide(state="s", options=_options())) is None


# ── HTTP 路径：形状与非 2xx（含 state 超长 422）──
class _FakeResp:
    def __init__(self, body: bytes):
        self._body = body

    def read(self):  # noqa: D401 — 测试桩
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


def _patch_urlopen(monkeypatch, opens: list, body: dict):
    def _open(req, timeout=None):  # noqa: ANN001 — 测试桩
        opens.append((req, timeout))
        return _FakeResp(json.dumps(body).encode("utf-8"))

    monkeypatch.setattr(urllib.request, "urlopen", _open)


def test_predict_posts_typesafe_payload(monkeypatch):
    opens: list = []
    _patch_urlopen(monkeypatch, opens, _response("tasks", {"tasks": 0.8}))
    engine = _OllayaEngine(base_url="http://127.0.0.1:11435", timeout=1.5)
    assert engine.predict(DEFAULT_MODEL, "s", {"business": {"type": "choice"}}) is not None
    req, timeout = opens[0]
    assert req.full_url == "http://127.0.0.1:11435/v1/systemone"
    assert req.get_header("Authorization") == "Bearer local"
    assert timeout == 1.5
    payload = json.loads((req.data or b"").decode("utf-8"))
    assert payload["model"] == DEFAULT_MODEL
    assert payload["state"] == "s"
    assert payload["questions"]["business"]["type"] == "choice"


def test_predict_returns_none_on_state_truncated(monkeypatch):
    """state 超长时 ollaya 回 ``422 STATE_TRUNCATED``（实测 12 轮中文历史在 512 上下文

    模型上必触发）→ 决策不可用 → 路由回落，而不是拿半截 state 硬答。
    """
    body = b'{"error":"state: part of state was dropped to fit the context","code":"STATE_TRUNCATED"}'

    def _raise(req, timeout=None):  # noqa: ANN001 — 测试桩
        raise urllib.error.HTTPError(
            "http://127.0.0.1:11435/v1/systemone",
            422,
            "Unprocessable Entity",
            {},
            io.BytesIO(body),
        )

    monkeypatch.setattr(urllib.request, "urlopen", _raise)
    engine = _OllayaEngine(base_url="http://127.0.0.1:11435")
    assert engine.predict(DEFAULT_MODEL, "x" * 4000, {"business": {"type": "choice"}}) is None


def test_predict_returns_none_when_unconfigured(monkeypatch):
    monkeypatch.delenv("OLLAYA_URL", raising=False)
    engine = _OllayaEngine()
    assert engine.configured is False
    assert engine.predict(DEFAULT_MODEL, "s", {}) is None
