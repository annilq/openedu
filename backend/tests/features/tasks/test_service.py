"""tasks ``generate_task_stream`` 窄接口存活测试（绕过 HTTP 与真 LLM）。

只验证「构造 question subagent 上下文 + 透传 run 输出」这一编排：桩 ``AgentRuntime``
直接注入 ``runtime=...``，断言 SSE 帧逐条透传、且 run 收到 ``business="question"`` 与
正确 subject。把编排移回 router 会让本测试无法成立（深度保证书）。
"""
import asyncio
from collections.abc import AsyncIterator
from types import SimpleNamespace
from uuid import uuid4

from agent_core.protocol import EVENT_ASSISTANT_MESSAGE, EVENT_DATA, AssistantEvent
from agent_core.runtime import AgentRuntime
from app.features.tasks import service as tasks_service
from app.features.tasks.schemas import TaskGenerateReq, TaskSpec


class _StubRuntime(AgentRuntime):
    def __init__(self, events):
        self._events = events
        self.captured_ctx = None
        self.captured_business = None

    async def decide(self, *args, **kwargs):
        return SimpleNamespace(business="question", name="出题")

    def run(self, message, *, role, ctx, deps, business, session) -> AsyncIterator[AssistantEvent]:
        self.captured_ctx = ctx
        self.captured_business = business

        async def _gen():
            for ev in self._events:
                yield ev

        return _gen()


async def _drain(gen) -> list[str]:
    frames: list[str] = []
    async for frame in gen:
        frames.append(frame)
    return frames


def test_generate_task_stream_passthrough_and_ctx():
    # 临时替换真 provider / retriever 构造，避免触达任何 LLM 或网络。
    orig_provider = tasks_service.build_ai_provider
    orig_retriever = tasks_service.build_retriever
    tasks_service.build_ai_provider = lambda *a, **k: SimpleNamespace()
    tasks_service.build_retriever = lambda *a, **k: None
    try:
        events = [
            AssistantEvent(eventType=EVENT_DATA, data={"type": "question", "result": {"stem": "1+1"}}),
            AssistantEvent(eventType=EVENT_ASSISTANT_MESSAGE, text="出题完成"),
        ]
        rt = _StubRuntime(events)
        req = TaskGenerateReq(
            specs=[
                TaskSpec(
                    subject="数学",
                    grade=3,
                    knowledge_point="加法",
                    qtype="choice",
                    difficulty="easy",
                    count=1,
                )
            ]
        )
        parent = SimpleNamespace(id=uuid4())
        session = SimpleNamespace()  # 透传路径不持久化，session 仅透传

        gen = tasks_service.generate_task_stream(req=req, parent=parent, session=session, runtime=rt)
        frames = asyncio.run(_drain(gen))

        assert len(frames) == 2
        assert rt.captured_business == "question"
        assert rt.captured_ctx is not None
        assert rt.captured_ctx.extra["subject"] == "数学"
        assert rt.captured_ctx.extra["parent_id"] == parent.id
    finally:
        tasks_service.build_ai_provider = orig_provider
        tasks_service.build_retriever = orig_retriever
