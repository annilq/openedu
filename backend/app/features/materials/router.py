"""资料库路由（ADR-0055）：教师专属——上传 / 目录 / 向量化状态 / 知识点目录。

所有端点 ``CurrentTeacher``（学生端没有资料库）；归属校验下沉 guard +
repository（get_owned_*），路由只做「接参数 → 调 service」。
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, File, Form, UploadFile

from app.core.deps import CurrentTeacher, SessionDep
from app.features.materials import indexing, service
from app.features.materials.schemas import (
    ExtractResult,
    FolderCreate,
    FolderResp,
    FolderUpdate,
    KnowledgePointConfirm,
    KnowledgePointDelete,
    KnowledgePointListResp,
    KnowledgePointResp,
    KnowledgePointScenesUpdate,
    KnowledgePointScopeListResp,
    MaterialDelete,
    MaterialMove,
    MaterialResp,
    UploadResult,
)

router = APIRouter(prefix="/materials", tags=["materials"])


@router.get("/folders", response_model=list[FolderResp])
def list_folders(session: SessionDep, user: CurrentTeacher) -> list[FolderResp]:
    """扁平目录列表（前端组树），带直接子节点计数。"""
    return service.list_folders(session, teacher_id=user.id)


@router.post("/folders", response_model=FolderResp)
def create_folder(
    session: SessionDep, user: CurrentTeacher, req: FolderCreate
) -> FolderResp:
    return service.create_folder(session, teacher_id=user.id, req=req)


@router.patch("/folders/{folder_id}", response_model=FolderResp)
def update_folder(
    session: SessionDep, user: CurrentTeacher, folder_id: UUID, req: FolderUpdate
) -> FolderResp:
    return service.update_folder(
        session, teacher_id=user.id, folder_id=folder_id, req=req
    )


@router.delete("/folders/{folder_id}")
def delete_folder(session: SessionDep, user: CurrentTeacher, folder_id: UUID) -> dict:
    service.delete_folder(session, teacher_id=user.id, folder_id=folder_id)
    return {"deleted": True}


@router.post("/upload", response_model=UploadResult)
async def upload_material(
    session: SessionDep,
    user: CurrentTeacher,
    file: UploadFile = File(...),
    folder_id: UUID | None = Form(default=None),
    subject: str | None = Form(default=None),
    grade: int | None = Form(default=None),
    semester: str | None = Form(default=None),
) -> UploadResult:
    """上传一份资料（PDF / docx / txt / md）。

    解析失败 422、超限 413；AI 元数据提取失败**不阻塞入库**——响应里的
    ``extraction`` 字段告知四态之一，教师可在详情页重试提取。
    """
    data = await file.read()
    filename = file.filename or "未命名"
    return await service.upload_material(
        session,
        teacher_id=user.id,
        filename=filename,
        data=data,
        folder_id=folder_id,
        subject=subject,
        grade=grade,
        semester=semester,
    )


@router.get("", response_model=list[MaterialResp])
def list_materials(
    session: SessionDep, user: CurrentTeacher, folder_id: UUID | None = None
) -> list[MaterialResp]:
    """资料列表；``folder_id`` 缺省 = 全部（含未归目录的根级资料）。"""
    return service.list_materials(session, teacher_id=user.id, folder_id=folder_id)


@router.get("/knowledge-points", response_model=KnowledgePointListResp)
def list_knowledge_points(
    session: SessionDep, user: CurrentTeacher, subject: str, grade: int, semester: str = ""
) -> KnowledgePointListResp:
    """知识点选择器数据源：涌现目录（含待审）+ 骨架兜底（ADR-0055 §4）。"""
    return service.list_knowledge_points(
        session, teacher_id=user.id, subject=subject, grade=grade, semester=semester
    )


@router.get("/knowledge-points/scopes", response_model=KnowledgePointScopeListResp)
def list_knowledge_point_scopes(
    session: SessionDep, user: CurrentTeacher
) -> KnowledgePointScopeListResp:
    """知识点范围清单：**只有上传过教材的** (学科, 年级, 学期) 才会出现（ADR-0065）。

    范围下拉据此构造——不这么做的话，9 个年级 × 3 学科里绝大多数是空门，教师挨
    个点进去全是空的，还得自己记哪个年级传过教材。
    """
    return service.list_knowledge_point_scopes(session, teacher_id=user.id)


@router.post("/knowledge-points/confirm")
def confirm_knowledge_points(
    session: SessionDep, user: CurrentTeacher, req: KnowledgePointConfirm
) -> dict:
    confirmed = service.confirm_knowledge_points(
        session,
        teacher_id=user.id,
        subject=req.subject,
        grade=req.grade,
        names=req.names,
        semester=req.semester,
    )
    return {"confirmed": confirmed}


@router.patch("/knowledge-points/{kp_id}/scenes", response_model=KnowledgePointResp)
def update_knowledge_point_scenes_endpoint(
    session: SessionDep,
    user: CurrentTeacher,
    kp_id: UUID,
    req: KnowledgePointScenesUpdate,
) -> KnowledgePointResp:
    """教师为知识点编写 / 覆盖默认交互讲解模板（ADR-0061）。

    仅更新 ``scenes`` 字段；owner 隔离在 service 层校验。
    """
    kp = service.update_knowledge_point_scenes(
        session,
        teacher_id=user.id,
        kp_id=kp_id,
        scenes=req.scenes,
    )
    return KnowledgePointResp(
        id=kp.id, name=kp.name, status=kp.status, source=kp.source, scenes=kp.scenes
    )


@router.post("/bulk-delete")
def bulk_delete_materials(
    session: SessionDep, user: CurrentTeacher, req: MaterialDelete
) -> dict:
    """批量删除资料（多选）。

    ``cascade_knowledge_points`` 为真时顺带清理**孤儿知识点**（仅由这批资料涌现、
    已无其它资料引用、且教师从未确认过的待审条目）；已转正的知识点不会被清理，
    那是教师的资产，请到「知识点管理」里手动删。
    """
    return service.delete_materials(
        session,
        teacher_id=user.id,
        material_ids=req.ids,
        cascade_knowledge_points=req.cascade_knowledge_points,
    )


@router.post("/knowledge-points/bulk-delete")
def bulk_delete_knowledge_points(
    session: SessionDep, user: CurrentTeacher, req: KnowledgePointDelete
) -> dict:
    """批量删除知识点（多选）。越权 / 不存在的 id 静默跳过，不会误删他人数据。"""
    removed = service.delete_knowledge_points(
        session, teacher_id=user.id, ids=req.ids
    )
    return {"deleted": True, "deleted_count": removed}


@router.get("/{material_id}", response_model=MaterialResp)
def get_material(
    session: SessionDep, user: CurrentTeacher, material_id: UUID
) -> MaterialResp:
    return service.get_material(session, teacher_id=user.id, material_id=material_id)


@router.delete("/{material_id}")
def delete_material(
    session: SessionDep, user: CurrentTeacher, material_id: UUID
) -> dict:
    return service.delete_material(session, teacher_id=user.id, material_id=material_id)


@router.patch("/{material_id}", response_model=MaterialResp)
def move_material_endpoint(
    session: SessionDep, user: CurrentTeacher, material_id: UUID, req: MaterialMove
) -> MaterialResp:
    """移动资料到指定目录（``folder_id=None`` = 移回根目录，ADR-0055 B6 补全）。"""
    material = service.move_material(
        session, teacher_id=user.id, material_id=material_id, folder_id=req.folder_id
    )
    return service.material_resp(material)


@router.post("/{material_id}/vectorize", response_model=MaterialResp)
async def vectorize_material(
    session: SessionDep, user: CurrentTeacher, material_id: UUID
) -> MaterialResp:
    """手动向量化 / 重新向量化（ADR-0055 §5：不自动触发，状态徽标提示）。

    服务端未配置 embedding 时 500 + ``LLM_UNAVAILABLE``；切片/embedding 失败
    不抛错——资料落 ``failed`` 态并附人话原因，教师可重试。
    """
    material = await indexing.vectorize_material(
        session, teacher_id=user.id, material_id=material_id
    )
    return service.material_resp(material)


@router.post("/{material_id}/extract", response_model=ExtractResult)
async def reextract_metadata(
    session: SessionDep, user: CurrentTeacher, material_id: UUID
) -> ExtractResult:
    """手动重新提取元数据（首次提取失败 / 未配置模型时的重试入口）。"""
    return await service.reextract_metadata(
        session, teacher_id=user.id, material_id=material_id
    )
