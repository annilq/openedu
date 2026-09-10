"""出题 SubAgent 专用 tool 目录（占位）。

出题执行体（provider.generate_question + RAG/Persona）位于 ``../agent.py``。
注意：本目录下的函数**不会**被任何 manifest/运行时自动发现——SubAgent 在 ``run()``
内直接 import 调用。若拆分出可独立复用的出题工具（如「按知识点检索题干」「难度自适应」），
在此放置为独立函数并由 ``../agent.py`` 显式引用即可。
"""
