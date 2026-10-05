"""资料库服务编排（ADR-0055）：目录管理 / 上传解析 / AI 元数据提取 / 知识点对齐。

三条纪律：
- **提取失败不阻塞入库**——文件永远先落盘，元数据四态（extracted /
  skipped_unsafe / skipped_no_engine / failed）随响应告知，家长可手动重试；
- **用户内容进 prompt 前过 ADR-0012 ``check_input``**（§9 版权与安全闸门）；
- **目录元数据是意图**——家长显式指定或目录继承的学科 / 年级不被 AI 推翻，
  AI 只补空白并贡献知识点。
"""

from __future__ import annotations

import uuid
from pathlib import Path

from sqlmodel import Session

from agent_core.ports import StructuredDone
from app.core.ai_plumbing import build_ai_provider
from app.core.config import settings
from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned
from app.db.models import KnowledgePoint, Material, MaterialFolder
from app.db.models.material import INDEX_STATE_READY, INDEX_STATE_STALE
from app.domain.safety import check_input
from app.domain.subjects import SUBJECTS
from app.features.materials import indexing
from app.features.materials import repository as repo
from app.features.materials.parser import ParseError, extract_text
from app.features.materials.schemas import (
    ExtractResult,
    FolderCreate,
    FolderResp,
    FolderUpdate,
    KnowledgePointListResp,
    KnowledgePointResp,
    MaterialMeta,
    MaterialResp,
    UploadResult,
)
from app.features.materials.skeleton import skeleton_names

# 送进 LLM 的正文上限（字符）：整篇提取只需要「这是份什么资料」，不读全文
_PROMPT_TEXT_LIMIT = 6000


# ── 响应组装 ────────────────────────────────────────────────────────────


def material_resp(material: Material) -> MaterialResp:
    return MaterialResp(
        id=material.id,
        folder_id=material.folder_id,
        name=material.name,
        mime=material.mime,
        size_bytes=material.size_bytes,
        subject=material.subject,
        grade=material.grade,
        semester=material.semester,
        knowledge_points=material.knowledge_points or [],
        index_state=material.index_state,
        embed_model=material.embed_model,
        chunker_ver=material.chunker_ver,
        index_error=material.index_error,
        text_length=len(material.text or ""),
        created_at=material.created_at,
        indexed_at=material.indexed_at,
    )


def folder_resp(folder: MaterialFolder, counts: tuple[int, int] | None) -> FolderResp:
    mat_count, sub_count = counts if counts else (0, 0)
    return FolderResp(
        id=folder.id,
        name=folder.name,
        parent_folder_id=folder.parent_folder_id,
        subject=folder.subject,
        grade=folder.grade,
        semester=folder.semester,
        created_at=folder.created_at,
        material_count=mat_count,
        subfolder_count=sub_count,
    )


# ── 目录管理 ────────────────────────────────────────────────────────────


def list_folders(session: Session, *, parent_id: uuid.UUID) -> list[FolderResp]:
    folders = repo.list_folders(session, parent_id=parent_id)
    counts = repo.folder_counts(session, parent_id=parent_id)
    return [folder_resp(f, counts.get(f.id)) for f in folders]


def create_folder(
    session: Session, *, parent_id: uuid.UUID, req: FolderCreate
) -> FolderResp:
    if req.parent_folder_id is not None:
        repo.get_owned_folder(
            session, parent_id=parent_id, folder_id=req.parent_folder_id
        )
    folder = MaterialFolder(
        parent_id=parent_id,
        name=req.name.strip() or "未命名目录",
        parent_folder_id=req.parent_folder_id,
        subject=req.subject,
        grade=req.grade,
        semester=req.semester,
    )
    session.add(folder)
    session.commit()
    session.refresh(folder)
    return folder_resp(folder, None)


def update_folder(
    session: Session, *, parent_id: uuid.UUID, folder_id: uuid.UUID, req: FolderUpdate
) -> FolderResp:
    folder = repo.get_owned_folder(session, parent_id=parent_id, folder_id=folder_id)
    if req.parent_folder_id is not None and req.parent_folder_id != folder.id:
        parent = repo.get_owned_folder(
            session, parent_id=parent_id, folder_id=req.parent_folder_id
        )
        _assert_not_descendant(
            session, parent_id=parent_id, folder=folder, target=parent
        )
        folder.parent_folder_id = req.parent_folder_id
    if req.name is not None:
        folder.name = req.name.strip() or folder.name
    if "subject" in req.model_fields_set:
        folder.subject = req.subject
    if "grade" in req.model_fields_set:
        folder.grade = req.grade
    if "semester" in req.model_fields_set:
        folder.semester = req.semester
    session.add(folder)
    session.commit()
    session.refresh(folder)
    return folder_resp(folder, None)


def _assert_not_descendant(
    session: Session,
    *,
    parent_id: uuid.UUID,
    folder: MaterialFolder,
    target: MaterialFolder,
) -> None:
    """把目录挂进自己的子树会成环：沿 target 向上走，撞到自己即拒绝。"""
    seen: set[uuid.UUID] = set()
    cursor: MaterialFolder | None = target
    while cursor is not None and cursor.id not in seen:
        if cursor.id == folder.id:
            raise AppErrorException(
                ErrCode.VALIDATION, "不能把目录移动到它自己的子目录下"
            )
        seen.add(cursor.id)
        cursor = (
            session.get(MaterialFolder, cursor.parent_folder_id)
            if cursor.parent_folder_id
            else None
        )


def delete_folder(
    session: Session, *, parent_id: uuid.UUID, folder_id: uuid.UUID
) -> None:
    folder = repo.get_owned_folder(session, parent_id=parent_id, folder_id=folder_id)
    if (
        repo.count_folder_materials(session, parent_id=parent_id, folder_id=folder_id)
        > 0
    ):
        raise AppErrorException(
            ErrCode.MATERIAL_FOLDER_NOT_EMPTY, "目录下仍有资料，请先移走或删除"
        )
    subs = [
        f
        for f in repo.list_folders(session, parent_id=parent_id)
        if f.parent_folder_id == folder.id
    ]
    if subs:
        raise AppErrorException(
            ErrCode.MATERIAL_FOLDER_NOT_EMPTY, "目录下仍有子目录，请先删除"
        )
    session.delete(folder)
    session.commit()


# ── 上传与解析 ──────────────────────────────────────────────────────────


def _resolve_inherited(
    session: Session, folder_id: uuid.UUID | None
) -> tuple[str | None, int | None, str | None]:
    """沿目录链向上找最近一次设置的 (subject, grade, semester)（ADR-0055 §2 继承）。"""
    subject: str | None = None
    grade: int | None = None
    semester: str | None = None
    seen: set[uuid.UUID] = set()
    cursor_id = folder_id
    while cursor_id is not None and cursor_id not in seen:
        seen.add(cursor_id)
        folder = session.get(MaterialFolder, cursor_id)
        if folder is None:
            break
        if subject is None and folder.subject:
            subject = folder.subject
        if grade is None and folder.grade:
            grade = folder.grade
        if semester is None and folder.semester:
            semester = folder.semester
        cursor_id = folder.parent_folder_id
    return subject, grade, semester


def _semester_from_name(name: str) -> str | None:
    """文件名兜底推断学期（ADR-0055 §2 补，最低优先级）。

    教材文件名常带「上册 / 下册」→ 映射「上学期 / 下学期」。仅作**兜底**，
    不覆盖家长显式选择或目录继承（调用方须把本结果放在 ``semester or
    inherited_semester or _semester_from_name(...)`` 链最末）。命中不了返回 ``None``。
    """
    if "上册" in name:
        return "上学期"
    if "下册" in name:
        return "下学期"
    return None


def _store_file(*, parent_id: uuid.UUID, filename: str, data: bytes) -> str:
    root = Path(settings.MATERIAL_UPLOAD_ROOT) / str(parent_id)
    root.mkdir(parents=True, exist_ok=True)
    ext = Path(filename).suffix.lower()
    key = f"{parent_id}/{uuid.uuid4().hex}{ext}"
    (Path(settings.MATERIAL_UPLOAD_ROOT) / key).write_bytes(data)
    return key


async def upload_material(
    session: Session,
    *,
    parent_id: uuid.UUID,
    filename: str,
    data: bytes,
    folder_id: uuid.UUID | None,
    subject: str | None,
    grade: int | None,
    semester: str | None = None,
) -> UploadResult:
    if len(data) > settings.MATERIAL_MAX_BYTES:
        raise AppErrorException(
            ErrCode.MATERIAL_TOO_LARGE,
            f"文件超过大小上限（{settings.MATERIAL_MAX_BYTES // (1024 * 1024)}MB）",
        )
    if folder_id is not None:
        repo.get_owned_folder(session, parent_id=parent_id, folder_id=folder_id)
    try:
        text = extract_text(filename=filename, data=data)
    except ParseError as e:
        raise AppErrorException(ErrCode.MATERIAL_PARSE_FAILED, str(e)) from e

    inherited_subject, inherited_grade, inherited_semester = _resolve_inherited(
        session, folder_id
    )
    # 学期兜底链：显式指定 > 目录继承 > 文件名推断（上册/下册）
    effective_semester = (
        semester or inherited_semester or _semester_from_name(filename)
    )
    material = Material(
        parent_id=parent_id,
        folder_id=folder_id,
        name=filename,
        storage_key=_store_file(parent_id=parent_id, filename=filename, data=data),
        mime="",
        size_bytes=len(data),
        text=text,
        # 覆盖优先级：显式指定 > 目录继承 > 文件名推断（AI 只补空白，见模块 docstring）
        subject=subject or inherited_subject,
        grade=grade or inherited_grade,
        semester=effective_semester,
    )
    session.add(material)
    session.commit()
    session.refresh(material)

    extraction, error = await _extract_and_align(
        session, parent_id=parent_id, material=material
    )
    return UploadResult(
        material=material_resp(material), extraction=extraction, extraction_error=error
    )


async def reextract_metadata(
    session: Session, *, parent_id: uuid.UUID, material_id: uuid.UUID
) -> ExtractResult:
    """手动重新提取：知识点**全量刷新**；学科 / 年级只补空白（不覆盖家长意图）。"""
    material = repo.get_owned_material(
        session, parent_id=parent_id, material_id=material_id
    )
    extraction, error = await _extract_and_align(
        session, parent_id=parent_id, material=material
    )
    return ExtractResult(
        material=material_resp(material), extraction=extraction, extraction_error=error
    )


# ── AI 元数据提取（整篇一次，广播给所有 chunk —— ADR-0055 §3）──────────


_EXTRACT_SYSTEM = (
    "你是 K12 教研资料整理助手。根据用户提供的资料全文，判断它是哪个学科、"
    "哪个年级（1-9）的资料，并提炼 5-20 个资料中涉及的知识点（用教材常见的"
    "简短名词表述，如「两位数乘法」「一般过去时」）。只输出 JSON。"
)


async def _extract_and_align(
    session: Session, *, parent_id: uuid.UUID, material: Material
) -> tuple[str, str | None]:
    """跑整篇提取并写回 material + 对齐知识点目录。返回 (状态, 错误信息)。"""
    text = (material.text or "").strip()
    if not text:
        return "failed", "资料没有可分析的文本"
    verdict = check_input(text[:_PROMPT_TEXT_LIMIT], offtopic=False)
    if not verdict.safe:
        # ADR-0012：不安全内容不进 prompt；资料照常保留，只是不做 AI 提取。
        return "skipped_unsafe", verdict.reason

    provider = build_ai_provider(parent_id=parent_id, session=session)
    if not getattr(provider, "configured", True):
        return "skipped_no_engine", "未配置 AI 模型，请在「模型管理」中添加并设为默认"

    user_prompt = f"资料文件名：{material.name}\n资料全文（可能截断）：\n{text[:_PROMPT_TEXT_LIMIT]}"
    try:
        data: dict | None = None
        async for ev in provider.stream(
            _EXTRACT_SYSTEM, user_prompt, schema=MaterialMeta
        ):
            if isinstance(ev, StructuredDone):
                data = ev.data
                break
    except Exception as e:  # noqa: BLE001  (提取失败必须落库为可重试态，而非 500)
        return "failed", f"AI 提取失败：{e}"
    if not data:
        return "failed", "模型未返回结构化元数据"

    try:
        meta = MaterialMeta.model_validate(data)
    except Exception as e:  # noqa: BLE001
        return "failed", f"模型输出不符合元数据格式：{e}"
    subject = meta.subject.strip() if meta.subject.strip() in SUBJECTS else None
    grade = meta.grade if 1 <= meta.grade <= 9 else None
    if subject and not material.subject:
        material.subject = subject
    if grade and not material.grade:
        material.grade = grade
    # 学期兜底：资料名含上册/下册且当前未设学期时自动带（最低优先级，不覆盖家长意图）。
    # 既覆盖旧资料重抽（入库时尚未有文件名推断），也兜底 upload_material 之外直建的行。
    if not material.semester:
        inferred = _semester_from_name(material.name)
        if inferred:
            material.semester = inferred
    names: list[str] = []
    for raw in meta.knowledge_points:
        name = raw.strip()[:128]
        if name and name not in names:
            names.append(name)
    names = names[:20]
    material.knowledge_points = names
    session.add(material)
    session.commit()
    session.refresh(material)

    # 知识点对齐（ADR-0055 §4）：只在学科 / 年级齐备时入库，新知识点进「待审」
    if material.subject and material.grade and names:
        for name in names:
            repo.upsert_pending_knowledge_point(
                session,
                parent_id=parent_id,
                subject=material.subject,
                grade=material.grade,
                name=name,
                semester=material.semester or "",
            )
    return "extracted", None


# ── 资料列表 / 详情 / 删除 ──────────────────────────────────────────────


def list_materials(
    session: Session, *, parent_id: uuid.UUID, folder_id: uuid.UUID | None
) -> list[MaterialResp]:
    if folder_id is not None:
        repo.get_owned_folder(session, parent_id=parent_id, folder_id=folder_id)
    # 惰性 stale 标记：模型 / 切分器变更后，首次看列表即感知（ADR-0055 §5）
    indexing.mark_stale_if_model_changed(session, parent_id=parent_id)
    return [
        material_resp(m)
        for m in repo.list_materials(session, parent_id=parent_id, folder_id=folder_id)
    ]


def get_material(
    session: Session, *, parent_id: uuid.UUID, material_id: uuid.UUID
) -> MaterialResp:
    return material_resp(
        repo.get_owned_material(session, parent_id=parent_id, material_id=material_id)
    )


def delete_material(
    session: Session, *, parent_id: uuid.UUID, material_id: uuid.UUID
) -> dict:
    material = repo.get_owned_material(
        session, parent_id=parent_id, material_id=material_id
    )
    chunk_count = repo.delete_material_cascade(session, material)
    # 落盘文件 best-effort 清理：DB 已删，残留文件不影响正确性（检索走 DB）
    try:
        path = Path(settings.MATERIAL_UPLOAD_ROOT) / material.storage_key
        path.unlink(missing_ok=True)
    except OSError:
        pass
    return {"deleted": True, "chunks_removed": chunk_count}


def move_material(
    session: Session,
    *,
    parent_id: uuid.UUID,
    material_id: uuid.UUID,
    folder_id: uuid.UUID | None,
) -> Material:
    """把已有资料移到指定目录（``folder_id=None`` = 移回根目录）。

    只改归属指针；不触发重新提取 / 向量化（移动是纯组织操作）。若资料当前
    无学科 / 年级，且目标目录能提供，则顺手补齐继承值，避免移入带学科的目录
    后检索按学科过滤却命中不到（chunk 的 subject 取自 material.subject）。
    """
    material = repo.get_owned_material(
        session, parent_id=parent_id, material_id=material_id
    )
    if folder_id is not None:
        repo.get_owned_folder(session, parent_id=parent_id, folder_id=folder_id)
    material.folder_id = folder_id
    if material.subject is None or material.grade is None or material.semester is None:
        inh_subject, inh_grade, inh_semester = _resolve_inherited(session, folder_id)
        material.subject = material.subject or inh_subject
        material.grade = material.grade or inh_grade
        material.semester = material.semester or inh_semester
        # 仅补空白：若仍缺学科/年级，标记为 stale 让其重向量化时再确认
        if material.subject is None or material.grade is None:
            if material.index_state == INDEX_STATE_READY:
                material.index_state = INDEX_STATE_STALE
    session.add(material)
    session.commit()
    session.refresh(material)
    return material


# ── 知识点选择器（目录优先 + 骨架兜底，ADR-0055 §4）────────────────────


def list_knowledge_points(
    session: Session,
    *,
    parent_id: uuid.UUID,
    subject: str,
    grade: int,
    semester: str = "",
) -> KnowledgePointListResp:
    rows = repo.list_knowledge_points(
        session, parent_id=parent_id, subject=subject, grade=grade, semester=semester
    )
    known = {r.name for r in rows}
    items = [
        KnowledgePointResp(
            id=r.id,
            name=r.name,
            status=r.status,
            source=r.source,
            scenes=r.scenes,
            semester=r.semester,
        )
        for r in rows
    ]
    # 骨架补位：DB 已有（含待审）的名字不再重复给——家长自己涌现的措辞优先于骨架
    for name in skeleton_names(subject, grade):
        if name not in known:
            items.append(
                KnowledgePointResp(
                    id=None, name=name, status="curated", source="skeleton"
                )
            )
    # 只有骨架时**明说**（ADR-0061 §L）：骨架是分不出学期的大颗粒目录，家长切学期
    # 看到的下拉会逐字相同——不说清楚就像「联动坏了」，实际只是该范围还没资料。
    notice = ""
    if not rows and semester:
        notice = (
            f"该学期（{semester}）还没有资料知识点，以下是**不分学期**的通用目录；"
            "上传对应学期的资料并向量化后，这里才会按学期变化。"
        )
    return KnowledgePointListResp(
        items=items,
        pending_count=sum(1 for i in items if i.status == "pending"),
        notice=notice,
    )


def update_knowledge_point_scenes(
    session: Session,
    *,
    parent_id: uuid.UUID,
    kp_id: uuid.UUID,
    scenes: list[dict],
) -> KnowledgePoint:
    """教师为知识点编写 / 覆盖默认交互讲解模板（ADR-0061）。

    owner 隔离：``kp_id`` 必须属于当前家长，否则视作不存在（``require_owned``）。
    空数组 = 清空模板。
    """
    kp = require_owned(
        session=session,
        owner_id=parent_id,
        model=KnowledgePoint,
        obj_id=kp_id,
        code=ErrCode.NOT_FOUND,
        message="知识点不存在",
    )
    kp.scenes = scenes or None
    session.add(kp)
    session.commit()
    session.refresh(kp)
    return kp


def confirm_knowledge_points(
    session: Session,
    *,
    parent_id: uuid.UUID,
    subject: str,
    grade: int,
    names: list[str],
    semester: str = "",
) -> int:
    """确认知识点：待审转正；骨架条目落库为转正（source=skeleton）。返回转正数。"""
    if subject not in SUBJECTS:
        raise AppErrorException(ErrCode.VALIDATION, f"不支持的学科：{subject}")
    confirmed = 0
    for raw in names:
        name = raw.strip()[:128]
        if not name:
            continue
        kp = repo.find_knowledge_point(
            session,
            parent_id=parent_id,
            subject=subject,
            grade=grade,
            name=name,
            semester=semester,
        )
        if kp is None:
            kp = KnowledgePoint(
                parent_id=parent_id,
                subject=subject,
                grade=grade,
                semester=semester,
                name=name,
                status="curated",
                source="skeleton",
            )
            confirmed += 1
        elif kp.status == "pending":
            confirmed += 1
        repo.confirm_knowledge_point(session, kp)
    return confirmed
