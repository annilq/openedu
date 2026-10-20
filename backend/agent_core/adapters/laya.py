"""Laya-multilingual 决策模型适配器（agent_core 第一方适配器，与 genkit 平级）。

硬前提：必须用 ``convaiinnovations/laya-multilingual``（100+ 语言含中文，mmBERT-base
322M，1024 tok，Apache-2.0），**绝不能用英文 ``laya``**（英文版在非英语上「自信但错误」——
高棉语 0.000 准确率却仍高置信，仅 23/51 语种过 3×随机线）。产品是中文，英文版是错误选择。

本适配器为「尽力可用」实现：未配置服务 / 缺权重 / 离线时 ``available()`` 返回 False，
路由回落 LLM 分类或兜底助手，链路不崩。真实 ``laya-serve`` 就位（设 ``LAYA_SERVE_URL``）
后自动激活，无需改路由代码。
"""
from __future__ import annotations

import os
from typing import Any

from agent_core.ports import DecisionModel, DecisionOption, DecisionResult

# 允许的模型仓库（硬约束：仅 multilingual）。字符串匹配，避免路径/大小写歧义。
_ALLOWED_REPOS = frozenset({"convaiinnovations/laya-multilingual"})


def _assert_multilingual(repo: str) -> None:
    """配置守护：仅 ``laya-multilingual`` 可用，拒绝英文 ``laya`` 等违规配置。"""
    if repo not in _ALLOWED_REPOS:
        raise ValueError(
            f"决策模型仅允许 {sorted(_ALLOWED_REPOS)}；"
            f"拒绝 {repo!r}——英文 laya 在非英语上自信但错误，本产品为中文场景。"
        )


class _LayaServeEngine:
    """懒加载的 ``laya-serve``（Jev 兼容 ``POST /v1/systemone``）客户端。

    仅作「尽力连接」：导入失败 / 未配置 ``LAYA_SERVE_URL`` / 首次请求失败都为 ``None``，
    不抛错（决策模型不可用是预期降级路径，不是异常）。真实权重就位后自动激活。
    """

    def __init__(self, base_url: str | None = None) -> None:
        self._base_url = base_url or os.getenv("LAYA_SERVE_URL")
        self._client = None
        self._loaded = False

    @property
    def configured(self) -> bool:
        """是否配置了服务地址（廉价同步判断，不发起网络握手）。"""
        return bool(self._base_url)

    def _ensure(self) -> bool:
        if self._loaded:
            return self._client is not None
        self._loaded = True
        if not self._base_url:
            return False
        try:
            import urllib.request

            self._client = (urllib.request, self._base_url)
            return True
        except Exception:  # noqa: BLE001 — 任何失败都视为不可用，回落 LLM 分类 / 兜底助手
            return False

    def predict(
        self, state: str, questions: list[dict[str, Any]]
    ) -> list[dict[str, Any]] | None:
        """调用 laya-serve 的 system-one 端点，返回每个问题的 ``{"choice", "prob"}``。

        失败（网络/超时/非 2xx）返回 ``None``，由调用方回落。
        """
        if not self._ensure():
            return None
        import json
        import urllib.request

        url = f"{self._base_url.rstrip('/')}/v1/systemone"
        payload = json.dumps({"state": state, "questions": questions}).encode("utf-8")
        req = urllib.request.Request(
            url, data=payload, headers={"Content-Type": "application/json"}
        )
        try:
            with urllib.request.urlopen(req, timeout=2.0) as resp:  # noqa: S310 — 内网受控地址
                data = json.loads(resp.read().decode("utf-8"))
        except Exception:  # noqa: BLE001 — 超时/非 2xx 一律视为不可用
            return None
        # laya-serve 返回形如 {"answers": [{"choice": <label>, "prob": float}, ...]}
        answers = data.get("answers") if isinstance(data, dict) else None
        return answers if isinstance(answers, list) else None


class LayaDecisionModel(DecisionModel):
    """决策模型端口的 Laya-multilingual 实现。

    - 路由决策：把可见 business 的能力清单作为 ``choice`` 问题的选项，state = 近期
      对话上下文，问「哪个业务处理本 state」，取校准概率最高者。
    - 低于 ``threshold`` 或无法决策 → ``decide`` 返回 ``None``，路由回落 LLM 分类或兜底助手。
    - ``engine`` 可注入（测试 / 私有部署）；缺省懒连 ``laya-serve``。
    """

    def __init__(
        self,
        *,
        repo: str = "convaiinnovations/laya-multilingual",
        threshold: float = 0.5,
        engine: Any | None = None,
    ) -> None:
        _assert_multilingual(repo)
        self._repo = repo
        self._threshold = float(threshold)
        self._engine = engine if engine is not None else _LayaServeEngine()

    def available(self) -> bool:
        """引擎就绪才视为可用：注入引擎恒真；laya-serve 需已配置 ``LAYA_SERVE_URL``。

        不做网络握手（廉价同步检查）；握手失败由 ``decide`` 的 predict 返回 ``None`` 兜底。
        """
        if self._engine is None:
            return False
        if isinstance(self._engine, _LayaServeEngine):
            return self._engine.configured
        return True

    async def decide(
        self, *, state: str, options: list[DecisionOption]
    ) -> DecisionResult | None:
        if self._engine is None:
            return None
        if not options:
            return None

        question = {
            "type": "choice",
            "question": "给定以上对话，应由哪个助手继续处理用户的最新消息？",
            "options": [opt.label for opt in options],
        }
        try:
            answers = self._engine.predict(state, [question])
        except Exception:  # noqa: BLE001 — 模型异常不应击穿路由，回落 LLM 分类 / 兜底助手
            return None
        if not answers:
            return None
        ans = answers[0]
        choice = ans.get("choice") if isinstance(ans, dict) else None
        prob = float(ans.get("prob", 0.0)) if isinstance(ans, dict) else 0.0

        key = self._resolve_key(choice, options)
        if key is None or prob < self._threshold:
            # 无法解析选项 / 低于置信阈值 → 视为无决策，回落 LLM 分类 / 兜底助手
            return None
        return DecisionResult(choice=key, prob=prob, raw=ans)

    @staticmethod
    def _resolve_key(choice: Any, options: list[DecisionOption]) -> str | None:
        """把模型回传的 choice（可能是 key / label / 索引）映射回业务 key。"""
        if choice is None:
            return None
        # 1) 直接是某个选项的 key
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
    repo: str = "convaiinnovations/laya-multilingual",
    threshold: float = 0.5,
) -> LayaDecisionModel | None:
    """进程内唯一的决策模型；首次调用时构造（multilingual 守护在构造内执行）。

    返回 ``None`` 仅当配置非法（应为编程错误，构造已抛 ``ValueError``——此处不吞）；
    模型本身不可用由 ``LayaDecisionModel.available()`` 反映，实例仍返回，路由据此回落。
    """
    global _DECISION_MODEL
    if _DECISION_MODEL is None:
        _DECISION_MODEL = LayaDecisionModel(repo=repo, threshold=threshold)
    return _DECISION_MODEL  # type: ignore[return-value]
