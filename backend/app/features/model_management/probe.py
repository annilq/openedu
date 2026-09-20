"""「测试连接」探针：用一次极短调用验证这组模型参数**真的能出内容**。

为什么必须有后端端点、而不能由前端直接去 ping 厂商：

1. **密钥不出门**：api_key 的密文只存在后端（ADR-0038 的硬约束）。编辑表单里
   「密钥留空 = 不修改」，前端手里根本没有可测的东西，必须回后端取库里那份。
2. **判据必须与生产同源**：探针经 ``app.ai.engine.build_engine`` 构造引擎，与真实
   出题走**同一条链路**（同一份 ollama 默认地址、同一份引擎缓存）。若另起一条
   HTTP 直连，就会出现「测试通过但出题失败」的假绿灯——那比没有测试更糟。
3. **失败归因可复用**：异常一律经 ``classify_failure``（ADR-0038）归类，家长看到
   的是「密钥无效 / 地址不可达 / 模型名不存在」，而不是一个笼统的「连接失败」。

探针本身是**一次极小开销的流式生成**（不是只读 /models 清单）：读取清单只能证明
「接口通」，而家长真正要问的是「能不能用它出题」——认证、模型名、配额三件事
只有真发一次请求才验得出来。
"""
from __future__ import annotations

import asyncio
import logging
import time

from agent_core.adapters.genkit import classify_failure
from agent_core.errors import ProviderRequestError
from app.ai.engine import build_engine
from app.core.config import settings
from app.features.model_management.schemas import ModelProbeResp

logger = logging.getLogger(__name__)

# 提示语刻意极短：探针只关心「有没有内容回来」，不关心内容质量。
_PROBE_SYSTEM = "你正在接受一次连接测试。只回复一个字：好。"
_PROBE_PROMPT = "ping"

# 厂商原始报文可能很长（整段 JSON），也可能夹带被拒密钥的尾号 → 截断后再回显。
_DETAIL_MAX = 300

# 「超时」是探针自己的结论，不属于厂商归因枚举，单独给一个 kind。
_TIMEOUT_KIND = "timeout"


def _redact(text: str, secret: str | None) -> str:
    """把文本里出现的密钥明文抹掉。

    厂商报错有时会把请求串（含 key）回显出来；本端点的调用者正是密钥持有者本人，
    但报错要进前端日志与用户可见界面，回显一次就够多了——绝不再复制第二份。
    """
    if secret and len(secret) >= 4 and secret in text:
        text = text.replace(secret, "***")
    return text[:_DETAIL_MAX]


def _elapsed_ms(started: float) -> int:
    return int((time.perf_counter() - started) * 1000)


async def _call_once(genkit: object, model: str) -> None:
    """发一次流式生成，**收到第一帧就收工**。

    连通性只问「有没有内容回来」，不需要等模型把话说完。实测本地
    ``qwen3:1.7b``（带 thinking）：一句「ping」要 6.4 秒才把思维链 + 回答吐完，
    而首个 chunk 不到 1 秒——读完整个流等于把一次握手做成一次完整生成，
    思维链越长的模型越慢，20 秒超时会被白白吃掉，报出「连接超时」这种假阴性。

    ⚠️ 收工不是「撒手不管」，两步都不能省：
    1. genkit 把真正的生成派发成了后台 task，直接跳出会留一条悬挂流
       （Python 警告「Task was destroyed but it is pending」）→ 显式 cancel；
    2. 但**不能无条件吞掉这个 future**：认证失败（401）时流里一帧都没有，
       channel 会静默 ``StopAsyncIteration``，只有 await 这个 future 才能让异常
       冒出来——省掉它就变成「401 被判成连接成功」。
    """
    sresp = genkit.generate_stream(
        model=model, system=_PROBE_SYSTEM, prompt=_PROBE_PROMPT
    )
    future = sresp.response  # 后台生成任务的 Future（ModelStreamResponse.response）
    async for _chunk in sresp.stream:
        break

    done = getattr(future, "done", None)
    if callable(done) and not done():
        # 还在生成：说明已经连上了，后面的内容我们不想要。
        cancel = getattr(future, "cancel", None)
        if callable(cancel):
            cancel()
        try:
            await future
        except asyncio.CancelledError:
            return
        return
    # 已结束：无论是正常收尾还是「开流前就失败」，都在此揭晓（失败会抛出）。
    await future


async def probe_model(
    *,
    provider: str,
    base_url: str | None,
    model_name: str,
    api_key: str | None,
    timeout_s: float | None = None,
) -> ModelProbeResp:
    """用一次极短调用验证参数可用性；**不抛异常**，一律以 ``ModelProbeResp`` 返回。"""
    timeout = timeout_s if timeout_s is not None else settings.MODEL_PROBE_TIMEOUT_S
    started = time.perf_counter()

    try:
        engine = build_engine(
            provider=provider, base_url=base_url, api_key=api_key, model_name=model_name
        )
    except Exception as exc:  # noqa: BLE001 — 构造失败也要变成结论，不能冒成 500
        logger.warning("模型探针：引擎构造失败 provider=%s model=%s", provider, model_name)
        return ModelProbeResp(
            ok=False,
            latency_ms=_elapsed_ms(started),
            message="连接失败：模型参数无法构造引擎，请检查服务商与接口地址。",
            error_kind="unknown",
            detail=_redact(f"{exc.__class__.__name__}: {exc}", api_key),
        )

    try:
        await asyncio.wait_for(_call_once(engine.genkit, engine.model), timeout=timeout)
    except asyncio.TimeoutError:
        # 超时的**下一步**取决于 provider：本地 Ollama 首次调用要先加载权重
        # （几个 G 的模型可达数十秒），报「检查地址」会把家长往错的方向推；
        # 而云端服务 20 秒没反应，基本就是地址或网络的问题。
        if provider == "ollama":
            message = (
                f"连接超时：{timeout:.0f} 秒内没有响应。本地模型首次调用要先加载权重"
                "（大模型可达数十秒），且模型名必须已用 ollama pull 拉过——"
                "请确认后重试（第二次通常就很快）。"
            )
        else:
            message = f"连接超时：{timeout:.0f} 秒内没有响应，请检查网络或接口地址。"
        return ModelProbeResp(
            ok=False,
            latency_ms=_elapsed_ms(started),
            message=message,
            error_kind=_TIMEOUT_KIND,
            detail=None,
        )
    except ProviderRequestError as exc:
        # 适配器已按 ADR-0038 归类：auth / rate_limit / network / bad_request / unknown
        return ModelProbeResp(
            ok=False,
            latency_ms=_elapsed_ms(started),
            message=exc.user_hint,
            error_kind=exc.kind,
            detail=_redact(exc.reason, api_key),
        )
    except Exception as exc:  # noqa: BLE001 — 归类后回显，绝不把 401 说成「未知错误」
        failure = classify_failure(exc)
        kind = getattr(failure, "kind", None) or "unknown"
        hint = getattr(failure, "user_hint", None) or f"连接失败：{exc}"
        logger.warning("模型探针：调用失败 provider=%s kind=%s", provider, kind)
        return ModelProbeResp(
            ok=False,
            latency_ms=_elapsed_ms(started),
            message=hint,
            error_kind=kind,
            detail=_redact(f"{exc.__class__.__name__}: {exc}", api_key),
        )

    latency = _elapsed_ms(started)
    return ModelProbeResp(
        ok=True,
        latency_ms=latency,
        # 口径是「首个响应」而非「完整答复」：探针在收到第一帧时就收工了
        # （见 _call_once），把这个数字说成整轮耗时会让家长误判模型速度。
        message=f"连接成功：{model_name} 可用（{latency} ms 收到首个响应）。",
        error_kind=None,
        detail=None,
    )
