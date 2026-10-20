"""T01 验收守卫：删除 question/students 空壳 + 陈旧出题 subagent 命名。

纯删除票（候选 5）。本测试锁住验收：业务键已是 ``tasks``，全仓不得再出现
过时的出题 subagent 陈旧命名；同名 subagent 壳目录不得存在。

注意：本文件刻意不以连续字面量写出被禁字符串，否则守卫测试会把自身判为命中。
"""

from __future__ import annotations

from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
APP_DIR = BACKEND_ROOT / "app"
TESTS_DIR = BACKEND_ROOT / "tests"
SUBAGENTS_DIR = APP_DIR / "ai" / "subagents"

# 以拼接方式构造被禁字符串，避免本文件源码中出现其连续字面量
STALE_PATTERN = "question" + " subagent"


def _iter_py_sources(root: Path):
    for path in root.rglob("*.py"):
        # 跳过字节码 / 缓存目录，只扫源码
        if "__pycache__" in path.parts:
            continue
        yield path


def test_no_stale_question_subagent_string():
    """全仓源码不得再出现过时的出题 subagent 陈旧命名。"""
    hits: list[str] = []
    for root in (APP_DIR, TESTS_DIR):
        for path in _iter_py_sources(root):
            text = path.read_text(encoding="utf-8")
            if STALE_PATTERN in text:
                hits.append(f"{path.relative_to(BACKEND_ROOT)}")
    assert not hits, f"仍存在陈旧出题 subagent 字符串：{hits}"


def test_dead_subagent_shells_removed():
    """question/students subagent 空壳目录不得残留。"""
    assert not (SUBAGENTS_DIR / "question").exists(), "question 壳目录未删除"
    assert not (SUBAGENTS_DIR / "students").exists(), "students 壳目录未删除"
