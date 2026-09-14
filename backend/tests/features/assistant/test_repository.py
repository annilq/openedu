"""悬浮助手 repository 单测：load_chat_history 的 compaction 行为。

compaction 逻辑已抽到纯函数 ``_compact_history``，无需 DB 即可覆盖边界。
"""
from app.features.assistant import repository as repo


def _h(n: int, content_len: int = 10) -> list[dict]:
    return [{"role": "user", "content": "x" * content_len} for _ in range(n)]


def test_keeps_recent_limit():
    history = _h(30)
    out = repo._compact_history(history, limit=20, max_tokens=10_000)
    assert len(out) == 20
    assert out[0] is history[10]  # 保留最近 20 条，丢弃最旧 10 条


def test_short_history_unchanged():
    history = _h(5)
    assert repo._compact_history(history, limit=20, max_tokens=10_000) == history


def test_token_budget_drops_oldest():
    # 每条 4000 字符 ≈ 1000 token；max_tokens=4000 仅容 ~3 条 → 丢最旧
    history = _h(20, content_len=4000)
    out = repo._compact_history(history, limit=20, max_tokens=4000)
    assert len(out) < 20
    assert repo._estimate_tokens(out) <= 4000
    assert out[-1] is history[-1]  # 保留最新轮次


def test_never_drops_to_empty():
    # 单条就超预算时，至少留 1 条，绝不返回空（保留最新上下文）
    history = _h(5, content_len=100_000)
    out = repo._compact_history(history, limit=20, max_tokens=100)
    assert len(out) == 1
    assert out[-1] is history[-1]
