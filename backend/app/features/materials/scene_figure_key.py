"""场景图形身份键的读取（中性归宿，票据 10 / LCC-10）。

``last_scene_figure_key`` 原先躺在 ``features.assistant.repository``，被 tutor 的
``scene_intent`` 子代理直连 import——这是越权的跨特性数据依赖（子代理伸手进另一个
feature 的 repository）。现下沉到本中性模块，作为 assistant 与 tutor/scene_intent 共用的
端口；两者都向本模块取数，**互不反向依赖**（无新回边）。

本模块还需要「会话可见轮次」口径（``_visible_rows`` + ``_cards_of``）来扫描已发射的
``interactive_scene`` 卡片。该口径同时是 prompt 历史 / 用户面回放的唯一事实源
（见 ``features/assistant/repository`` 的注释），故一并提供在此中性模块，
``assistant.repository`` 反向 import 本模块取用——避免同口径出现第二份。
"""
from __future__ import annotations

from typing import Any
from uuid import UUID

from sqlmodel import Session, select

from app.db.models import Message


def _visible_rows(session: Session, conv_id: UUID) -> list[Message]:
    """会话内的**可见轮次**（user 输入 + assistant 输出），按 ``turn`` 升序。

    「可见」是领域判定而非 SQL 细节：``system/routing`` 与 ``tool/*`` 是运行轨迹，
    不属于对话内容。prompt 历史、用户面回放、场景去重共用本查询——同一口径写两遍，
    迟早会出现「喂给模型的上下文」与「回放给用户的气泡」不一致。
    """
    return list(
        session.exec(
            select(Message)
            .where(
                Message.conversation_id == conv_id,
                Message.role.in_(["user", "assistant"]),
                Message.step.in_(["input", "output"]),
            )
            .order_by(Message.turn.asc())
        ).all()
    )


def _cards_of(m: Message) -> list[dict]:
    """assistant 输出行的 DATA 卡片；畸形载荷按「无卡片」处理，不抛错。"""
    if m.role != "assistant" or not isinstance(m.payload, dict):
        return []
    cards = m.payload.get("cards")
    if not isinstance(cards, list):
        return []
    return [c for c in cards if isinstance(c, dict)]


def last_scene_figure_key(session: Session, conv_id: Any) -> str | None:
    """本会话**最近一次**已发射的交互场景图形身份键（ADR-0089 §4 去重护栏）。

    读取口径与 prompt 历史 / 用户面回放**共用**同一套「可见轮次」判定
    （``_visible_rows`` + ``_cards_of``）：场景卡整帧落库在 assistant 输出行的
    ``payload["cards"]``（``{type, result}``），按 ``turn`` 倒序找第一条
    ``type == "interactive_scene"`` 的卡片，取其中 ``result.figure.key``。

    返回 ``None`` 的三种情形一视同仁：会话 id 畸形 / 本会话从未发射过场景卡 /
    最近一条场景卡没有身份键——调用方据此**照常发射**（去重只在「键相同」时生效）。
    """
    if session is None or conv_id is None:
        return None
    try:
        cid = conv_id if isinstance(conv_id, UUID) else UUID(str(conv_id))
    except (ValueError, TypeError, AttributeError):
        return None
    for m in reversed(_visible_rows(session, cid)):
        for card in _cards_of(m):
            if card.get("type") != "interactive_scene":
                continue
            result = card.get("result")
            figure = result.get("figure") if isinstance(result, dict) else None
            key = figure.get("key") if isinstance(figure, dict) else None
            return key if isinstance(key, str) and key else None
    return None


__all__ = ["last_scene_figure_key", "_visible_rows", "_cards_of"]
