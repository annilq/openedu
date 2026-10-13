"""知识点聚焦解析单元测试（ADR-0080 / ai-prompts-hardening ticket 02）。

纯函数 + 软归属校验，全部确定性、不接真实模型、不建真库：

- ``format_kp_focus``：四元组 → 【知识点聚焦】段；``query_mode`` 追加工具数据约束；
  缺失 / 空 name → 空串（调用方据此不注入，无回归）。
- ``resolve_kp_focus``：经 ``find_owned`` 归属校验取四元组；越权（非己方）/ 缺失 id → ``None``。
"""
from __future__ import annotations

from uuid import UUID

from app.features.assistant.kp_focus import format_kp_focus, resolve_kp_focus


def test_format_kp_focus_renders_segment():
    seg = format_kp_focus(
        {"subject": "数学", "grade": 5, "semester": "上学期", "name": "轴对称"}
    )
    assert "【知识点聚焦】" in seg
    assert "轴对称" in seg
    assert "数学" in seg and "5年级" in seg and "上学期" in seg


def test_format_kp_focus_handles_empty_semester():
    seg = format_kp_focus({"subject": "语文", "grade": 3, "semester": "", "name": "比喻"})
    assert "整学年" in seg


def test_format_kp_focus_query_mode_adds_tool_data_line():
    base = format_kp_focus({"subject": "数学", "grade": 5, "semester": "上学期", "name": "轴对称"})
    query = format_kp_focus(
        {"subject": "数学", "grade": 5, "semester": "上学期", "name": "轴对称"},
        query_mode=True,
    )
    assert "查询仍须依托工具数据" in query
    assert query.startswith(base)


def test_format_kp_focus_empty_when_missing():
    assert format_kp_focus(None) == ""
    assert format_kp_focus({}) == ""
    assert format_kp_focus({"subject": "数学"}) == ""  # 无 name


class _KP:
    def __init__(self, teacher_id: UUID, subject: str, grade: int, semester: str, name: str):
        self.teacher_id = teacher_id
        self.subject = subject
        self.grade = grade
        self.semester = semester
        self.name = name


class _Session:
    def __init__(self, kp: _KP | None):
        self._kp = kp

    def get(self, model, obj_id):
        return self._kp


def test_resolve_kp_focus_returns_tuple_when_owned():
    owner = UUID(int=1)
    kp = _KP(owner, "数学", 5, "上学期", "轴对称")
    result = resolve_kp_focus(session=_Session(kp), owner_id=owner, kp_id=UUID(int=99))
    assert result == {
        "subject": "数学",
        "grade": 5,
        "semester": "上学期",
        "name": "轴对称",
    }


def test_resolve_kp_focus_returns_none_when_not_owned():
    owner = UUID(int=1)
    other = UUID(int=2)
    kp = _KP(other, "数学", 5, "上学期", "轴对称")  # 属于 other，非 owner
    assert resolve_kp_focus(session=_Session(kp), owner_id=owner, kp_id=UUID(int=99)) is None


def test_resolve_kp_focus_returns_none_when_missing_id():
    owner = UUID(int=1)
    assert resolve_kp_focus(session=_Session(None), owner_id=owner, kp_id=None) is None
