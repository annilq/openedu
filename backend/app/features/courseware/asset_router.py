"""课件素材路由（ADR-0067 §3.5，切片 2）：上传 / 列表 / 删除 / 取原图。

全端点 ``CurrentTeacher``（课件只做教师端，决策 8）；路由只做「接参数 → 调
service」，归属校验在 service 里经 ``core.guard``。

⚠️ 与课件线（切片 3）的 ``router.py`` **各写各的文件**（§6.4 约定 1）：两条线
并行开发，共用文件必然互相覆盖。本 router 只挂素材资源。
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, File, UploadFile
from fastapi.responses import FileResponse

from app.core.deps import CurrentTeacher, SessionDep
from app.features.courseware import asset_service
from app.features.courseware.asset_schemas import CoursewareAssetResp

router = APIRouter(prefix="/courseware", tags=["courseware"])


@router.post("/assets", response_model=CoursewareAssetResp)
async def upload_asset(
    session: SessionDep, user: CurrentTeacher, file: UploadFile = File(...)
) -> CoursewareAssetResp:
    """上传一张课件素材（图片）。

    非图片 422（``CW_91005``）、超上限 413（``CW_91004``）。素材不切分、不向量化——
    它是要原样投出去的图，与资料（Material）两条路（§3.5）。
    """
    data = await file.read()
    return asset_service.upload_asset(
        session,
        teacher_id=user.id,
        filename=file.filename or "素材",
        mime=file.content_type or "",
        data=data,
    )


@router.get("/assets", response_model=list[CoursewareAssetResp])
def list_assets(session: SessionDep, user: CurrentTeacher) -> list[CoursewareAssetResp]:
    """本人素材列表（按上传时间正序）。"""
    return asset_service.list_assets(session, teacher_id=user.id).items


@router.delete("/assets/{asset_id}")
def delete_asset(session: SessionDep, user: CurrentTeacher, asset_id: UUID) -> dict:
    """删除素材：**被课件引用也允许删**（决策 10 / §4.2），删后环节显示占位。

    不维护引用计数、不级联课件——「删不掉」比「出现空洞」更让人恼火。
    """
    asset_service.delete_asset(session, teacher_id=user.id, asset_id=asset_id)
    return {"deleted": True}


@router.get("/assets/{asset_id}/file")
def get_asset_file(session: SessionDep, user: CurrentTeacher, asset_id: UUID) -> FileResponse:
    """取素材原图（与列表同一鉴权路径）。越权 / 不存在一律 404 ``CW_91003``。"""
    path, mime = asset_service.asset_file(
        session, teacher_id=user.id, asset_id=asset_id
    )
    return FileResponse(path=path, media_type=mime)
