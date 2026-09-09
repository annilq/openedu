"""Agent Runtime ↔ 前端 的统一事件信封（ADR-0025：AG-UI 式）。

一条 SSE 流由若干 ``AssistantEvent`` 帧组成；前端按 ``eventType`` 判别并分发渲染：
USER_MESSAGE / ASSISTANT_MESSAGE(delta) / THINKING(reasoning delta) /
TOOL_CALL / TOOL_RESULT / STEP(进度) / DATA(已收集到的结构化数据：题卡/任务卡) / ERROR / DONE。

STEP / DATA 直接复用 ADR-0017 出题信封语义，向后兼容。
所有帧以 ``data: {json}\\n\\n`` 推送（text/event-stream）。
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from typing import Any

# ── 事件类型常量（前端按此分发） ──
EVENT_RUN_STARTED = "RUN_STARTED"
EVENT_USER_MESSAGE = "USER_MESSAGE"
EVENT_THINKING = "THINKING"
EVENT_ASSISTANT_MESSAGE = "ASSISTANT_MESSAGE"
EVENT_TOOL_CALL = "TOOL_CALL"
EVENT_TOOL_RESULT = "TOOL_RESULT"
EVENT_STEP = "STEP"
EVENT_DATA = "DATA"
EVENT_ERROR = "ERROR"
EVENT_DONE = "DONE"
EVENT_RUN_FINISHED = "RUN_FINISHED"


def _new_id() -> str:
    return uuid.uuid4().hex[:12]


@dataclass
class AssistantEvent:
    """统一事件帧。``eventType`` 为判别字段；其余字段按事件类型可选。"""

    eventType: str
    id: str = field(default_factory=_new_id)
    # 通用可选字段（按 eventType 选用，缺省省略以保持帧精简）
    text: str | None = None          # USER_MESSAGE / ASSISTANT_MESSAGE / THINKING 的增量文本
    delta: str | None = None         # 同 text 的别名（ASSISTANT_MESSAGE 流式用 text）
    tool: str | None = None          # TOOL_CALL / TOOL_RESULT：工具/步骤名
    label: str | None = None         # TOOL_CALL / STEP：可读标签
    args: dict | None = None         # TOOL_CALL：入参
    result: Any | None = None        # TOOL_RESULT：出参
    status: str | None = None        # STEP / DONE：状态（running|done|error）
    data: dict | None = None         # DATA：结构化数据载荷 {status, type, result}
    message: str | None = None       # ERROR：可读错误
    code: str | None = None          # ERROR：错误码
    session_id: str | None = None    # DONE：本次会话 id
    blocked: bool | None = None      # 安全兜底标记（ASSISTANT_MESSAGE/ERROR）
    extra: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        """序列化为线协议 dict（省略 None 字段）。"""
        d: dict[str, Any] = {"eventType": self.eventType, "id": self.id}
        for key in (
            "text",
            "delta",
            "tool",
            "label",
            "args",
            "result",
            "status",
            "data",
            "message",
            "code",
            "session_id",
            "blocked",
        ):
            v = getattr(self, key)
            if v is not None:
                d[key] = v
        if self.extra:
            d["extra"] = self.extra
        return d

    def to_sse(self) -> str:
        """SSE 帧：``data: {json}\\n\\n``。"""
        return "data: " + json.dumps(self.to_dict(), ensure_ascii=False) + chr(10) + chr(10)


# ── 便捷构造器 ──
def user_message(text: str) -> AssistantEvent:
    return AssistantEvent(eventType=EVENT_USER_MESSAGE, text=text)


def thinking(delta: str, *, extra: dict | None = None) -> AssistantEvent:
    return AssistantEvent(eventType=EVENT_THINKING, text=delta, extra=extra or {})


def assistant_message(delta: str, *, blocked: bool | None = None) -> AssistantEvent:
    return AssistantEvent(eventType=EVENT_ASSISTANT_MESSAGE, text=delta, blocked=blocked)


def tool_call(tool: str, *, label: str | None = None, args: dict | None = None) -> AssistantEvent:
    return AssistantEvent(eventType=EVENT_TOOL_CALL, tool=tool, label=label, args=args)


def tool_result(tool: str, result: Any) -> AssistantEvent:
    return AssistantEvent(eventType=EVENT_TOOL_RESULT, tool=tool, result=result)


def step(label: str, *, status: str = "running") -> AssistantEvent:
    return AssistantEvent(eventType=EVENT_STEP, label=label, status=status)


def data_event(status: str, data_type: str, result: Any) -> AssistantEvent:
    """DATA 事件：已收集到的结构化数据（题卡/任务卡等）。

    ``data`` 载荷结构为 ``{status, type, result}``：
    - status: 采集状态（done / error / ...）
    - type:   数据种类（question | task | ...），取代旧 CARD 的 kind
    - result: 结构化结果载荷
    """
    return AssistantEvent(
        eventType=EVENT_DATA,
        data={"status": status, "type": data_type, "result": result},
    )


def error(message: str, *, code: str | None = None) -> AssistantEvent:
    return AssistantEvent(eventType=EVENT_ERROR, message=message, code=code)


def done(session_id: str | None = None) -> AssistantEvent:
    return AssistantEvent(eventType=EVENT_DONE, session_id=session_id)


def run_started() -> AssistantEvent:
    return AssistantEvent(eventType=EVENT_RUN_STARTED)


def run_finished() -> AssistantEvent:
    return AssistantEvent(eventType=EVENT_RUN_FINISHED)
