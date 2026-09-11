"""async_bridge.run_async 的 loop-safe 策略单测。

候选 5 把三处裸 ``asyncio.run``（grader / tutor / tasks 出题）收口到此处。本测试守护
「无 loop 走 asyncio.run / 有 loop 走线程 offload 不崩」这一唯一策略——否则它只
存在于注释里，下一次有人图省事直接 ``asyncio.run`` 又会埋回 RuntimeError 雷。
"""
from __future__ import annotations

import asyncio

from app.core.async_bridge import run_async


async def _echo(x: int) -> int:
    await asyncio.sleep(0)
    return x


def test_run_async_in_sync_context_returns_value():
    assert run_async(_echo(42)) == 42


def test_run_async_in_sync_context_propagates_exception():
    async def _boom() -> int:
        raise ValueError("kaboom")

    try:
        run_async(_boom())
    except ValueError as e:
        assert "kaboom" in str(e)
    else:
        raise AssertionError("异常未向上传播")


def test_run_async_from_within_running_loop_offloads_to_thread():
    # 模拟「异步路由直调同步壳」：已处于事件循环中，run_async 必须不抛 RuntimeError。
    async def _caller() -> int:
        return run_async(_echo(7))

    assert asyncio.run(_caller()) == 7
