"""伴学 SubAgent 专用 tool 目录（占位）。

伴学答疑执行体位于 ``../agent.py``（复用 TutorService + 知识库检索）。
注意：本目录下的函数**不会**被任何 manifest/运行时自动发现——SubAgent 在 ``run()``
内直接 import 调用。若拆分出独立可复用的伴学工具（如「知识点检索」「错因诊断」），
在此放置为独立函数并由 ``../agent.py`` 显式引用即可。
"""
