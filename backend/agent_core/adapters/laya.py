"""Ollaya 决策模型适配器（agent_core 第一方适配器，与 genkit 平级）。

服务端是本地 ``ollaya serve``（默认 ``http://127.0.0.1:11435``），走 TypeSafe 兼容的
``POST /v1/systemone``——与本机 Ollama(11434) 是两个独立进程，互不干扰。配置
``OLLAYA_URL`` 即启用；未配置 / 请求出错 / 状态超长（``422 STATE_TRUNCATED``）
一律返回 ``None``，路由回落 LLM 分类，再不中落能力引导（ADR-0105），链路不崩。

硬前提：**模型必须多语言**。中文产品用英文决策模型会「自信但错误」（laya 官方数据：
``laya:en`` 在高棉语上准确率 0.000 却仍给出高置信），故 ``_ALLOWED_MODELS`` 白名单
只收实测过的多语言权重；新增标签前先用
``.scratch/ai-intent-routing/eval/decision_model_eval.py`` 跑一遍中文评测。

2026-10-20 本地影子评测（13 条中文用例 + 一条 12 轮长历史，脚本见 eval/）：

- ``laya:multilingual``：8/13 = 62%，p50 23 ms，长历史不截断，平均置信 0.617；
- ``largha``：5/13 = 38%，平均置信 0.270（阈值 0.5 下几乎恒不决策），且 512 上下文
  在 12 轮中文历史上直接 ``422 STATE_TRUNCATED``——**暂不采用**。

两者共同的失败面是 tasks ↔ tutor 的边界，换权重不足以解决这一层分辨问题
（见 scratch ticket 11 的后续项）。
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any

from agent_core.ports import DecisionModel, DecisionOption, DecisionResult

# 决策服务地址：本地 ollaya（环境变量；未配置即降级到 LLM 分类）
_OLLAYA_URL_ENV = "OLLAYA_URL"
# 可选的服务端模型标签覆盖（缺省即用白名单里的默认权重）
_OLLAYA_MODEL_ENV = "OLLAYA_MODEL"

# 路由问题的 id。TypeSafe 约定：问题缺 ``instructions`` 时模型会读 id 代替，
# 故这里用一个描叙性名字（本适配器始终传 instructions，id 只作响应索引）。
_QUESTION_ID = "business"

# 问句与 ADR-0104 保持一致：模型按上下文 + 能力清单挑一个业务。
_ROUTING_INSTRUCTIONS = "给定以上对话，应由哪个助手继续处理用户的最新消息？"

# 允许的模型标签：均为**多语言**权重。 ``laya:en`` / ``laya:typed-decisions`` /
# ``von`` / ``nli`` / ``gliclass`` 是英文权重，一律拒绝。
_ALLOWED_MODELS = frozenset({"laya:multilingual", "largha"})
_DEFAULT_MODEL = "laya:multilingual"


def _assert_multilingual(model: str) -> None:
    """配置守护：拒绝英文权重，避免「在中文上自信但错误」。"""
    if model not in _ALLOWED_MODELS:
        raise ValueError(
            f"决策模型仅允许 {sorted(_ALLOWED_MODELS)}；拒绝 {model!r}——"
            f"英文权重在中文上自信但错误（laya:en 在高棉语 0.000 准确率仍高置信）。"
            f"新增标签前请先跑 "
            f".scratch/ai-intent-routing/eval/decision_model_eval.py 验中文。"
        )


class _OllayaEngine:
    """本地 ``ollaya`` 服务的 TypeSafe 兼容客户端（``POST /v1/systemone``）。

    「尽力可用」实现：未配置地址 / 非 2xx（含 ``422 STATE_TRUNCATED``，即 state
    装不进模型上下文）/ 网络失败 / 非 JSON 响应，一律返回 ``None``，由调用方回落。
    """

    def __init__(self, base_url: str | None = None, *, timeout: float = 3.0) -> None:
        self._base_url = base_url or os.getenv(_OLLAYA_URL_ENV)
        # 冷启动要把权重加载进 GPU / CPU，实测 laya:multilingual 首请求约 1.1 s，
        # 之后稳定在 10–30 ms；3 s 足够本地服务，超时后下一次请求命中已加载的权重。
        self._timeout = timeout

    @property
    def configured(self) -> bool:
        """是否配置了服务地址（廉价同步判断，不发起网络握手）。"""
        return bool(self._base_url)

    def predict(
        self, model: str, state: str, questions: dict[str, Any]
    ) -> dict[str, Any] | None:
        """返回反序列化后的响应体；任何失败返回 ``None``。"""
        if not self._base_url:
            return None
        payload = json.dumps(
            {"model": model, "state": state, "questions": questions}
        ).encode("utf-8")
        req = urllib.request.Request(
            f"{self._base_url.rstrip('/')}/v1/systemone",
            data=payload,
            headers={"Content-Type": "application/json", "Authorization": "Bearer local"},
        )
        try:
            with urllib.request.urlopen(req, timeout=self._timeout) as resp:  # noqa: S310 — 本机受控地址
                data = json.loads(resp.read().decode("utf-8"))
        except (urllib.error.HTTPError, OSError, ValueError):
            # 422 STATE_TRUNCATED（state 超长）/ 连不上 / 超时 / 非 JSON：
            # 决策模型不可用是设计好的降级路径，不是异常。
            return None
        return data if isinstance(data, dict) else None


class LayaDecisionModel(DecisionModel):
    """决策模型端口的 Ollaya 实现（默认权重 laya:multilingual）。

    - 路由决策：把可见 business 的能力清单作为 ``choice`` 问题的 ``criteria``
      （键 = 业务键，值 = ``_capability_text(manifest)``），state = 近期对话上下文，
      问「哪个业务处理本 state」，取概率最高者。
    - 低于 ``threshold`` 或无法决策 → ``decide`` 返回 ``None``，路由回落 LLM 分类，
      再不中落能力引导（ADR-0105）。
    - ``engine`` 可注入（测试 / 私有部署）；缺省懒连本地 ollaya。
    """

    def __init__(
        self,
        *,
        model: str = _DEFAULT_MODEL,
        threshold: float = 0.5,
        engine: Any | None = None,
    ) -> None:
        _assert_multilingual(model)
        self._model = model
        self._threshold = float(threshold)
        self._engine = engine if engine is not None else _OllayaEngine()

    def available(self) -> bool:
        """引擎就绪才视为可用：注入引擎恒真；本地 ollaya 需已配置 ``OLLAYA_URL``。

        不做网络握手（廉价同步检查）；握手失败由 ``predict`` 返回 ``None`` 兜底。
        """
        if self._engine is None:
            return False
        if isinstance(self._engine, _OllayaEngine):
            return self._engine.configured
        return True

    async def decide(
        self, *, state: str, options: list[DecisionOption]
    ) -> DecisionResult | None:
        if self._engine is None:
            return None
        if not options:
            return None

        questions = {
            _QUESTION_ID: {
                "type": "choice",
                "instructions": _ROUTING_INSTRUCTIONS,
                "criteria": {opt.key: opt.label for opt in options},
            }
        }
        try:
            raw = self._engine.predict(self._model, state, questions)
        except Exception:  # noqa: BLE001 — 模型异常不应击穿路由，回落 LLM 分类 / 能力引导
            return None

        answers = (raw or {}).get("answers") or {}
        answer = answers.get(_QUESTION_ID) if isinstance(answers, dict) else None
        if not isinstance(answer, dict):
            return None

        key = self._resolve_key(answer.get("choice"), options)
        prob = self._top_probability(answer, options)
        if key is None or prob < self._threshold:
            # 无法解析选项 / 低于置信阈值 → 视为无决策，回落 LLM 分类 / 能力引导
            return None
        return DecisionResult(choice=key, prob=prob, raw=answer)

    @staticmethod
    def _top_probability(answer: dict[str, Any], options: list[DecisionOption]) -> float:
        """取所选项的校准概率做门控：**不用** TypeSafe 的 ``confidence``。

        ``confidence`` 是归一化后的 top 概率（K 个选项时为 ``(K·pmax − 1)/(K − 1)``），
        同一个 pmax 在教师端（3 个选项）与学生端（2 个选项）会映射成不同数字，固定
        阈值在不同可见集上不可比。 ``probabilities`` 里的值是模型给出的校准分布，跨
        K 可比，故以其作为 ``threshold`` 的比较对象；``confidence`` 留在 ``raw`` 里
        供观测。

        ``probabilities`` 缺省时退回 ``confidence``，仍缺省则 0.0（必然不达阈值）。
        """
        probabilities = answer.get("probabilities")
        keys = {opt.key for opt in options}
        if isinstance(probabilities, dict):
            values = [
                float(v)
                for k, v in probabilities.items()
                if k in keys and isinstance(v, (int, float))
            ]
            if values:
                return max(values)
        confidence = answer.get("confidence")
        return float(confidence) if isinstance(confidence, (int, float)) else 0.0

    @staticmethod
    def _resolve_key(choice: Any, options: list[DecisionOption]) -> str | None:
        """把模型回传的 choice（可能是 key / label / 索引）映射回业务 key。"""
        if choice is None:
            return None
        # 1) 直接是某个选项的 key（criteria 以业务键为 key，正常路径）
        for opt in options:
            if choice == opt.key:
                return opt.key
        # 2) 是某个选项的 label（精确 / 包含）
        for opt in options:
            if choice == opt.label or (isinstance(choice, str) and choice in opt.label):
                return opt.key
        # 3) 是索引（int 或数字字符串）
        try:
            idx = int(choice)
        except (TypeError, ValueError):
            return None
        if 0 <= idx < len(options):
            return options[idx].key
        return None


# ───────────────────────── 单例工厂（与 get_runtime 对等） ─────────────────────────
_DECISION_MODEL: "LayaDecisionModel | None" = None  # None=未初始化占位


def get_decision_model(
    *,
    model: str | None = None,
    threshold: float = 0.5,
) -> LayaDecisionModel:
    """进程内唯一的决策模型；首次调用时构造（多语言守护在构造内执行）。

    ``model`` 缺省取 ``OLLAYA_MODEL`` 环境变量，再缺省用白名单里的默认权重。
    配置非法时构造抛 ``ValueError``（此处不吞——那是配置错误，不是运行时降级）；
    模型本身不可用由 ``LayaDecisionModel.available()`` 反映，路由据此回落。
    """
    global _DECISION_MODEL
    if _DECISION_MODEL is None:
        _DECISION_MODEL = LayaDecisionModel(
            model=model or os.getenv(_OLLAYA_MODEL_ENV) or _DEFAULT_MODEL,
            threshold=threshold,
        )
    return _DECISION_MODEL
