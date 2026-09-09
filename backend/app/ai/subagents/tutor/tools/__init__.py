"""伴学 SubAgent 专用 tool 目录。

伴学答疑执行体位于 ``../agent.py``（复用 TutorService + 知识库检索）。
若后续拆分出独立可复用的伴学工具（如「知识点检索」「错因诊断」），
在此放置为独立可执行函数并由 manifest ``tools`` 引用。
"""
