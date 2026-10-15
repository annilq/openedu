"""票 03(a)：chat 端点每轮回复后随 SSE 下发 SUGGESTED_ACTIONS 帧（不落库）。"""
from tests.api.routes.test_assistant import _setup, _stream


def test_chat_emits_suggested_actions_frame(client):
    """回复后下发 suggested_actions 帧：payload 为 actions 列表（label/kind/payload）。"""
    _ptoken, _student, ctoken = _setup(client, "asfa_teacher", "asfa_kid")
    status, events = _stream(client, ctoken, "23 + 45 怎么算")
    assert status == 200, events

    sa = [e for e in events if e["eventType"] == "SUGGESTED_ACTIONS"]
    assert sa, "回复后必须下发 suggested_actions 帧"
    actions = sa[0]["data"]["actions"]
    assert isinstance(actions, list) and actions, "actions 非空列表"
    assert all(
        "label" in a and "kind" in a and "payload" in a for a in actions
    ), "每条 action 含 label/kind/payload"


def test_suggested_actions_frame_not_persisted(client, db):
    """suggested_actions 仅入口、非对话内容：不写 Message 轨迹（不落库）。"""
    from sqlmodel import select

    from app.db.models import Message

    _ptoken, _student, ctoken = _setup(client, "asfa2_teacher", "asfa2_kid")
    # ADR-0095 预检：出题业务要求 subject/grade/qtype 齐备；给全后走生成路径，
    # 验证「回复后 suggested_actions 下发但不落库」的意图不被预检误伤。
    _status, events = _stream(client, ctoken, "帮我出一道三年级数学选择题")
    assert any(e["eventType"] == "SUGGESTED_ACTIONS" for e in events)

    # 会话轨迹里不应出现 suggested_actions 步（落库只记 routing/工具/输出等）。
    # db 夹具与 app 同库、按测试隔离，故此扫描即覆盖本轮写入。
    steps = db.execute(select(Message.step)).scalars().all()
    assert "suggested_actions" not in steps
