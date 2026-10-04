"""资料库路由（ADR-0055）：家长专属——上传 / 目录 / 向量化状态 / 知识点目录。

所有端点 ``CurrentParent``（娃娃端没有资料库）；归属校验下沉 guard +
repository（get_owned_*），路由只做「接参数 → 调 service」。
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, File, Form, UploadFile

from app.core.deps import CurrentParent, SessionDep
from app.features.materials import indexing, service
from app.features.materials.schemas import (
    ExtractResult,
    FolderCreate,
    FolderResp,
    FolderUpdate,
    KnowledgePointConfirm,
    KnowledgePointListResp,
    MaterialResp,
    UploadResult,
)

router = APIRouter(prefix="/materials", tags=["materials"])


@router.get("/folders", response_model=list[FolderResp])
def list_folders(session: SessionDep, user: CurrentParent) -> list[FolderResp]:
    """扁平目录列表（前端组树），带直接子节点计数。"""
    return service.list_folders(session, parent_id=user.id)


@router.post("/folders", response_model=FolderResp)
def create_folder(
    session: SessionDep, user: CurrentParent, req: FolderCreate
) -> FolderResp:
    return service.create_folder(session, parent_id=user.id, req=req)


@router.patch("/folders/{folder_id}", response_model=FolderResp)
def update_folder(
    session: SessionDep, user: CurrentParent, folder_id: UUID, req: FolderUpdate
) -> FolderResp:
    return service.update_folder(
        session, parent_id=user.id, folder_id=folder_id, req=req
    )


@router.delete("/folders/{folder_id}")
def delete_folder(session: SessionDep, user: CurrentParent, folder_id: UUID) -> dict:
    service.delete_folder(session, parent_id=user.id, folder_id=folder_id)
    return {"deleted": True}


@router.post("/upload", response_model=UploadResult)
async def upload_material(
    session: SessionDep,
    user: CurrentParent,
    file: UploadFile = File(...),
    folder_id: UUID | None = Form(default=None),
    subject: str | None = Form(default=None),
    grade: int | None = Form(default=None),
) -> UploadResult:
    """上传一份资料（PDF / docx / txt / md）。

    解析失败 422、超限 413；AI 元数据提取失败**不阻塞入库**——响应里的
    ``extraction`` 字段告知四态之一，家长可在详情页重试提取。
    """
    data = await file.read()
    filename = file.filename or "未命名"
    return await service.upload_material(
        session,
        parent_id=user.id,
        filename=filename,
        data=data,
        folder_id=folder_id,
        subject=subject,
        grade=grade,
    )


@router.get("", response_model=list[MaterialResp])
def list_materials(
    session: SessionDep, user: CurrentParent, folder_id: UUID | None = None
) -> list[MaterialResp]:
    """资料列表；``folder_id`` 缺省 = 全部（含未归目录的根级资料）。"""
    return service.list_materials(session, parent_id=user.id, folder_id=folder_id)


@router.get("/knowledge-points", response_model=KnowledgePointListResp)
def list_knowledge_points(
    session: SessionDep, user: CurrentParent, subject: str, grade: int
) -> KnowledgePointListResp:
    """知识点选择器数据源：涌现目录（含待审）+ 骨架兜底（ADR-0055 §4）。"""
    return service.list_knowledge_points(
        session, parent_id=user.id, subject=subject, grade=grade
    )


@router.post("/knowledge-points/confirm")
def confirm_knowledge_points(
    session: SessionDep, user: CurrentParent, req: KnowledgePointConfirm
) -> dict:
    confirmed = service.confirm_knowledge_points(
        session,
        parent_id=user.id,
        subject=req.subject,
        grade=req.grade,
        names=req.names,
    )
    return {"confirmed": confirmed}


@router.get("/{material_id}", response_model=MaterialResp)
def get_material(
    session: SessionDep, user: CurrentParent, material_id: UUID
) -> MaterialResp:
    return service.get_material(session, parent_id=user.id, material_id=material_id)


@router.delete("/{material_id}")
def delete_material(
    session: SessionDep, user: CurrentParent, material_id: UUID
) -> dict:
    return service.delete_material(session, parent_id=user.id, material_id=material_id)


@router.post("/{material_id}/vectorize", response_model=MaterialResp)
async def vectorize_material(
    session: SessionDep, user: CurrentParent, material_id: UUID
) -> MaterialResp:
    """手动向量化 / 重新向量化（ADR-0055 §5：不自动触发，状态徽标提示）。

    服务端未配置 embedding 时 500 + ``LLM_UNAVAILABLE``；切片/embedding 失败
    不抛错——资料落 ``failed`` 态并附人话原因，家长可重试。
    """
    material = await indexing.vectorize_material(
        session, parent_id=user.id, material_id=material_id
    )
    return service.material_resp(material)


@router.post("/{material_id}/extract", response_model=ExtractResult)
async def reextract_metadata(
    session: SessionDep, user: CurrentParent, material_id: UUID
) -> ExtractResult:
    """手动重新提取元数据（首次提取失败 / 未配置模型时的重试入口）。"""
    return await service.reextract_metadata(
        session, parent_id=user.id, material_id=material_id
    )
