"""悬浮助手 repository 单测：load_chat_history 的 compaction 与自动摘要行为。

compaction / 摘要逻辑已抽到纯函数，无需 DB 即可覆盖边界；``load_chat_history_with_summary``
通过轻量 fake session 驱动（只依赖 ``session.exec(...).all()`` 返回带 role/content 的行）。
"""
import asyncio
from uuid import uuid4

from app.features.assistant import repository as repo


def _h(n: int, content_len: int = 10) -> list[dict]:
    return [{"role": "user", "content": "x" * content_len} for _ in range(n)]


# ── 纯函数：compaction（P1） ──────────────────────────────────────────────
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


# ── 纯函数：split / 摘要装配 ─────────────────────────────────────────────
def test_split_compaction_returns_dropped_and_kept():
    history = _h(30)
    dropped, kept = repo._split_compaction(history, limit=20, max_tokens=10_000)
    assert len(dropped) == 10 and len(kept) == 20
    assert dropped[0] is history[0] and kept[0] is history[10]


def test_split_compaction_token_branch():
    history = [{"role": "user", "content": "y" * 4000} for _ in range(20)]
    dropped, kept = repo._split_compaction(history, limit=20, max_tokens=4000)
    assert len(kept) < 20
    assert repo._estimate_tokens(kept) <= 4000
    assert kept[-1] is history[-1]


def test_assemble_summary_prepends_with_prefix():
    kept = _h(3)
    out = repo._assemble_summary(kept, "摘要内容")
    assert len(out) == 4
    assert out[0]["role"] == "user"
    assert out[0]["content"].startswith(repo.SUMMARY_PREFIX)
    assert "摘要内容" in out[0]["content"]
    assert out[1:] == kept


# ── 异步：自动摘要（P2） ─────────────────────────────────────────────────
class _FakeRow:
    def __init__(self, role: str, content: str = "") -> None:
        self.role = role
        self.content = content


class _FakeResult:
    def __init__(self, rows) -> None:
        self._rows = rows

    def all(self):
        return self._rows


class _FakeSession:
    def __init__(self, messages: list[dict]) -> None:
        self._rows = [_FakeRow(m["role"], m["content"]) for m in messages]

    def exec(self, *args, **kwargs):
        return _FakeResult(self._rows)


def _msgs(n: int) -> list[dict]:
    return [{"role": "user", "content": f"m{i}"} for i in range(n)]


def test_summary_injected_when_dropped():
    # 10 条，limit=5 → 丢最旧 5 条，summarizer 返回摘要 → 前置注入
    calls: list[list[dict]] = []

    async def fake(dropped):
        calls.append(dropped)
        return "这是一段摘要"

    result = asyncio.run(
        repo.load_chat_history_with_summary(
            _FakeSession(_msgs(10)), uuid4(), limit=5, summarize=fake
        )
    )
    assert len(calls) == 1
    assert len(calls[0]) == 5  # 被丢的 5 条交给 summarizer
    assert len(result) == 6  # 5 条 kept + 1 摘要
    assert result[0]["content"].startswith(repo.SUMMARY_PREFIX)
    assert "这是一段摘要" in result[0]["content"]


def test_summary_falls_back_when_none():
    async def fake(dropped):
        return None

    result = asyncio.run(
        repo.load_chat_history_with_summary(
            _FakeSession(_msgs(10)), uuid4(), limit=5, summarize=fake
        )
    )
    assert len(result) == 5  # 回退纯丢弃，无摘要
    assert not result[0]["content"].startswith(repo.SUMMARY_PREFIX)


def test_summary_skipped_when_no_drop():
    called: list[bool] = []

    async def fake(dropped):
        called.append(True)
        return "x"

    result = asyncio.run(
        repo.load_chat_history_with_summary(
            _FakeSession(_msgs(3)), uuid4(), limit=20, summarize=fake
        )
    )
    assert called == []  # 短对话不调用 summarizer
    assert len(result) == 3


def test_summary_falls_back_on_exception():
    async def fake(dropped):
        raise RuntimeError("llm down")

    result = asyncio.run(
        repo.load_chat_history_with_summary(
            _FakeSession(_msgs(10)), uuid4(), limit=5, summarize=fake
        )
    )
    assert len(result) == 5  # 异常回退纯丢弃
    assert not result[0]["content"].startswith(repo.SUMMARY_PREFIX)
