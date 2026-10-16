"""ADR-0072 / 票 03(a)：推荐操作目录（build_actions）单测。

目录是服务端静态装配（零延迟、可控、可单测），不靠 LLM。覆盖：
- 空态目录（situation="empty"）：角色分叉的导航标签与 prompt / navigate 分野；与旧
  ``build_suggested_actions`` 输出逐条等价（回归锁定）。
- 知识点目录（带 id 且归属通过）：叠加知识点动作（含判断题 prompt），且行内插值知识点名。
- 知识点 id 越权 / 查不到：回落全局目录（不抛错、不泄他人知识点）。
- 回复后 chips（situation="followup"）：按 business 选一组，带知识点焦点时叠加。
- SSE 帧形状（EVENT_SUGGESTED_ACTIONS + data.actions 载荷，不落库）。
"""
import uuid

from agent_core.protocol import EVENT_SUGGESTED_ACTIONS, AssistantEvent
from app.db.models.material import KnowledgePoint
from app.features.assistant.service import build_actions


def _make_kp(db, *, teacher_id, name="轴对称", subject="数学", grade=4, semester="下学期"):
    kp = KnowledgePoint(
        teacher_id=teacher_id,
        subject=subject,
        grade=grade,
        semester=semester,
        name=name,
    )
    db.add(kp)
    db.commit()
    db.refresh(kp)
    return kp


def _labels(actions):
    return [a.label for a in actions]


def _by_label(actions):
    return {a.label: a for a in actions}


def test_global_actions_role_fork(db):
    """无知识点 id：全局 4 项；学生/教师导航标签分叉，但都走 teacher_task_list。"""
    tid = uuid.uuid4()

    student = build_actions(
        situation="empty", knowledge_point_id=None, role="student",
        teacher_id=tid, session=db,
    )
    s_labels = _labels(student)
    assert s_labels[:2] == ["我要问个问题", "出几道题练练"]
    assert "查看我的错题" in s_labels
    assert len(student) == 4

    teacher = build_actions(
        situation="empty", knowledge_point_id=None, role="teacher",
        teacher_id=tid, session=db,
    )
    t_labels = _labels(teacher)
    assert "看看孩子错题" in t_labels
    assert len(teacher) == 4

    # 两条线都只有 1 个 navigate 动作，payload 是既有 ShellDestination 枚举。
    nav = [a for a in student if a.kind == "navigate"]
    assert len(nav) == 1 and nav[0].payload == "teacher_task_list"
    assert all(a.payload for a in student)


def test_kp_actions_prepend_when_owned(db):
    """带知识点 id 且归属通过：前 3 项是知识点动作（含判断题 prompt），后接全局能力。"""
    tid = uuid.uuid4()
    kp = _make_kp(db, teacher_id=tid, name="轴对称")

    actions = build_actions(
        situation="empty", knowledge_point_id=kp.id, role="teacher",
        teacher_id=tid, session=db,
    )
    labels = _labels(actions)
    # 知识点动作在前（顺序固定），全局能力在后。
    assert labels[:3] == ["举几个生活例子", "出一道判断题", "讲解这个知识点"]
    assert "我要问个问题" in labels
    assert len(actions) == 7

    by_label = _by_label(actions)
    quiz_action = by_label["出一道判断题"]
    # 判断题走自然语言入口（ADR-0089）：prompt 文本自含「判断题」，由出题子代理自主判定。
    assert quiz_action.kind == "prompt" and "判断题" in quiz_action.payload
    # 知识点动作 prompt 内插值了知识点名。
    assert "轴对称" in quiz_action.payload
    assert "轴对称" in by_label["举几个生活例子"].payload
    assert "轴对称" in by_label["讲解这个知识点"].payload


def test_kp_id_unauthorized_falls_back(db):
    """知识点 id 归别人所有：require_owned 抛错被吞，回落全局目录（不出现知识点动作）。"""
    owner = uuid.uuid4()
    other = uuid.uuid4()
    kp = _make_kp(db, teacher_id=owner, name="轴对称")

    actions = build_actions(
        situation="empty", knowledge_point_id=kp.id, role="teacher",
        teacher_id=other, session=db,
    )
    assert _labels(actions) == [
        "我要问个问题",
        "出几道题练练",
        "看看孩子错题",
        "查学习进度",
    ]


def test_kp_id_not_found_falls_back(db):
    """知识点 id 根本不存在：同样回落全局目录，不抛错。"""
    tid = uuid.uuid4()
    actions = build_actions(
        situation="empty", knowledge_point_id=uuid.uuid4(), role="teacher",
        teacher_id=tid, session=db,
    )
    assert len(actions) == 4


def test_followup_chips_by_business(db):
    """follow-up：按 business 选一组；带知识点焦点（归属通过）时叠加知识点向 chips。"""
    tid = uuid.uuid4()
    kp = _make_kp(db, teacher_id=tid, name="轴对称")

    tutor = build_actions(
        situation="followup", business="tutor", knowledge_point_id=None,
        role="teacher", teacher_id=tid, session=db,
    )
    assert _labels(tutor) == ["再举一个例子", "出一道类似的题", "换个角度讲"]

    # 带知识点：tutor 3 项 + 知识点向 2 项（深入 / 出判断题）。
    tutor_kp = build_actions(
        situation="followup", business="tutor", knowledge_point_id=kp.id,
        role="teacher", teacher_id=tid, session=db,
    )
    labels = _labels(tutor_kp)
    assert labels[:3] == ["再举一个例子", "出一道类似的题", "换个角度讲"]
    assert labels[3:] == ["深入这个知识点", "出一道判断题"]
    # 知识点向 chips 为固定目录（单一事实源），payload 不内插知识点名（语境已由
    # 会话的「知识点聚焦」徽标承载）；判定仍走自然语言入口（ADR-0089）。
    assert _by_label(tutor_kp)["出一道判断题"].kind == "prompt"

    # 其它 business 各取各组；无 business → 空（不渲染）。
    tasks = build_actions(
        situation="followup", business="tasks", knowledge_point_id=None,
        role="teacher", teacher_id=tid, session=db,
    )
    assert _labels(tasks) == [
        "看看相关错题", "整理成可导出要点", "换个范围再查",
        "查看学习进度", "回到首页",
    ]
    assert build_actions(
        situation="followup", business=None, knowledge_point_id=None,
        role="teacher", teacher_id=tid, session=db,
    ) == []


def test_followup_kp_unauthorized_no_overlap(db):
    """follow-up 带他人知识点 id：越权不叠加知识点向 chips（不泄他人知识点）。"""
    owner = uuid.uuid4()
    other = uuid.uuid4()
    kp = _make_kp(db, teacher_id=owner, name="轴对称")

    actions = build_actions(
        situation="followup", business="tutor", knowledge_point_id=kp.id,
        role="teacher", teacher_id=other, session=db,
    )
    assert _labels(actions) == ["再举一个例子", "出一道类似的题", "换个角度讲"]


def test_suggested_actions_frame_shape():
    """SSE 新帧：eventType=SUGGESTED_ACTIONS，data.actions 为 SuggestedAction 列表（非 LLM）。"""
    from app.features.assistant.schemas import SuggestedAction

    actions = [
        SuggestedAction(label="我要问个问题", kind="prompt", payload="q"),
        SuggestedAction(label="看看孩子错题", kind="navigate", payload="teacher_task_list"),
    ]
    frame = AssistantEvent(
        eventType=EVENT_SUGGESTED_ACTIONS,
        data={"actions": [a.model_dump(mode="json") for a in actions]},
    )
    d = frame.to_dict()
    assert d["eventType"] == EVENT_SUGGESTED_ACTIONS
    assert d["data"]["actions"] == [
        {"label": "我要问个问题", "kind": "prompt", "payload": "q"},
        {"label": "看看孩子错题", "kind": "navigate", "payload": "teacher_task_list"},
    ]
