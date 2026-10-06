"""学科收敛 + 题型白名单校验（ADR-0055 §11/§12）。"""

import pytest
from pydantic import ValidationError

from app.domain.subjects import (
    SUBJECTS,
    default_qtype,
    qtypes_for,
)
from app.features.tasks.schemas import TaskSpec


def test_subjects_converged_to_three():
    assert SUBJECTS == ("数学", "语文", "英语")


def test_default_qtypes():
    assert default_qtype("数学") == "calc"
    assert default_qtype("语文") == "fill"
    assert default_qtype("英语") == "choice"


def test_english_rejects_calc():
    assert "calc" not in qtypes_for("英语")
    assert "calc" not in qtypes_for("语文")
    assert "calc" in qtypes_for("数学")


def test_spec_rejects_unknown_subject():
    with pytest.raises(ValidationError, match="暂不支持学科"):
        TaskSpec(subject="科学", grade=3, knowledge_point="浮力", qtype="choice")


def test_spec_rejects_qtype_outside_whitelist():
    with pytest.raises(ValidationError, match="不支持题型"):
        TaskSpec(subject="英语", grade=3, knowledge_point="时态", qtype="calc")


def test_spec_accepts_valid_combo():
    spec = TaskSpec(subject="英语", grade=3, knowledge_point="时态", qtype="choice")
    assert spec.qtype == "choice"
