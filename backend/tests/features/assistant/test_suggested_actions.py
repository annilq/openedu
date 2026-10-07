"""ADR-0072：推荐操作目录（build_suggested_actions）单测。

目录是服务端静态装配（零延迟、可控、可单测），不靠 LLM。覆盖：
- 全局目录（无知识点 id）：角色分叉的导航标签与 prompt / navigate 分野。
- 知识点目录（带 id 且归属通过）：叠加知识点动作（含 quiz 判断题），且行内插值知识点名。
- 知识点 id 越权 / 查不到：回落全局目录（不抛错、不泄他人知识点）。
"""
import uuid

from app.db.models.material import KnowledgePoint
from app.features.assistant.service import build_suggested_actions


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

    student = build_suggested_actions(
        knowledge_point_id=None, role="student", teacher_id=tid, session=db
    )
    s_labels = _labels(student)
    assert s_labels[:2] == ["我要问个问题", "出几道题练练"]
    assert "查看我的错题" in s_labels
    assert len(student) == 4

    teacher = build_suggested_actions(
        knowledge_point_id=None, role="teacher", teacher_id=tid, session=db
    )
    t_labels = _labels(teacher)
    assert "看看孩子错题" in t_labels
    assert len(teacher) == 4

    # 两条线都只有 1 个 navigate 动作，payload 是既有 ShellDestination 枚举。
    nav = [a for a in student if a.kind == "navigate"]
    assert len(nav) == 1 and nav[0].payload == "teacher_task_list"
    assert all(a.quiz is False for a in student)


def test_kp_actions_prepend_when_owned(db):
    """带知识点 id 且归属通过：前 3 项是知识点动作（含 quiz 判断题），后接全局能力。"""
    tid = uuid.uuid4()
    kp = _make_kp(db, teacher_id=tid, name="轴对称")

    actions = build_suggested_actions(
        knowledge_point_id=kp.id, role="teacher", teacher_id=tid, session=db
    )
    labels = _labels(actions)
    # 知识点动作在前（顺序固定），全局能力在后。
    assert labels[:3] == ["举几个生活例子", "出一道判断题", "讲解这个知识点"]
    assert "我要问个问题" in labels
    assert len(actions) == 7

    by_label = _by_label(actions)
    quiz_action = by_label["出一道判断题"]
    assert quiz_action.kind == "prompt" and quiz_action.quiz is True
    # 知识点动作 prompt 内插值了知识点名。
    assert "轴对称" in quiz_action.payload
    assert "轴对称" in by_label["举几个生活例子"].payload
    assert "轴对称" in by_label["讲解这个知识点"].payload


def test_kp_id_unauthorized_falls_back(db):
    """知识点 id 归别人所有：require_owned 抛错被吞，回落全局目录（不出现知识点动作）。"""
    owner = uuid.uuid4()
    other = uuid.uuid4()
    kp = _make_kp(db, teacher_id=owner, name="轴对称")

    actions = build_suggested_actions(
        knowledge_point_id=kp.id, role="teacher", teacher_id=other, session=db
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
    actions = build_suggested_actions(
        knowledge_point_id=uuid.uuid4(), role="teacher", teacher_id=tid, session=db
    )
    assert len(actions) == 4
