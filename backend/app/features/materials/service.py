"""资料库服务编排（ADR-0055）：目录管理 / 上传解析 / AI 元数据提取 / 知识点对齐。

三条纪律：
- **提取失败不阻塞入库**——文件永远先落盘，元数据四态（extracted /
  skipped_unsafe / skipped_no_engine / failed）随响应告知，教师可手动重试；
- **用户内容进 prompt 前过 ADR-0012 ``check_input``**（§9 版权与安全闸门）；
- **目录元数据是意图**——教师显式指定或目录继承的学科 / 年级不被 AI 推翻，
  AI 只补空白并贡献知识点。
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from pathlib import Path

from sqlmodel import Session, select

from agent_core.ports import StructuredDone
from app.core.ai_plumbing import build_ai_provider
from app.core.config import settings
from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned
from app.db.models import KnowledgePoint, Material, MaterialFolder
from app.db.models.material import (
    INDEX_STATE_READY,
    INDEX_STATE_STALE,
    KP_SOURCE_SKELETON,
    SceneTemplateConfig,
)
from app.domain.safety import check_input
from app.domain.subjects import SUBJECTS
from app.features.materials import indexing
from app.features.materials import repository as repo
from app.features.materials.parser import ParseError, extract_text
from app.features.materials.scene_figures import FIGURES
from app.features.materials.scene_templates import (
    SCENE_LIBRARY,
    list_builtin_scenes,
)
from app.features.materials.schemas import (
    ExtractResult,
    FigureLibraryItem,
    FigureLibraryResp,
    FolderCreate,
    FolderResp,
    FolderUpdate,
    KnowledgePointListResp,
    KnowledgePointResp,
    KnowledgePointScopeListResp,
    KnowledgePointScopeResp,
    MaterialMeta,
    MaterialResp,
    SceneLibraryItem,
    SceneLibraryKpRef,
    SceneLibraryResp,
    UploadResult,
)

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
        teacher_folder_id=folder.teacher_folder_id,
        subject=folder.subject,
        grade=folder.grade,
        semester=folder.semester,
        created_at=folder.created_at,
        material_count=mat_count,
        subfolder_count=sub_count,
    )


# ── 目录管理 ────────────────────────────────────────────────────────────


def list_folders(session: Session, *, teacher_id: uuid.UUID) -> list[FolderResp]:
    folders = repo.list_folders(session, teacher_id=teacher_id)
    counts = repo.folder_counts(session, teacher_id=teacher_id)
    return [folder_resp(f, counts.get(f.id)) for f in folders]


def create_folder(
    session: Session, *, teacher_id: uuid.UUID, req: FolderCreate
) -> FolderResp:
    if req.teacher_folder_id is not None:
        repo.get_owned_folder(
            session, teacher_id=teacher_id, folder_id=req.teacher_folder_id
        )
    folder = MaterialFolder(
        teacher_id=teacher_id,
        name=req.name.strip() or "未命名目录",
        teacher_folder_id=req.teacher_folder_id,
        subject=req.subject,
        grade=req.grade,
        semester=req.semester,
    )
    session.add(folder)
    session.commit()
    session.refresh(folder)
    return folder_resp(folder, None)


def update_folder(
    session: Session, *, teacher_id: uuid.UUID, folder_id: uuid.UUID, req: FolderUpdate
) -> FolderResp:
    folder = repo.get_owned_folder(session, teacher_id=teacher_id, folder_id=folder_id)
    if req.teacher_folder_id is not None and req.teacher_folder_id != folder.id:
        teacher = repo.get_owned_folder(
            session, teacher_id=teacher_id, folder_id=req.teacher_folder_id
        )
        _assert_not_descendant(
            session, teacher_id=teacher_id, folder=folder, target=teacher
        )
        folder.teacher_folder_id = req.teacher_folder_id
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
    teacher_id: uuid.UUID,
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
            session.get(MaterialFolder, cursor.teacher_folder_id)
            if cursor.teacher_folder_id
            else None
        )


def delete_folder(
    session: Session, *, teacher_id: uuid.UUID, folder_id: uuid.UUID
) -> None:
    folder = repo.get_owned_folder(session, teacher_id=teacher_id, folder_id=folder_id)
    if (
        repo.count_folder_materials(session, teacher_id=teacher_id, folder_id=folder_id)
        > 0
    ):
        raise AppErrorException(
            ErrCode.MATERIAL_FOLDER_NOT_EMPTY, "目录下仍有资料，请先移走或删除"
        )
    subs = [
        f
        for f in repo.list_folders(session, teacher_id=teacher_id)
        if f.teacher_folder_id == folder.id
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
        cursor_id = folder.teacher_folder_id
    return subject, grade, semester


def _semester_from_name(name: str) -> str | None:
    """文件名兜底推断学期（ADR-0055 §2 补，最低优先级）。

    教材文件名常带「上册 / 下册」→ 映射「上学期 / 下学期」。仅作**兜底**，
    不覆盖教师显式选择或目录继承（调用方须把本结果放在 ``semester or
    inherited_semester or _semester_from_name(...)`` 链最末）。命中不了返回 ``None``。
    """
    if "上册" in name:
        return "上学期"
    if "下册" in name:
        return "下学期"
    return None


def _store_file(*, teacher_id: uuid.UUID, filename: str, data: bytes) -> str:
    root = Path(settings.MATERIAL_UPLOAD_ROOT) / str(teacher_id)
    root.mkdir(parents=True, exist_ok=True)
    ext = Path(filename).suffix.lower()
    key = f"{teacher_id}/{uuid.uuid4().hex}{ext}"
    (Path(settings.MATERIAL_UPLOAD_ROOT) / key).write_bytes(data)
    return key


async def upload_material(
    session: Session,
    *,
    teacher_id: uuid.UUID,
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
        repo.get_owned_folder(session, teacher_id=teacher_id, folder_id=folder_id)
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
        teacher_id=teacher_id,
        folder_id=folder_id,
        name=filename,
        storage_key=_store_file(teacher_id=teacher_id, filename=filename, data=data),
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
        session, teacher_id=teacher_id, material=material
    )
    return UploadResult(
        material=material_resp(material), extraction=extraction, extraction_error=error
    )


async def reextract_metadata(
    session: Session, *, teacher_id: uuid.UUID, material_id: uuid.UUID
) -> ExtractResult:
    """手动重新提取：知识点**全量刷新**；学科 / 年级只补空白（不覆盖教师意图）。"""
    material = repo.get_owned_material(
        session, teacher_id=teacher_id, material_id=material_id
    )
    extraction, error = await _extract_and_align(
        session, teacher_id=teacher_id, material=material
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
    session: Session, *, teacher_id: uuid.UUID, material: Material
) -> tuple[str, str | None]:
    """跑整篇提取并写回 material + 对齐知识点目录。返回 (状态, 错误信息)。"""
    text = (material.text or "").strip()
    if not text:
        return "failed", "资料没有可分析的文本"
    verdict = check_input(text[:_PROMPT_TEXT_LIMIT], offtopic=False)
    if not verdict.safe:
        # ADR-0012：不安全内容不进 prompt；资料照常保留，只是不做 AI 提取。
        return "skipped_unsafe", verdict.reason

    provider = build_ai_provider(teacher_id=teacher_id, session=session)
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
    # 学期兜底：资料名含上册/下册且当前未设学期时自动带（最低优先级，不覆盖教师意图）。
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
        # 学期必须具体（2026-10-05 决策：不再允许空学期）：资料显式学期 > 文件名推断
        # （上册/下册）> 退上学期。整学年资料的知识点默认归上学期，讲解页可再改。
        kp_semester = (
            material.semester
            or _semester_from_name(material.name)
            or "上学期"
        )
        for name in names:
            repo.upsert_pending_knowledge_point(
                session,
                teacher_id=teacher_id,
                subject=material.subject,
                grade=material.grade,
                name=name,
                semester=kp_semester,
            )
    return "extracted", None


# ── 资料列表 / 详情 / 删除 ──────────────────────────────────────────────


def list_materials(
    session: Session, *, teacher_id: uuid.UUID, folder_id: uuid.UUID | None
) -> list[MaterialResp]:
    if folder_id is not None:
        repo.get_owned_folder(session, teacher_id=teacher_id, folder_id=folder_id)
    # 惰性 stale 标记：模型 / 切分器变更后，首次看列表即感知（ADR-0055 §5）
    indexing.mark_stale_if_model_changed(session, teacher_id=teacher_id)
    return [
        material_resp(m)
        for m in repo.list_materials(session, teacher_id=teacher_id, folder_id=folder_id)
    ]


def get_material(
    session: Session, *, teacher_id: uuid.UUID, material_id: uuid.UUID
) -> MaterialResp:
    return material_resp(
        repo.get_owned_material(session, teacher_id=teacher_id, material_id=material_id)
    )


def knowledge_point_scope(material: Material) -> tuple[str, int, str] | None:
    """资料对应的知识点作用域 ``(学科, 年级, 学期)``；信息不齐时返回 ``None``。

    学期口径必须与提取时（``_extract_and_align``）**逐字一致**：资料显式学期 >
    文件名推断（上册/下册）> 上学期。差一个字就定位不到当初涌现出的那一行，
    级联清理会静默失效。
    """
    if not material.subject or not material.grade:
        return None
    semester = (
        material.semester or _semester_from_name(material.name) or "上学期"
    )
    return material.subject, material.grade, semester


def _prune_knowledge_points(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    materials: Sequence[Material],
) -> list[KnowledgePoint]:
    """算出这批资料删掉之后**无人认领**的知识点（详见 repository 的三条口径）。"""
    candidates: list[tuple[str, int, str, str]] = []
    for material in materials:
        scope = knowledge_point_scope(material)
        if scope is None:
            continue
        subject, grade, semester = scope
        for name in material.knowledge_points or []:
            candidates.append((subject, grade, semester, name))
    if not candidates:
        return []
    return repo.prunable_knowledge_points(
        session,
        teacher_id=teacher_id,
        candidates=candidates,
        exclude_material_ids={m.id for m in materials},
    )


def delete_materials(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    material_ids: Sequence[uuid.UUID],
    cascade_knowledge_points: bool = False,
) -> dict:
    """删除一批资料（单个走同一路径，<｜hy_place▁holder▁no▁813｜> ids 长 1）。

    ``cascade_knowledge_points`` 为真时**顺带清理孤儿知识点**——判定口径见
    :func:`repository.prunable_knowledge_points`（只收回没被引用的待审涌现点）。
    为什么默认关闭：删除不可逆，副作用越少越安全；前端多选删除时显式询问后
    带上这个开关，但 API 默认必须保持「删什么就是什么」。
    """
    # 去重保序：多选 UI 可能给出重复 id，重复会让计数虚高。
    seen: set[uuid.UUID] = set()
    materials: list[Material] = []
    for material_id in material_ids:
        if material_id in seen:
            continue
        seen.add(material_id)
        materials.append(
            repo.get_owned_material(
                session, teacher_id=teacher_id, material_id=material_id
            )
        )
    if not materials:
        return {
            "deleted": True,
            "deleted_count": 0,
            "chunks_removed": 0,
            "knowledge_points_removed": 0,
        }

    kp_rows = (
        _prune_knowledge_points(session, teacher_id=teacher_id, materials=materials)
        if cascade_knowledge_points
        else []
    )
    chunks_removed = 0
    for index, material in enumerate(materials):
        # 知识点行只在最后一份资料上删一次：它们不属于某个具体 material。
        chunks, _ = repo.delete_material_cascade(
            session, material, kp_rows if index == len(materials) - 1 else ()
        )
        chunks_removed += chunks
        # 落盘文件 best-effort 清理：DB 已删，残留文件不影响正确性（检索走 DB）
        try:
            path = Path(settings.MATERIAL_UPLOAD_ROOT) / material.storage_key
            path.unlink(missing_ok=True)
        except OSError:
            pass
    return {
        "deleted": True,
        "deleted_count": len(materials),
        "chunks_removed": chunks_removed,
        "knowledge_points_removed": len(kp_rows),
    }


def delete_material(
    session: Session, *, teacher_id: uuid.UUID, material_id: uuid.UUID
) -> dict:
    """删单份资料：**不级联知识点**（保留既有语义）。需要清理请用批量端点。"""
    return delete_materials(
        session, teacher_id=teacher_id, material_ids=[material_id]
    )


def move_material(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    material_id: uuid.UUID,
    folder_id: uuid.UUID | None,
) -> Material:
    """把已有资料移到指定目录（``folder_id=None`` = 移回根目录）。

    只改归属指针；不触发重新提取 / 向量化（移动是纯组织操作）。若资料当前
    无学科 / 年级，且目标目录能提供，则顺手补齐继承值，避免移入带学科的目录
    后检索按学科过滤却命中不到（chunk 的 subject 取自 material.subject）。
    """
    material = repo.get_owned_material(
        session, teacher_id=teacher_id, material_id=material_id
    )
    if folder_id is not None:
        repo.get_owned_folder(session, teacher_id=teacher_id, folder_id=folder_id)
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


# ── 知识点目录（ADR-0065：只认从这里上传的教材里涌现出来的那些）──────


def list_knowledge_points(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    subject: str,
    grade: int,
    semester: str = "",
) -> KnowledgePointListResp:
    """某范围的知识点目录 = 该范围内上传过的教材里涌现出来的那些。

    2026-10-06 起**不再补预置目录**（旧的 skeleton 兜底已下线，见 ADR-0065）：
    预置目录让「1 年级数学」这种一份教材都没传的范围也列出十几条知识点，教师
    勾选确认后拿到的是和自己学生无关的空目录，还以为系统已经认出了教材。

    库里可能还有历史遗留的 skeleton 行（教师当年确认过）——这里一并屏蔽而不删
    库：删数据不可逆，而这些行还挂着交互讲解模板（scenes），留着数据随时可逆。
    """
    rows = [
        r
        for r in repo.list_knowledge_points(
            session,
            teacher_id=teacher_id,
            subject=subject,
            grade=grade,
            semester=semester,
        )
        if r.source != KP_SOURCE_SKELETON
    ]
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
    # 空列表本身不解释任何事——必须回答「为什么空」+「下一步做什么」（ADR-0051）。
    notice = ""
    if not items:
        material_count = repo.count_materials_in_scope(
            session, teacher_id=teacher_id, subject=subject, grade=grade
        )
        if material_count == 0:
            notice = (
                "这个学科年级还没有上传过教材，所以没有知识点。"
                "到「资料库」上传教材并完成提取后，知识点会自己出现在这里。"
            )
        else:
            notice = (
                f"这里有 {material_count} 份教材，但还没有识别出知识点。"
                "到「资料库」对这些资料点「重新提取」（需要先配置并设为默认模型）。"
            )
    return KnowledgePointListResp(
        items=items,
        pending_count=sum(1 for i in items if i.status == "pending"),
        notice=notice,
    )


def list_knowledge_point_scopes(
    session: Session, *, teacher_id: uuid.UUID
) -> KnowledgePointScopeListResp:
    """教师**实际上传过教材**的知识点范围清单（ADR-0065）。

    知识点管理页与出题表单的范围下拉都由它兜住：没传过教材的学科 / 年级根本不
    该出现在选项里——选进去只能看到空列表，等于把 9 个年级 × 3 学科的空门都摆
    出来让教师一个个试。

    学期走 ``knowledge_point_scope`` 的同一口径（显式 > 文件名推断 > 上学期）：
    这是知识点**诞生时**用的口径，这里若算法不一致，会出现「范围里列出了 4 年级
    数学上学期，点进去却一条知识点都没有」。
    """
    counts: dict[tuple[str, int, str], int] = {}
    unscoped = 0
    for material in repo.list_materials(session, teacher_id=teacher_id):
        scope = knowledge_point_scope(material)
        if scope is None:
            # 学科 / 年级缺失：归不到任何范围。必须计数回报——教师传了资料却在下
            # 拉里找不到对应年级，第一反应是「上传丢了」，实际是元数据没提取出来。
            unscoped += 1
            continue
        counts[scope] = counts.get(scope, 0) + 1
    scopes = [
        KnowledgePointScopeResp(
            subject=subject,
            grade=grade,
            semester=semester,
            material_count=count,
        )
        # 学科 → 年级 → 学期：与下拉的自然阅读顺序一致
        for (subject, grade, semester), count in sorted(counts.items())
    ]
    return KnowledgePointScopeListResp(scopes=scopes, unscoped_count=unscoped)


def list_scene_library(
    session: Session, *, teacher_id: uuid.UUID
) -> SceneLibraryResp:
    """场景库清单（ADR-0073）：内置注册表 + 本教师关联知识点的聚合。

    **实例口径只认后端内置参考**——统计「哪些知识点的 ``scenes`` 引用了某个
    kind」，**不跨查** ``Question.scene_spec`` / ``Courseware.sections`` 的生成
    快照。那些快照属于具体的题目 / 课件，只在它们自己的页面里渲染；搬进清单
    会把场景库变成快照垃圾场，而且计数随着每次出题一直涨，教师根本对不上。
    """
    # kind → 关联知识点。按 kp.id 去重：一个知识点的 scenes 里可能有多个同 kind
    # 的场景，但它作为「一个知识点」只该被计一次。
    grouped: dict[str, dict[uuid.UUID, SceneLibraryKpRef]] = {
        kind: {} for kind in SCENE_LIBRARY
    }
    rows = session.exec(
        select(KnowledgePoint).where(KnowledgePoint.teacher_id == teacher_id)
    ).all()
    for kp in rows:
        for scene in kp.scenes or []:
            kind = scene.get("kind") if isinstance(scene, dict) else None
            if kind in grouped:
                grouped[kind][kp.id] = SceneLibraryKpRef(
                    id=kp.id,
                    name=kp.name,
                    subject=kp.subject,
                    grade=kp.grade,
                    semester=kp.semester,
                    scenes=kp.scenes,
                    kp_missing=False,
                )
    # kind 级默认图形（ADR-0074 v4）：读 ``scene_template_config``，按 kind 透传。
    # 关联由 kp.scenes 的 kind 隐式表达（无关联表），这里只取默认值，不影响聚合口径。
    defaults = get_scene_default_figures(session)
    items: list[SceneLibraryItem] = []
    for scene in list_builtin_scenes():
        kind = str(scene.get("kind") or "")
        refs = sorted(
            grouped.get(kind, {}).values(),
            key=lambda ref: (ref.subject, ref.grade, ref.semester, ref.name),
        )
        items.append(
            SceneLibraryItem(
                kind=kind,
                title=str(scene.get("title") or ""),
                defaults=scene,
                associated_knowledge_points=refs,
                instance_count=len(refs),
                default_figure_key=defaults.get(kind),
            )
        )
    return SceneLibraryResp(scenes=items)


def get_scene_default_figures(session: Session) -> dict[str, str | None]:
    """读全部 kind 级默认演示图形（ADR-0074 v4）。返回 ``{kind: default_figure_key}``。"""
    rows = session.exec(select(SceneTemplateConfig)).all()
    return {
        r.kind: r.default_figure_key
        for r in rows
        if isinstance(r, SceneTemplateConfig)
    }


def set_scene_default_figure(
    session: Session, *, kind: str, default_figure_key: str | None
) -> None:
    """写某 kind 的默认演示图形（ADR-0074 v4）。kind 必须存在于注册表。

    空 key（``None`` / ``''``）视为清除默认 → 关联 seed 回落注册表 ``figure=''`` 空占位。
    默认图形只经 seed 注入新关联 KP，绝不回写已落库 ``kp.scenes`` / ``Question.scene_spec``
    （ADR-0073 快照不可变）。
    """
    if kind not in SCENE_LIBRARY:
        raise ValueError(f"unknown scene kind: {kind}")
    cfg = session.get(SceneTemplateConfig, kind)
    if default_figure_key in (None, ""):
        # 清除默认：删行即回落注册表空占位。
        if cfg is not None:
            session.delete(cfg)
            session.commit()
        return
    if cfg is None:
        cfg = SceneTemplateConfig(kind=kind)
        session.add(cfg)
    cfg.default_figure_key = default_figure_key
    session.add(cfg)
    session.commit()


def list_figure_library() -> FigureLibraryResp:
    """图形几何库（ADR-0073 遗留 4）：后端是顶点**唯一手写事实源**。

    前端 `figures.dart` 已改为由本库生成（`frontend/scripts/gen_figures.py`），
    不再是第二份手写副本——顶点漂移会让「是否轴对称」的判定变错（学生拖轴永远
    对不上），而手工同步两处正是漂移的唯一来源。

    端点与生成脚本**读同一份 ``FIGURES``**，所以「API 下发的几何」与「前端随包
    内置的几何」不可能不一致；需要刷新时重跑脚本即可，不必改两份。

    ⚠️ 这里**不做 house 兜底**：未命中 key 应由调用方降级（返回无图），而不是
    拿房子顶上——那是渲染层的「永不空」安全网，不是数据层的默认值。
    """
    return FigureLibraryResp(
        figures=[FigureLibraryItem(**shape.to_dict()) for shape in FIGURES]
    )


def update_knowledge_point_scenes(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    kp_id: uuid.UUID,
    scenes: list[dict],
) -> KnowledgePoint:
    """教师为知识点编写 / 覆盖默认交互讲解模板（ADR-0061）。

    owner 隔离：``kp_id`` 必须属于当前教师，否则视作不存在（``require_owned``）。
    空数组 = 清空模板。
    """
    kp = require_owned(
        session=session,
        owner_id=teacher_id,
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


def delete_knowledge_points(
    session: Session, *, teacher_id: uuid.UUID, ids: Sequence[uuid.UUID]
) -> int:
    """批量删除知识点（多选），返回实际删除条数。

    删除本身是安全的：知识点到题目是**快照式**引用（``Question`` / ``Task`` 只存
    知识点名字串，不建外键），所以删掉目录里的这一行不会破坏已出的题与掌握度
    统计——只是这个范围的下拉里不再有它、后续出题也不会再选它。
    """
    return repo.delete_knowledge_points(session, teacher_id=teacher_id, ids=list(ids))


def confirm_knowledge_points(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    subject: str,
    grade: int,
    names: list[str],
    semester: str = "",
) -> int:
    """确认知识点：待审转正；骨架条目落库为转正（source=skeleton）。返回转正数。

    按**概念名**跨学期生效（见 ``repository.confirm_knowledge_points_by_name``）：
    同一概念按学期拆成的多行会一并转正，避免「整学年」视图确认后仍有同名待审残留。
    ``semester`` 仅用于名下无行时新建骨架条的默认学期（默认整学年）。
    """
    if subject not in SUBJECTS:
        raise AppErrorException(ErrCode.VALIDATION, f"不支持的学科：{subject}")
    return repo.confirm_knowledge_points_by_name(
        session,
        teacher_id=teacher_id,
        subject=subject,
        grade=grade,
        names=names,
        semester=semester,
    )
