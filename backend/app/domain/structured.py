"""结构化模型产出的读取工具（dict / pydantic / 对象通吃）。

模型结构化产出（``output_schema`` 约束解码）在不同引擎/版本下可能是 ``dict``、pydantic
模型或普通对象。本模块提供**两态统一读取**的最小工具，出题解析与开放题批改共用
（ADR-0031/0032：跨业务共用的小工具下沉到共享内核，而非任何一个业务包）。
"""
from __future__ import annotations

import re
from typing import Any


def schema_field(obj: Any, name: str, default: Any = None) -> Any:
    """读模型产出字段（兼容 dict 与 pydantic 对象）。"""
    if isinstance(obj, dict):
        return obj.get(name, default)
    return getattr(obj, name, default)


# 选项标号前缀：可带括号（(A) / （B））/ 字母或数字 + 分隔符（. 、 ： ． ) ]）。
# 只用于「切分」一段被模型揉在一起的选项串，不剥离——前缀由前端按位置重画，
# 且答案字段也带前缀，剥离会破坏判题比对（见 normalize_options）。
_OPTION_LABEL = re.compile(r"[\(（\[]?[A-Ea-e\d][\)）\].、：:．]\s*")


def _split_options(text: str) -> list[str]:
    """把一段可能揉了多个选项的文本切成「每个选项一段」。

    模型偶发不遵守 output_schema，把全部选项塞进一个字符串或某个列表元素：
    ``"A. 平行四边形 B. 等腰三角形 C. 任意梯形 D. 一般四边形"``。仅当找到 **≥2 个**
    选项标号时才切（避免把正文中偶然出现的「1. 」误拆），单标号或零标号原样返回。
    """
    labels = list(_OPTION_LABEL.finditer(text))
    if len(labels) < 2:
        return [text]
    out: list[str] = []
    for i, m in enumerate(labels):
        end = labels[i + 1].start() if i + 1 < len(labels) else len(text)
        piece = text[m.start():end].strip()
        if piece:
            out.append(piece)
    return out


def normalize_options(raw: object) -> list[str] | None:
    """把模型产出的 ``options`` 归一为「每个选项一段」的列表。

    处理三种畸形输入（均来自模型不守 output_schema）：
    - ``None`` / 非 list 非 str → 返回 ``None``（上层按「无选项」处理）；
    - 单个字符串（可能揉了多个选项）→ 切分；
    - list，但某元素本身揉了多个选项 → 把该元素再切分后展平。

    **只切分、不剥字母前缀**：前缀（"A."）由前端 ``cleanOptionText`` 按位置重画，
    且答案字段也带前缀，剥离会让判题比对失配。切分后每个选项仍保留自己的前缀。
    """
    if raw is None:
        return None
    if isinstance(raw, str):
        parts: list[str] = [raw]
    elif isinstance(raw, list):
        parts = [
            el if isinstance(el, str) else ("" if el is None else str(el))
            for el in raw
        ]
    else:
        return None

    out: list[str] = []
    for p in parts:
        p = p.strip()
        if not p:
            continue
        # 单元素若只含一个标号（已经是干净的一项）→ 保留；含多个标号 → 展平。
        out.extend(_split_options(p))
    return out or None


def coerce_dict(obj: Any) -> dict:
    """把结构化产出归一为 ``dict``（dict / pydantic model_dump / 可迭代键值）。"""
    if obj is None:
        return {}
    if isinstance(obj, dict):
        return obj
    if hasattr(obj, "model_dump"):
        return obj.model_dump()
    try:
        return dict(obj)
    except (TypeError, ValueError):
        return {}
