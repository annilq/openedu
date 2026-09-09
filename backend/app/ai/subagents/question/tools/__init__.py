"""出题 SubAgent 专用 tool 目录。

出题执行体（provider.generate_question + RAG/Persona）位于 ``../agent.py``；
后续若拆分出可独立复用的出题工具（如「按知识点检索题干」「难度自适应」），
在此放置为独立可执行函数并由 manifest ``tools`` 引用。
"""
