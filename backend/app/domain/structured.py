"""结构化模型产出的读取工具（dict / pydantic / 对象通吃）。

模型结构化产出（``output_schema`` 约束解码）在不同引擎/版本下可能是 ``dict``、pydantic
模型或普通对象。本模块提供**两态统一读取**的最小工具，出题解析与开放题批改共用
（ADR-0031/0032：跨业务共用的小工具下沉到共享内核，而非任何一个业务包）。
"""
from __future__ import annotations

from typing import Any


def schema_field(obj: Any, name: str, default: Any = None) -> Any:
    """读模型产出字段（兼容 dict 与 pydantic 对象）。"""
    if isinstance(obj, dict):
        return obj.get(name, default)
    return getattr(obj, name, default)


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
