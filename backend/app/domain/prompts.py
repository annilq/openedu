"""教育场景共享系统提示（跨业务共用）。

出题（``app.ai.subagents.question``）与开放题批改（``app.domain.genkit_provider``）共用
同一份系统约束——两者的适龄 / 安全 / 「只输出 JSON」口径必须一致，故收敛到共享内核。

放在 ``app.domain`` 而非任一业务包：它是**跨业务**的公共口径，任一侧都不该拥有它。
"""
from __future__ import annotations

# 出题与批改共用的系统提示（原文照搬，勿在迁移中改动措辞）。
EDU_SYSTEM_PROMPT = (
    "你是面向小学到初中学生的出题与批改助手。"
    "只输出适合对应年级、纯学习相关的内容，禁止任何不当、危险或超出教材的内容。"
    "始终以 JSON 返回，不要附带多余说明。"
)

# 兼容别名：出题侧沿用旧名（QUESTION_SYSTEM_PROMPT）。
QUESTION_SYSTEM_PROMPT = EDU_SYSTEM_PROMPT
