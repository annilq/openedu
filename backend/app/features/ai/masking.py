"""运行轨迹脱敏（ADR-0088 ticket 03）。

默认视图（debug 端点）：步级元数据（step / 模型 / token / 延迟 / 安全标记）可见；
tool 参数与结果（``payload``，含学生 PII：姓名/学号/作答）与正文脱敏，原文不可见。
管理员走破窗（``/reveal``）显原文——避免「站着就能读所有孩子对话」。
"""

from app.db.models import Message
from app.features.ai.schemas import MessageResp

# 脱敏占位：默认视图里正文与 tool 载荷被换成此标记，原文不出现在响应里。
REDACTED_MARKER = "⟨已脱敏⟩"


def mask_message(m: Message) -> MessageResp:
    """默认（脱敏）投影：正文与 tool 载荷都不可见，元数据保留。"""
    d = m.model_dump()
    d["content"] = REDACTED_MARKER
    d["payload"] = None
    d["redacted"] = True
    return MessageResp(**d)


def full_message(m: Message) -> MessageResp:
    """破窗（原文）投影：正文与 tool 载荷原样返回。"""
    d = m.model_dump()
    d["redacted"] = False
    return MessageResp(**d)
