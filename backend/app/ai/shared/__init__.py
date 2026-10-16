"""``app.ai.shared``：业务 agent 工具的跨域共享件（ADR-0097）。

query 解散后，原 ``query/tools/_shared.py`` 的职责由三个业务 agent
（tasks / questions / students）共用。放在 ``app/ai/`` 而非 ``agent_core/``：
这些是教育业务语义（学生定位、答案裁剪、分块信封），内核保持零业务依赖。
"""
