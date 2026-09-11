"""同步代码驱动异步 provider 的唯一桥接点（ADR-00xx：异步边界收口）。

后端多处是「同步壳 → 异步 provider」的边界：``Grader.grade``、``TutorService.explain``、
tasks 出题管线都只在同步路由/同步 service 里被调用，FastAPI 的同步路由跑在线程池
（**无运行中的事件循环**），裸 ``asyncio.run`` 可用。但这段逻辑一旦被异步路由直接
调用，裸 ``asyncio.run`` 立刻抛 ``RuntimeError: asyncio.run() cannot be called from a
running event loop``——而调用方才是真正撞错的地方，难以定位。

把 loop-safe 策略只在此实现一次并单测覆盖，三处调用点退化为 ``run_async(coro)``，
消除「各写一份 asyncio.run、语义靠纪律不靠机制」的漂移源。
"""
from __future__ import annotations

import asyncio
import concurrent.futures


def run_async(coro):
    """在线程池外的同步上下文运行协程；若已处于事件循环内则 offload 到独立线程。

    返回协程的结果，或原样抛出其异常。

    - 无运行中 loop（同步路由/同步 service）：标准 ``asyncio.run`` 路径。
    - 已处于事件循环（异步路由直调同步壳）：在新线程跑独立 loop，避免 RuntimeError；
      异步 provider 的 IO 本就阻塞，offload 到线程不比同步路由更差。
    """
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        return asyncio.run(coro)
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        return ex.submit(lambda: asyncio.run(coro)).result()
