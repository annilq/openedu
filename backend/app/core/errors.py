"""统一错误码 + 应用异常 + JSON 响应封装。

口径（E-Q1~Q4=a）：
- 系统级 10xxx，业务级按领域分段：20xxx Tasks / 30xxx Auth / 40xxx Review /
  50xxx WrongQuestions / 60xxx Tutor / 70xxx Children。
- HTTP 状态码保持语义（401=401、403=403、404=404、422=422、500=500）。
- 错误体：`{"code": str, "message": str, "status": int, "data": null|dict}`。
  code 用字符串（枚举名 + 数字），便于全局搜；成功体不包层，保持原样。
"""

from __future__ import annotations

from enum import Enum
from typing import Any

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel

# ───────────────────────── 错误码枚举 ─────────────────────────


class ErrCode(str, Enum):
    """<前缀>_<数字>。数字保留 5 位：系统 1xxxx，任务 2xxxx，鉴权 3xxxx ……"""

    # 系统级 10xxx
    UNAUTHORIZED = "SYS_10001"
    FORBIDDEN = "SYS_10002"
    NOT_FOUND = "SYS_10003"
    VALIDATION = "SYS_10004"
    INTERNAL = "SYS_10005"

    # Tasks 领域 20xxx
    TASK_NOT_FOUND = "TASK_20001"
    TASK_NOT_OWNED = "TASK_20002"
    TASK_NOT_YOUR_CHILD = "TASK_20003"
    TASK_STATUS_DRAFT_REQUIRED = "TASK_20004"  # 草稿态动作（编辑/重生成）
    TASK_STATUS_READY_REQUIRED = "TASK_20005"  # ready 态动作（派发）
    TASK_STATUS_ASSIGNED_REQUIRED = "TASK_20006"  # assigned 态动作（打卡）
    TASK_NOT_ASSIGNED = "TASK_20007"  # child_id 为空就想作答/打卡
    TASK_QUESTION_NOT_FOUND = "TASK_20008"
    TASK_LOCK_REQUIRES_ALL_PROMOTED = "TASK_20009"  # draft→ready 前每题必须入题库
    TASK_QUESTION_ALREADY_PROMOTED = "TASK_20010"
    TASK_EMPTY_SPECS = "TASK_20011"
    TASK_CHILD_NOT_OWNED = "TASK_20012"  # batch-generate/assign 指定的 child 非本家长所有
    TASK_NO_QUESTIONS = "TASK_20013"  # 锁定/派发前草稿没有题
    QUESTION_NOT_FOUND = "TASK_20014"  # 题库题不存在（from-bank 全部越权/缺失）
    QUESTION_ACCESS_DENIED = "TASK_20015"  # 部分题库题无权限（owner 隔离）
    QUESTION_IN_USE = "TASK_20016"  # 题库题已被任务引用，禁止删除

    # Auth 30xxx
    AUTH_INVALID_TOKEN = "AUTH_30001"
    AUTH_INACTIVE_USER = "AUTH_30002"
    AUTH_BAD_CREDENTIALS = "AUTH_30003"
    AUTH_PARENT_ONLY = "AUTH_30004"
    AUTH_CHILD_ONLY = "AUTH_30005"
    AUTH_USERNAME_TAKEN = "AUTH_30006"

    # Tutor 60xxx
    TUTOR_QUOTA_EXCEEDED = "TUTOR_60001"


_HTTP_DEFAULT_STATUS: dict[ErrCode, int] = {
    ErrCode.UNAUTHORIZED: status.HTTP_401_UNAUTHORIZED,
    ErrCode.FORBIDDEN: status.HTTP_403_FORBIDDEN,
    ErrCode.NOT_FOUND: status.HTTP_404_NOT_FOUND,
    ErrCode.VALIDATION: status.HTTP_422_UNPROCESSABLE_CONTENT,
    ErrCode.INTERNAL: status.HTTP_500_INTERNAL_SERVER_ERROR,
    ErrCode.TASK_NOT_FOUND: status.HTTP_404_NOT_FOUND,
    ErrCode.TASK_NOT_OWNED: status.HTTP_403_FORBIDDEN,
    ErrCode.TASK_NOT_YOUR_CHILD: status.HTTP_403_FORBIDDEN,
    ErrCode.TASK_STATUS_DRAFT_REQUIRED: status.HTTP_409_CONFLICT,
    ErrCode.TASK_STATUS_READY_REQUIRED: status.HTTP_409_CONFLICT,
    ErrCode.TASK_STATUS_ASSIGNED_REQUIRED: status.HTTP_409_CONFLICT,
    ErrCode.TASK_NOT_ASSIGNED: status.HTTP_409_CONFLICT,
    ErrCode.TASK_QUESTION_NOT_FOUND: status.HTTP_404_NOT_FOUND,
    ErrCode.TASK_LOCK_REQUIRES_ALL_PROMOTED: status.HTTP_409_CONFLICT,
    ErrCode.TASK_QUESTION_ALREADY_PROMOTED: status.HTTP_409_CONFLICT,
    ErrCode.TASK_EMPTY_SPECS: status.HTTP_422_UNPROCESSABLE_CONTENT,
    ErrCode.TASK_CHILD_NOT_OWNED: status.HTTP_403_FORBIDDEN,
    ErrCode.TASK_NO_QUESTIONS: status.HTTP_409_CONFLICT,
    ErrCode.QUESTION_NOT_FOUND: status.HTTP_404_NOT_FOUND,
    ErrCode.QUESTION_ACCESS_DENIED: status.HTTP_403_FORBIDDEN,
    ErrCode.QUESTION_IN_USE: status.HTTP_409_CONFLICT,
    ErrCode.AUTH_INVALID_TOKEN: status.HTTP_403_FORBIDDEN,
    ErrCode.AUTH_INACTIVE_USER: status.HTTP_400_BAD_REQUEST,
    ErrCode.AUTH_BAD_CREDENTIALS: status.HTTP_401_UNAUTHORIZED,
    ErrCode.AUTH_PARENT_ONLY: status.HTTP_403_FORBIDDEN,
    ErrCode.AUTH_CHILD_ONLY: status.HTTP_403_FORBIDDEN,
    ErrCode.AUTH_USERNAME_TAKEN: status.HTTP_400_BAD_REQUEST,
    ErrCode.TUTOR_QUOTA_EXCEEDED: status.HTTP_402_PAYMENT_REQUIRED,
}


# ───────────────────────── 统一响应体 ─────────────────────────


class ErrorResp(BaseModel):
    code: str
    message: str
    status: int
    data: Any | None = None


def default_status(code: ErrCode) -> int:
    return _HTTP_DEFAULT_STATUS.get(code, status.HTTP_500_INTERNAL_SERVER_ERROR)


# ───────────────────────── 应用异常类（路由层直接抛） ─────────────────────────


class AppErrorException(Exception):
    """业务层统一异常，被 FastAPI 全局异常处理器转为 JSON。"""

    def __init__(
        self,
        code: ErrCode,
        message: str | None = None,
        *,
        status_code: int | None = None,
        data: Any | None = None,
    ) -> None:
        self.code = code
        self.message = message or code.name.replace("_", " ")
        self.status_code = status_code or default_status(code)
        self.data = data
        super().__init__(self.message)


# ───────────────────────── FastAPI 全局异常处理器注册 ─────────────────────────


def _body(code: ErrCode | str, message: str, status: int, data: Any = None) -> dict[str, Any]:
    return jsonable_encoder(
        ErrorResp(
            code=code.value if isinstance(code, ErrCode) else code,
            message=message,
            status=status,
            data=data,
        )
    )


def register_error_handlers(app: FastAPI) -> None:
    """在 FastAPI app 上挂 HTTPException / Validation / AppErrorException / 兜底 500。"""

    # 路由层抛 AppErrorException
    @app.exception_handler(AppErrorException)
    async def _app_error_handler(request: Request, exc: AppErrorException) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content=_body(exc.code, exc.message, exc.status_code, exc.data),
        )

    # FastAPI 自带 HTTPException（包括 deps 里那些直接 raise HTTPException 的老代码）
    @app.exception_handler(HTTPException)
    async def _http_handler(request: Request, exc: HTTPException) -> JSONResponse:
        # 把老 HTTPException 的 status_code 映射回一个 ErrCode 字符串，便于前端统一展示
        mapping: dict[int, ErrCode] = {
            status.HTTP_401_UNAUTHORIZED: ErrCode.UNAUTHORIZED,
            status.HTTP_403_FORBIDDEN: ErrCode.FORBIDDEN,
            status.HTTP_404_NOT_FOUND: ErrCode.NOT_FOUND,
            status.HTTP_422_UNPROCESSABLE_CONTENT: ErrCode.VALIDATION,
        }
        code = mapping.get(exc.status_code, ErrCode.INTERNAL)
        detail = exc.detail if isinstance(exc.detail, str) else str(exc.detail)
        return JSONResponse(
            status_code=exc.status_code,
            content=_body(code, detail, exc.status_code),
        )

    # Pydantic 请求体校验失败
    @app.exception_handler(RequestValidationError)
    async def _validation_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        errors = exc.errors()
        lines = []
        for e in errors:
            loc = ".".join(str(x) for x in e.get("loc", [])) or "<body>"
            lines.append(f"{loc}: {e.get('msg', 'invalid')}")
        message = "; ".join(lines) if lines else "请求参数校验失败"
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            content=_body(
                ErrCode.VALIDATION,
                message,
                status.HTTP_422_UNPROCESSABLE_CONTENT,
                {"errors": errors},
            ),
        )

    # 兜底 500（记录未捕获异常但不泄露堆栈给前端）
    @app.exception_handler(Exception)
    async def _uncaught_handler(request: Request, exc: Exception) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content=_body(ErrCode.INTERNAL, "服务器内部错误", status.HTTP_500_INTERNAL_SERVER_ERROR),
        )
