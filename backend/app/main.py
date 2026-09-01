import json
import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request

# ── 修复 genkit_fastapi ↔ genkit Dart 客户端「错误帧格式不一致」──
# genkit_fastapi.handle_genkit_request 在流式异常时发出 `data: {"error": {...}}`，
# 但 package:genkit/client.dart 仅识别 `error: {...}` 前缀的错误帧；`data:` 帧若
# 既无 result 也无 message 键会被静默丢弃，导致流结束时报
# "stream finished without a final result chunk"，真实错误被掩盖。
# 这里把错误帧前缀改为 `error: `，使 Dart 端能解析并抛出真实错误文案。
from genkit import GenkitError as _GenkitError
from genkit_fastapi import handler as _gf_handler
from starlette.middleware.cors import CORSMiddleware

from app.api.main import api_router
from app.core.config import settings
from app.core.db import init_db
from app.core.errors import register_error_handlers


def _patched_format_stream_error(error: Exception) -> str:
    ex = error.cause if isinstance(error, _GenkitError) else error
    payload = (
        _gf_handler.get_callable_json(ex)
        if hasattr(_gf_handler, "get_callable_json")
        else {"message": str(ex)}
    )
    return f"error: {json.dumps({'error': payload}, separators=_gf_handler.JSON_SEPARATORS)}\n\n"


_gf_handler.format_stream_error = _patched_format_stream_error



@asynccontextmanager
async def lifespan(app: FastAPI):
    # 家自用：启动时建表即可，无需 Alembic 迁移流程
    init_db()
    yield


app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 统一错误体（AppErrorException / HTTPException / ValidationError / 兜底 500）
register_error_handlers(app)

app.include_router(api_router, prefix=settings.API_V1_STR)

# ── 请求访问日志 ─────────────────────────────────────────────
# 用途：排查「前端报 -1 但服务端无日志」类问题。
#   · 有日志行 → 请求已到达，问题在路由/业务层（看状态码）。
#   · 完全没有某次请求的日志行 → 请求在连接层就被拒（后端未启动/
#     端口不对/跨设备用了 127.0.0.1），此时前端会显示具体连接错误。
# 自带 handler，不依赖 uvicorn/root 日志配置，保证任何启动方式都打印。
_request_logger = logging.getLogger("openedu.request")
if not _request_logger.handlers:
    _req_handler = logging.StreamHandler()
    _req_handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s")
    )
    _request_logger.addHandler(_req_handler)
_request_logger.setLevel(logging.INFO)
_request_logger.propagate = False


@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    elapsed_ms = (time.perf_counter() - start) * 1000
    _request_logger.info(
        "%s %s -> %d (%.1fms)",
        request.method,
        request.url.path,
        response.status_code,
        elapsed_ms,
    )
    return response
