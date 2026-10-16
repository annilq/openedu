"""agent_core 工具抽象（真实 tool loop 的承载单元）。

``ToolSpec`` 描述一个可被模型选中的工具：名称、描述、参数 schema、执行处理器。
runtime 在 SubAgent 声明 ``tools`` 时，把 schema 随首轮请求发给模型；收到 ``ToolCall``
后执行对应 ``handler`` 并回灌结果，进入下一轮，直到模型不再请求工具。

两种执行形态（opt-in，互斥）：

- **同步**（``handler``）：一次 `await` 拿到完整结果，``tool_result`` 载荷即返回值。
- **流式**（``stream_handler``）：async generator，执行期间逐帧 yield 中间帧
  （THINKING / DATA / STEP…），**最后必须 yield 一个** :class:`ToolOutcome` 作为
  回灌 content。给「出题」这类长时流式生成用：用户侧体验（逐 token 思考、数据卡、
  进度锚点）不因 tool 化而丢失。
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, AsyncIterator


class ToolOutcome:
    """流式 tool 的末帧哨兵：``data`` 即回灌给模型的 tool content。

    同步工具不需要它（handler 的返回值天然是结局）。流式 generator 若正常结束却未
    yield 本对象，视为协议违例——runtime 以 ``{"error": ...}`` 回灌，不让空 content
    悄悄进入下一轮（那会让模型以为工具什么都没返回）。
    """

    __slots__ = ("data",)

    def __init__(self, data: Any) -> None:
        self.data = data


@dataclass
class ToolSpec:
    """一个可被模型调用的工具。

    ``handler`` 签名为 ``async (args: dict, *, ctx, session=None) -> Any``；
    runtime 捕获其返回值作为 ``tool_result`` 载荷。

    ``stream_handler`` 签名为 ``async generator (args, *, ctx, session=None)``，
    与 ``handler`` 二选一（同时提供时 runtime 取 ``stream_handler``）：逐帧 yield
    中间帧，末帧必须是 :class:`ToolOutcome`。流式分支下 runtime **不**再调用
    SubAgent 的 ``render_tool_result``——展示帧由 generator 自己负责，避免同一张卡
    发两遍。
    """

    name: str
    description: str
    schema: dict[str, Any]  # 参数的 JSON-schema（properties/required 等）
    handler: Callable[..., Any] | None = None
    # 面向用户的可读标签（如「查询娃娃列表」）：仅随 TOOL_CALL 帧下发供前端渲染
    # 中间状态，不进 to_schema()——模型看到的是 name/description，标签是纯展示。
    label: str | None = None
    # 流式执行器（opt-in）：非空即走流式分支，见模块 docstring。
    stream_handler: Callable[..., AsyncIterator[Any]] | None = field(default=None)

    def __post_init__(self) -> None:
        if self.handler is None and self.stream_handler is None:
            raise ValueError(
                f"ToolSpec({self.name!r}) 必须至少提供 handler 或 stream_handler 之一"
            )

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
