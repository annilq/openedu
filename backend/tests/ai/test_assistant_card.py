"""助手卡协议：`interactive_scene` 接入（ADR-0061 决策 7）。

验证后端 `render.py` 侧的卡片构建器与种类常量：
- `INTERACTIVE_SCENE_KIND` 与前端 `AssistantCardKind.interactiveScene` 双登记（逐字一致）；
- `render_scene_card` 把 SceneSpec 原样包成 `interactive_scene` 卡；
- 畸形 spec（非 dict / 缺失）不崩、不丢帧，交给前端降级卡兜住。
"""

from __future__ import annotations

from app.ai.subagents.query.render import (
    INTERACTIVE_SCENE_KIND,
    Card,
    render_scene_card,
)


def test_kind_constant_matches_frontend_contract() -> None:
    # 与 frontend/lib/features/assistant/domain/assistant_card.dart 的
    # AssistantCardKind.interactiveScene 逐字对齐（ADR-0042 §Consequences 双登记口径）。
    assert INTERACTIVE_SCENE_KIND == "interactive_scene"


def test_render_scene_card_wraps_spec() -> None:
    spec = {
        "kind": "reflection",
        "title": "图形的运动（轴对称）",
        "inputs": [{"key": "axisAngle", "value": 90}],
    }

    card = render_scene_card(spec)

    assert isinstance(card, Card)
    assert card.kind == INTERACTIVE_SCENE_KIND
    # payload 是 spec 的拷贝（原样下发，前端按内层 kind 分派渲染器）。
    assert card.payload == spec
    assert card.payload["kind"] == "reflection"


def test_render_scene_card_isolated_from_mutation() -> None:
    spec = {"kind": "reflection", "title": "轴对称"}
    card = render_scene_card(spec)
    # 修改原 spec 不应影响已产出的卡（防御性拷贝）。
    spec["title"] = "篡改"
    assert card.payload["title"] == "轴对称"


def test_render_scene_card_handles_malformed_spec() -> None:
    # 非 dict / 缺字段都不崩；空 payload 交给前端降级卡兜住，不产 None。
    for bad in (None, "", 123, []):
        card = render_scene_card(bad)
        assert isinstance(card, Card)
        assert card.kind == INTERACTIVE_SCENE_KIND
        assert card.payload == {}
