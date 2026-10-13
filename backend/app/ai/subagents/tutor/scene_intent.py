"""答疑「要不要出图」的三层识别（ADR-0089 §4：L0 门控 → L1 模型判定 → L2 校验盖章）。

核心立场一句话：**模型有建议权，没有决定权**——模型只能从「本次可用图形目录」里挑一个
身份键，几何永远由后端按该键从图形几何库（``figure_library``）盖章取来。

三层各答一个问题：

- **L0 确定性门控（不调模型、零成本）**：能解析出知识点 **且** 能投影出非空图形目录吗？
  两个都答「是」才发起 L1；否则**一次模型调用都不发**，也不发射场景卡。
  ⚠️ **不用意图关键词**做门控——关键词仍是猜（只是把「猜图形」换成「猜要不要问」），
  而知识点场景是教师显式配置的、更强且零成本的信号。
- **L1 模型判定（一次结构化微调用）**：只喂四样——知识点名、图形目录（只有身份键 + 中文名）、
  学生原话、（有则）上下文。目录条目是 ``FigureRef``（**没有几何字段**），类型层面就保证
  「顶点进不了提示词」。
- **L2 后端校验盖章**：``should_show`` 与 ``figure_key`` 必须自洽（冲突取保守）、键必须在
  目录内、图形几何库必须有这一行——任一不过就不发射。``kind`` 由盖章原语恒给 ``reflection``，
  **不由模型输出**（它是稳定契约，不是模型的判断）。

删除纪律：本模块取代 ``scene_extract.extract_scene_inputs``（「从提问文字反猜图形」）。
那条路径连同整个抽取模块一起删除——后端从此不从自然语言猜任何图形；未命中 / 异常一律
不发射，且**绝不回退到关键词猜测**。

边界：本模块是答疑侧编排（``ai/subagents/tutor``），投影 / 校验 / 盖章的实现在
``features/materials/figure_stamp.py``（与出题侧共用同一套）。
"""
from __future__ import annotations

from typing import Any
from uuid import UUID

from sqlmodel import SQLModel

from agent_core.ports import StructuredDone
from app.core.errors import AppErrorException
from app.core.guard import require_owned
from app.db.models import KnowledgePoint
from app.features.assistant.repository import last_scene_figure_key
from app.features.materials.figure_stamp import (
    available_figures,
    render_figure_catalog,
    stamp_scene_spec,
)
from app.features.materials.scene_fusion import find_knowledge_point

__all__ = [
    "SCENE_INTENT_SYSTEM_PROMPT",
    "SceneIntent",
    "accept_scene_intent",
    "build_scene_intent_prompt",
    "resolve_interactive_scene",
    "resolve_scene_intent",
    "resolve_scene_knowledge_point",
]


class SceneIntent(SQLModel):
    """这次提问要不要出示交互演示、出示哪个图形（L1 的结构化产出）。"""

    should_show: bool = False  # 模型整体判断：这一问该不该出图
    figure_key: str | None = None  # 只能是目录里的身份键
    rationale: str = ""  # 仅调试 / 轨迹用，不进正文


SCENE_INTENT_SYSTEM_PROMPT = (
    "你是教学演示判定助手。判断学生这一问要不要出示一个可交互的平面图形，以及出示哪一个。\n"
    "硬约束：只能从给定目录里选**一个身份键**；目录之外的图形一律不选；"
    "绝不输出顶点坐标、绝不描述图形的形状细节——几何由系统按身份键取权威数据。"
)


def build_scene_intent_prompt(
    *,
    knowledge_point: str,
    catalog: str,
    message: str,
    context: str | None = None,
) -> str:
    """L1 的用户消息：四样输入（知识点 / 目录 / 原话 / 有则上下文）+ 判据与反例。"""
    lines = [f"知识点：{knowledge_point}"]
    if context:
        lines.append(f"上下文：{context}")
    lines += [
        "可用图形目录（身份键 — 中文名）：",
        catalog,
        "",
        "判断标准：",
        "✅ should_show=true：理解这一问需要**看着图形操作**——数对称轴、判断对折是否重合、"
        "数边 / 角、比较面积、判断某个图形是否属于某一类。",
        "⛔ should_show=false：问定义、问作业、程序性事务；图形只是举例而不是提问对象；"
        "目录里没有能表达它的图形。",
        "",
        "反例（这些一律 should_show=false）：",
        "- 「今天的作业是什么」",
        "- 「这个词怎么读」",
        "- 「帮我算 25×4」",
        "",
        f"学生原话：{message}",
    ]
    return "\n".join(lines)


async def resolve_scene_intent(
    provider,
    *,
    knowledge_point: str,
    catalog: str,
    message: str,
    context: str | None = None,
) -> SceneIntent | None:
    """L1：一次结构化微调用 → :class:`SceneIntent`。

    未配置引擎 / 抛错 / 模型没给结构化产出 / 结构化产出畸形 → 一律 ``None``
    （调用方据此**不发射**；场景卡是答疑的增强，任何岔子都不许吞掉讲解正文）。
    """
    if provider is None or not getattr(provider, "configured", True):
        return None
    prompt = build_scene_intent_prompt(
        knowledge_point=knowledge_point, catalog=catalog, message=message, context=context
    )
    try:
        async for ev in provider.stream(
            SCENE_INTENT_SYSTEM_PROMPT, prompt, schema=SceneIntent
        ):
            if isinstance(ev, StructuredDone):
                return _coerce_intent(ev.data)
    except Exception:  # noqa: BLE001 — 微调用失败绝不能吞掉主功能（讲解正文照常）
        return None
    return None


def _coerce_intent(data: Any) -> SceneIntent | None:
    """结构化产出 → :class:`SceneIntent`；畸形（非 dict / 字段不符）按「不出图」处理。"""
    if isinstance(data, SceneIntent):
        return data
    if isinstance(data, dict):
        try:
            return SceneIntent.model_validate(data)
        except Exception:  # noqa: BLE001 — 模型偶发不守 schema 属正常输入，不抛错
            return None
    return None


def accept_scene_intent(intent: SceneIntent | None, *, allowed: set[str]) -> str | None:
    """L2 前半：自洽性 + 目录内校验（纯函数）。通过 → 可盖章的身份键；否则 ``None``。

    四态全部不发射：

    - ``should_show`` 为假 → 不发射（模型说不该出图）；
    - ``figure_key`` 为空 → 不发射（**说要出却不给键 = 冲突，取保守**）；
    - 说不该出却给了键 → 被第一条挡掉（同样是冲突取保守）；
    - 键不在本次目录内 → 不发射（模型幻觉属正常输入，不抛错）。

    通过之后还有第二道：几何库里必须有这一行——那一步在盖章原语里
    （``stamp_scene_spec`` 返回 ``None`` 即不发射）。
    """
    if intent is None or not intent.should_show:
        return None
    key = (intent.figure_key or "").strip()
    if not key or key not in allowed:
        return None
    return key


def resolve_scene_knowledge_point(
    session,
    *,
    knowledge_point: str = "",
    knowledge_point_id: Any = None,
    teacher_id: Any = None,
) -> str:
    """L0 第一步：解析本次提问所属的**知识点名**（零模型调用）。

    两个来源，按可靠性排序（都不满足就返回空串 → 门控不放行）：

    1. 调用方已给的知识点名（课件上下文 / 题目上下文里的 ``knowledge_point``）；
    2. 知识点精确 id（课件下钻 / 学生当前知识点）→ 按归属校验后读它的 ``name``。

    ⚠️ **刻意不做「从提问文字猜知识点」**：本仓库没有「文本 → 知识点」的解析器，
    而新造一套按字面匹配知识点的口径，正是 ADR-0089 要消灭的「猜」——它还会与
    ``find_knowledge_point`` 的匹配口径形成第二份事实源。故「都没有」时门控直接
    不放行（不发射场景卡，正文照常），而不是回退去猜。
    """
    if knowledge_point:
        return knowledge_point
    if session is None or knowledge_point_id is None or teacher_id is None:
        return ""
    try:
        kp = require_owned(
            session=session,
            owner_id=teacher_id,
            model=KnowledgePoint,
            obj_id=UUID(str(knowledge_point_id)),
        )
    except (AppErrorException, ValueError, TypeError, AttributeError):
        return ""
    return kp.name or ""


async def resolve_interactive_scene(
    *,
    provider=None,
    session=None,
    conv_id: Any = None,
    message: str = "",
    knowledge_point: str = "",
    knowledge_point_id: Any = None,
    subject: str = "",
    grade: int = 0,
    semester: str = "",
    teacher_id: Any = None,
    context: str | None = None,
) -> dict | None:
    """整条三层识别链路：命中 → ``SceneSpec`` 的裸 dict（SSE 载荷要 JSON 友好）；否则 ``None``。

    SSE 载荷在此边界 ``model_dump`` 成裸 dict——前端 ``SceneInterpreter`` 吃的就是裸 Map。
    """
    if session is None or not (message or "").strip():
        return None

    # ── L0 门控（不调模型、零成本）：知识点 + 非空图形目录 ──
    kp_name = resolve_scene_knowledge_point(
        session,
        knowledge_point=knowledge_point,
        knowledge_point_id=knowledge_point_id,
        teacher_id=teacher_id,
    )
    if not kp_name:
        return None
    kp = find_knowledge_point(
        session,
        teacher_id=teacher_id,
        subject=subject,
        grade=grade,
        knowledge_point=kp_name,
        semester=semester,
    )
    figures = available_figures(session, kp=kp)
    if not figures:
        return None
    allowed = {ref.key for ref in figures}

    # ── L1 模型判定：一次结构化微调用（只喂目录，不喂顶点） ──
    intent = await resolve_scene_intent(
        provider,
        knowledge_point=kp_name,
        catalog=render_figure_catalog(figures),
        message=message,
        context=context,
    )

    # ── L2 校验 + 盖章：决定权在后端 ──
    key = accept_scene_intent(intent, allowed=allowed)
    if key is None:
        return None
    spec = stamp_scene_spec(session, key, allowed=allowed)
    if spec is None:
        return None

    # ── 去重护栏：与上一条**已发射**的身份键相同 → 不重复发射（追问时反复弹同一个
    # 图会干扰阅读；中间换过别的键则照常发射）。──
    if key == last_scene_figure_key(session, conv_id):
        return None
    return spec.model_dump()
