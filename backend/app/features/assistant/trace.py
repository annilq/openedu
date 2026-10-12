"""步级可观测字段的**口径**收口（ADR-0088 §2.5）。

``Message`` 的 ``model`` / ``usage`` / ``latency_ms`` / ``input_safe`` / ``output_safe`` /
``blocked`` / ``block_reason`` 七列自 ADR-0022 起就在表里，但落库路径从未赋值——运行
轨迹页因此拿不到「哪一步最费 token / 最慢 / 被拦」。本模块把这几列**怎么算**收口到
一处：口径写两遍，迟早出现「两个面板对不上」的排障事故。

- ``usage``：token 字典 ``{prompt, completion, total}``，与 ``ai/schemas.MessageResp``
  的 ``usage`` 同一形状（前端可直接消费）。模型方（genkit 适配器）目前不回传真实
  usage，故按 ``repository._estimate_tokens`` 的同一粗估口径（约 4 字符 / token）折算；
  将来接上真实回传只改本模块，落库路径不动。
- ``latency_ms``：``perf_counter`` 上的步间耗时，不用 wall clock——后者会被 NTP 拨回，
  出现「负耗时」这种比没有数据更糟的数据。

**会话级总成本不建汇总列**：步级 usage 按 ``conversation_id`` 聚合即可上推，且保留
「哪一步最费 token」的排障粒度（ADR-0088 §2.5）。
"""
from __future__ import annotations

import json
from time import perf_counter
from typing import Any

# 与 ``repository._estimate_tokens`` 同源的粗估：约 4 字符 / token。
_CHARS_PER_TOKEN = 4


def _tokens(text: str) -> int:
    return len(text) // _CHARS_PER_TOKEN


def usage_of(*, prompt: str = "", completion: str = "") -> dict[str, int]:
    """一步的 token 估算字典 ``{prompt, completion, total}``。"""
    p = _tokens(prompt)
    c = _tokens(completion)
    return {"prompt": p, "completion": c, "total": p + c}


def json_text(value: Any) -> str:
    """把工具入参 / 结果折算成可估算长度的文本（不可序列化时退化为空串）。

    usage 只关心量级，序列化失败不该让落库路径炸掉——那会把一次可观测写入
    变成一次用户可见的失败。
    """
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    try:
        return json.dumps(value, ensure_ascii=False, default=str)
    except (TypeError, ValueError):
        return ""


def elapsed_ms(since: float) -> int:
    """``perf_counter`` 起点 → 现在的毫秒数（``latency_ms`` 的唯一换算口径）。"""
    return int((perf_counter() - since) * 1000)
