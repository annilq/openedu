"""``query`` 学情查询 SubAgent（ADR-0033）。

只读业务查询 SubAgent：双端可见（``roles: [parent, child]``），承载 7 个查询工具，
经 ``/assistant/chat`` 由模型以原生 function calling 调度。吸收并取代原 ``tasks``。
"""
from app.ai.subagents.query.agent import QuerySubAgent

__all__ = ["QuerySubAgent"]
