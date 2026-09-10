"""agent_core 工具抽象（真实 tool loop 的承载单元）。

``ToolSpec`` 描述一个可被模型选中的工具：名称、描述、参数 schema、执行处理器。
runtime 在 SubAgent 声明 ``tools`` 时，把 schema 随首轮请求发给模型；收到 ``ToolCall``
后执行对应 ``handler`` 并回灌结果，进入下一轮，直到模型不再请求工具。
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable


@dataclass
class ToolSpec:
    """一个可被模型调用的工具。

    ``handler`` 签名为 ``async (args: dict, *, ctx, session=None) -> Any``；
    runtime 捕获其返回值作为 ``tool_result`` 载荷。
    """

    name: str
    description: str
    schema: dict[str, Any]  # 参数的 JSON-schema（properties/required 等）
    handler: Callable[..., Any]

    def to_schema(self) -> dict[str, Any]:
        """转换为通用工具声明（模型厂商无关）。"""
        return {
            "name": self.name,
            "description": self.description,
            "parameters": self.schema,
        }


@dataclass
class ToolRegistry:
    """工具名 → 规格 的轻量索引，供 runtime 快速查表执行。"""

    specs: list[ToolSpec]

    def __post_init__(self) -> None:
        self._by_name = {s.name: s for s in self.specs}

    def get(self, name: str) -> ToolSpec | None:
        return self._by_name.get(name)

    def schemas(self) -> list[dict[str, Any]]:
        return [s.to_schema() for s in self.specs]
