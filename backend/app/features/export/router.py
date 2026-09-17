"""打印导出路由：``POST /export/sheet``，返回 ``application/pdf`` 字节。

端点是**同步 def**——FastAPI 会把同步路由放进线程池跑，CPU 密集的 Typst
编译因此不占事件循环（ADR-0052 决策）。不要为了「顺手」把它改成 async。
"""
from fastapi import APIRouter
from fastapi.responses import Response

from app.core.deps import CallerDep, SessionDep
from app.core.errors import AppErrorException, ErrCode
from app.features.export.schemas import ExportSheetReq
from app.features.export.service import build_sheet_pdf

router = APIRouter(prefix="/export", tags=["export"])


def _child_only_scope(caller, body: ExportSheetReq) -> None:
    """娃娃端只能导出**自己的**错题（复习页的「当前到期」）。

    来源与娃娃标识都由服务端按调用者钉死，不接受请求体指定：否则孩子改一个
    ``child_id`` 就拿到了别人的错题本——授权主体是他自己，资源却不是他的。
    ``ids`` 一并清空，避免「来源被改回 wrong_book、ids 却还留着别人题目 id」
    这种混合态溜进取数层。
    """
    if body.source != "wrong_book":
        raise AppErrorException(ErrCode.EXPORT_CHILD_SCOPE, "娃娃端只能导出错题练习")
    if body.child_id is not None and body.child_id != caller.user.id:
        raise AppErrorException(ErrCode.EXPORT_CHILD_SCOPE, "娃娃端只能导出自己的错题")
    body.child_id = caller.user.id
    body.ids = []


@router.post("/sheet")
def export_sheet(
    *,
    session: SessionDep,
    caller: CallerDep,
    body: ExportSheetReq,
) -> Response:
    if caller.role == "child":
        _child_only_scope(caller, body)
        # 娃娃的 parent_id 就是归属守卫要的 owner；取不到时守卫会按越权拒绝。
        parent_id = caller.user.parent_id or caller.user.id
    else:
        parent_id = caller.user.id
    pdf = build_sheet_pdf(session=session, parent_id=parent_id, req=body)
    return Response(
        content=pdf,
        media_type="application/pdf",
        headers={"Content-Disposition": 'inline; filename="student-sheet.pdf"'},
    )
