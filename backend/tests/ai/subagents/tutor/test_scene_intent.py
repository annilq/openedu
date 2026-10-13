"""答疑「要不要出图」三层识别（ADR-0089 §4，ticket 03）。

钉死四件事：
- **L0 确定性门控（不调模型）**：解析不出知识点 → 一次模型调用都不发、也不发射场景卡。
- **L2 后端校验盖章**：``should_show`` / ``figure_key`` 自洽、键 ∈ 目录、图库有行 → 才发射；
  四态全部不发射（决定权在后端，模型只有建议权）。
- **异常态**：L1 微调用抛错 → 不发射、不吞正文（返回 ``None``）。
- **去重**：与上一条已发射身份键相同 → 不重复发射。
- **顶点不进提示词**：喂给模型的目录只含 ``key — 中文名``。

本仓库未启用 ``pytest-asyncio``，异步入口统一用 ``asyncio.run`` 包裹（见
``tests/domain/test_tutor.py`` 先例）。
"""
import asyncio
import uuid

from agent_core.ports import StructuredDone, TextDelta
from agent_core.subagent import SubAgentContext
from app.ai.subagents.tutor.agent import TutorSubAgent
from app.ai.subagents.tutor.scene_intent import (
    SceneIntent,
    accept_scene_intent,
    resolve_interactive_scene,
    resolve_scene_knowledge_point,
)
from app.db.models import Conversation, KnowledgePoint, Message


class _FakeIntentProvider:
    """确定性意图微调用替身：返回可配置的 :class:`SceneIntent`，记录调用与末次 prompt。"""

    configured = True

    def __init__(self, *, intent: SceneIntent | None = None, raise_error: bool = False) -> None:
        self.intent = intent or SceneIntent()
        self.raise_error = raise_error
        self.calls: list[tuple[str, str]] = []
        self.last_prompt: str | None = None

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        self.calls.append((system, prompt))
        self.last_prompt = prompt
        if self.raise_error:
            raise RuntimeError("boom")
        yield TextDelta(delta="reasoning")
        yield StructuredDone(data=self.intent.model_dump())


_KP = "图形的运动（轴对称）"


# ───────────────────── L0 门控（不调模型） ─────────────────────


def test_l0_no_knowledge_point_emits_no_microcall(db):
    """解析不出知识点 → 不放行、一次模型调用都不发（断言微调用次数为 0）。"""

    async def _run():
        provider = _FakeIntentProvider(intent=SceneIntent(should_show=True, figure_key="square"))
        result = await resolve_interactive_scene(
            provider=provider, session=db, message="对称轴有几条",
            subject="数学", grade=4, teacher_id=uuid.uuid4(),
        )
        assert result is None
        assert provider.calls == []  # 微调用次数为 0

    asyncio.run(_run())


def test_l0_passes_to_l1_when_kp_resolves(db):
    """知识点可解析（即使无匹配模板，目录回落图库全量非空）→ 放行并发起 L1。"""

    async def _run():
        provider = _FakeIntentProvider(intent=SceneIntent(should_show=True, figure_key="square"))
        await resolve_interactive_scene(
            provider=provider, session=db, message="对称轴有几条",
            knowledge_point=_KP, subject="数学", grade=4, teacher_id=uuid.uuid4(),
        )
        assert len(provider.calls) == 1  # L0 放行才发起 L1 微调用

    asyncio.run(_run())


def test_l0_resolves_kp_by_id(db):
    """只给知识点 id（无 name）→ 门控应解析出知识点名并发起 L1。"""
    teacher_id = uuid.uuid4()
    kp = KnowledgePoint(
        id=uuid.uuid4(), teacher_id=teacher_id, subject="数学", grade=4,
        semester="", name="轴对称",
    )
    db.add(kp)
    db.commit()

    async def _run():
        provider = _FakeIntentProvider(intent=SceneIntent(should_show=True, figure_key="square"))
        await resolve_interactive_scene(
            provider=provider, session=db, message="...",
            knowledge_point_id=kp.id, subject="数学", grade=4, teacher_id=teacher_id,
        )
        assert len(provider.calls) == 1

    asyncio.run(_run())


def test_resolve_kp_prefers_name_over_id():
    """给了 name 直接返回，不查库；都没有 → 空串（门控不放行）。"""
    assert resolve_scene_knowledge_point(None, knowledge_point="轴对称") == "轴对称"
    assert resolve_scene_knowledge_point(None) == ""


def test_resolve_kp_id_unowned_returns_empty(db):
    """知识点不归该教师 → require_owned 抛错 → 空串（门控不放行，不崩）。"""
    other = uuid.uuid4()
    kp = KnowledgePoint(
        id=uuid.uuid4(), teacher_id=other, subject="数学", grade=4,
        semester="", name="轴对称",
    )
    db.add(kp)
    db.commit()
    assert resolve_scene_knowledge_point(db, knowledge_point_id=kp.id, teacher_id=uuid.uuid4()) == ""


# ───────────────────── L2 校验盖章：四态 ─────────────────────


def test_accept_scene_intent_four_non_emit_states():
    allowed = {"square"}
    # 1. should_show=False → 不发射
    assert accept_scene_intent(SceneIntent(should_show=False), allowed=allowed) is None
    # 2. 说要出却不给键 → 冲突取保守，不发射
    assert accept_scene_intent(SceneIntent(should_show=True, figure_key=None), allowed=allowed) is None
    # 3. 键不在目录内（模型幻觉）→ 不发射
    assert accept_scene_intent(SceneIntent(should_show=True, figure_key="ghost"), allowed=allowed) is None
    # 4. 通过 → 返回键
    assert accept_scene_intent(SceneIntent(should_show=True, figure_key="square"), allowed=allowed) == "square"


def test_full_path_four_states(db):
    """端到端四态：模型给不同意图，后端决定权恒为「不发射 / 发射」。"""

    async def _run():
        common = dict(
            session=db, message="...", knowledge_point=_KP, subject="数学",
            grade=4, teacher_id=uuid.uuid4(),
        )
        # should_show=False
        assert await resolve_interactive_scene(
            provider=_FakeIntentProvider(intent=SceneIntent(should_show=False)), **common
        ) is None
        # 给键却不该出（冲突）→ 不发射
        assert await resolve_interactive_scene(
            provider=_FakeIntentProvider(intent=SceneIntent(should_show=True, figure_key=None)),
            **common,
        ) is None
        # 目录外的键（模型幻觉）→ 不发射
        assert await resolve_interactive_scene(
            provider=_FakeIntentProvider(intent=SceneIntent(should_show=True, figure_key="ghost")),
            **common,
        ) is None
        # 合法键 → 发射，kind 恒 reflection
        out = await resolve_interactive_scene(
            provider=_FakeIntentProvider(intent=SceneIntent(should_show=True, figure_key="square")),
            **common,
        )
        assert isinstance(out, dict)
        assert out["kind"] == "reflection"
        assert out["figure"]["key"] == "square"

    asyncio.run(_run())


def test_l1_error_does_not_emit(db):
    """L1 微调用抛错 → 不发射、不抛错（正文照常）。"""

    async def _run():
        provider = _FakeIntentProvider(
            intent=SceneIntent(should_show=True, figure_key="square"), raise_error=True
        )
        result = await resolve_interactive_scene(
            provider=provider, session=db, message="...", knowledge_point=_KP,
            subject="数学", grade=4, teacher_id=uuid.uuid4(),
        )
        assert result is None

    asyncio.run(_run())


# ───────────────────── 去重 ─────────────────────


def test_dedup_skips_same_last_key(db):
    """与上一条已发射身份键相同 → 不重复发射。"""
    conv_id = uuid.uuid4()
    db.add(Conversation(id=conv_id, kind="agent", teacher_id=uuid.uuid4()))
    db.add(
        Message(
            conversation_id=conv_id, turn=1, role="assistant", step="output", content="",
            payload={"cards": [{"type": "interactive_scene",
                                "result": {"figure": {"key": "square", "label": "正方形"}}}]},
        )
    )
    db.commit()

    async def _run():
        provider = _FakeIntentProvider(intent=SceneIntent(should_show=True, figure_key="square"))
        result = await resolve_interactive_scene(
            provider=provider, session=db, conv_id=conv_id, message="...",
            knowledge_point=_KP, subject="数学", grade=4, teacher_id=uuid.uuid4(),
        )
        assert result is None

    asyncio.run(_run())


def test_dedup_allows_different_key(db):
    """换过别的键 → 照常发射。"""
    conv_id = uuid.uuid4()
    db.add(Conversation(id=conv_id, kind="agent", teacher_id=uuid.uuid4()))
    db.add(
        Message(
            conversation_id=conv_id, turn=1, role="assistant", step="output", content="",
            payload={"cards": [{"type": "interactive_scene",
                                "result": {"figure": {"key": "square", "label": "正方形"}}}]},
        )
    )
    db.commit()

    async def _run():
        provider = _FakeIntentProvider(intent=SceneIntent(should_show=True, figure_key="para"))
        result = await resolve_interactive_scene(
            provider=provider, session=db, conv_id=conv_id, message="...",
            knowledge_point=_KP, subject="数学", grade=4, teacher_id=uuid.uuid4(),
        )
        assert isinstance(result, dict)
        assert result["figure"]["key"] == "para"

    asyncio.run(_run())


# ───────────────────── 顶点不进提示词 ─────────────────────


def test_catalog_passed_to_model_has_no_vertices(db):
    """喂给模型的目录只含 key — 中文名，绝不出现顶点坐标。"""

    async def _run():
        provider = _FakeIntentProvider(intent=SceneIntent(should_show=True, figure_key="square"))
        await resolve_interactive_scene(
            provider=provider, session=db, message="...", knowledge_point=_KP,
            subject="数学", grade=4, teacher_id=uuid.uuid4(),
        )
        prompt = provider.last_prompt
        assert prompt is not None
        assert "square" in prompt and "正方形" in prompt
        # 顶点是 (0..1) 坐标，catalog 只给 key — 中文名，绝不含坐标。
        assert "0." not in prompt
        assert "[" not in prompt

    asyncio.run(_run())


# ───────────────────── 集成：tutor agent 接线 ─────────────────────


def test_agent_wiring_maps_ctx_extra(db):
    """tutor agent 把 ctx.extra 收齐转交三层识别；courseware 里的知识点生效。"""

    async def _run():
        provider = _FakeIntentProvider(intent=SceneIntent(should_show=True, figure_key="square"))
        agent = TutorSubAgent(provider=provider)
        ctx = SubAgentContext(
            role="student", message="...", history=[], model=None, skills="",
            extra={
                "teacher_id": uuid.uuid4(),
                "subject": "数学",
                "grade": 4,
                "knowledge_point_id": None,
                "session_id": str(uuid.uuid4()),
                "courseware": {"knowledge_point": _KP, "semester": ""},
            },
        )
        result = await agent._interactive_scene_for("正方形有几条对称轴", ctx, session=db)
        assert isinstance(result, dict)
        assert result["figure"]["key"] == "square"

    asyncio.run(_run())


def test_agent_wiring_no_kp_no_emit(db):
    """无任何知识点来源 → 不发射、不发起微调用。"""

    async def _run():
        provider = _FakeIntentProvider(intent=SceneIntent(should_show=True, figure_key="square"))
        agent = TutorSubAgent(provider=provider)
        ctx = SubAgentContext(
            role="student", message="今天作业是什么", history=[], model=None, skills="",
            extra={
                "teacher_id": uuid.uuid4(),
                "subject": "数学",
                "grade": 4,
                "knowledge_point_id": None,
                "session_id": str(uuid.uuid4()),
                "courseware": None,
            },
        )
        result = await agent._interactive_scene_for("今天作业是什么", ctx, session=db)
        assert result is None
        assert provider.calls == []

    asyncio.run(_run())


def test_scene_intent_model_invariants():
    """SceneIntent 是结构化微调用的契约：should_show 默认 False（保守）。"""
    assert SceneIntent().should_show is False
    assert SceneIntent(should_show=True, figure_key="square").figure_key == "square"
