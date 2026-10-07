"""课件素材服务编排（ADR-0067 §3.5，切片 2）：上传 / 列表 / 删除 / 取原图。

四条纪律：

- **物理存储复用资料库的 per-teacher 目录**，不新造根目录。素材与资料只是逻辑
  实体不同（资料要切分向量化、素材只负责原样显示），落盘机制完全同构：
  ``MATERIAL_UPLOAD_ROOT/{teacher_id}/{uuid}{ext}``，``storage_key`` 存相对路径（§3.5）。
- **归属校验只走 ``core.guard``**，不内联比较 ``teacher_id``（分层守卫测试全仓
  AST 扫描）。不存在与越权抛同一个 404「素材不存在或无权限」。
- **删除无条件允许**（决策 10 / §4.2）：不查引用计数、不级联课件。删行 +
  best-effort 删物理文件，引用它的环节由展示侧显示「素材已移除」占位。
- **只收图片**：MIME 限 ``COURSEWARE_ASSET_MIMES``、字节数限
  ``COURSEWARE_ASSET_MAX_BYTES``，越限分别 422 / 413。
"""

from __future__ import annotations

import io
import uuid
from pathlib import Path

from sqlmodel import Session, select

from app.core.config import settings
from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned
from app.db.models import CoursewareAsset, KnowledgePoint
from app.db.models.courseware import (
    COURSEWARE_ASSET_MIMES,
    COURSEWARE_ASSET_SOURCE_PLATFORM_CC0,
)
from app.features.courseware.asset_schemas import (
    CoursewareAssetListResp,
    CoursewareAssetResp,
)


def asset_resp(asset: CoursewareAsset) -> CoursewareAssetResp:
    """ORM 行 → 契约响应。``url`` 由后端拼好下发，前端不自己拼鉴权前缀。"""
    return CoursewareAssetResp(
        id=asset.id,
        name=asset.name,
        mime=asset.mime,
        size_bytes=asset.size_bytes,
        width=asset.width,
        height=asset.height,
        created_at=asset.created_at,
        knowledge_point_id=asset.knowledge_point_id,
        url=f"{settings.API_V1_STR}/courseware/assets/{asset.id}/file",
        source=asset.source or "",
        source_url=asset.source_url or "",
        license=asset.license or "",
    )


def _owned(
    session: Session, *, teacher_id: uuid.UUID, asset_id: uuid.UUID
) -> CoursewareAsset:
    return require_owned(
        session=session,
        owner_id=teacher_id,
        model=CoursewareAsset,
        obj_id=asset_id,
        code=ErrCode.COURSEWARE_ASSET_NOT_FOUND,
        message="素材不存在或无权限",
    )


def _owned_or_cc0(
    session: Session, *, teacher_id: uuid.UUID, asset_id: uuid.UUID
) -> CoursewareAsset:
    """取素材：本人所有 **或** 平台 CC0 公共素材（任意教师可读原图）。

    CC0 素材归系统哨兵教师所有，但属于「平台公共素材」，任何已登录教师都应能在
    课件里引用并取到原图——否则引用了 CC0 的环节会整片「素材已移除」。删除保护
    另有 ``delete_asset`` 的 CC0 拦截，这里只放开**读**。
    """
    asset = session.get(CoursewareAsset, asset_id)
    if asset is None:
        raise AppErrorException(
            ErrCode.COURSEWARE_ASSET_NOT_FOUND, "素材不存在或无权限"
        )
    if asset.teacher_id == teacher_id or asset.source == COURSEWARE_ASSET_SOURCE_PLATFORM_CC0:
        return asset
    raise AppErrorException(
        ErrCode.COURSEWARE_ASSET_NOT_FOUND, "素材不存在或无权限"
    )


def _store_file(*, teacher_id: uuid.UUID, filename: str, data: bytes) -> str:
    """落盘到 per-teacher 目录（与资料库 ``_store_file`` 同款），返回相对 storage_key。"""
    root = Path(settings.MATERIAL_UPLOAD_ROOT) / str(teacher_id)
    root.mkdir(parents=True, exist_ok=True)
    ext = Path(filename).suffix.lower()
    key = f"{teacher_id}/{uuid.uuid4().hex}{ext}"
    (Path(settings.MATERIAL_UPLOAD_ROOT) / key).write_bytes(data)
    return key


def _probe_size(data: bytes) -> tuple[int | None, int | None]:
    """读图片宽高；读不到就留空（布局按可用宽度自适应，宽高只是可选优化）。

    ``pillow`` 已在依赖锁里（经 genkit 传入），不为此新增依赖；即便它不在环境里
    或图片损坏，也只是宽高为 ``None``，不影响入库与展示。
    """
    try:
        from PIL import Image
    except ImportError:
        return None, None
    try:
        with Image.open(io.BytesIO(data)) as img:
            return img.width, img.height
    except Exception:  # 损坏图片照常入库，宽高降级为 None
        return None, None


def upload_asset(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    filename: str,
    mime: str,
    data: bytes,
) -> CoursewareAssetResp:
    """上传一张课件素材（图片）。超限 413、非图片 422。"""
    if len(data) > settings.COURSEWARE_ASSET_MAX_BYTES:
        raise AppErrorException(
            ErrCode.COURSEWARE_ASSET_TOO_LARGE,
            f"素材超过大小上限（{settings.COURSEWARE_ASSET_MAX_BYTES // (1024 * 1024)}MB）",
        )
    if mime not in COURSEWARE_ASSET_MIMES:
        raise AppErrorException(
            ErrCode.COURSEWARE_ASSET_BAD_MIME,
            f"课件素材只支持图片：{', '.join(COURSEWARE_ASSET_MIMES)}",
        )
    width, height = _probe_size(data)
    asset = CoursewareAsset(
        teacher_id=teacher_id,
        name=filename,
        storage_key=_store_file(teacher_id=teacher_id, filename=filename, data=data),
        mime=mime,
        size_bytes=len(data),
        width=width,
        height=height,
    )
    session.add(asset)
    session.commit()
    session.refresh(asset)
    return asset_resp(asset)


def search_assets(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    knowledge_point_id: uuid.UUID | None = None,
    filename: str | None = None,
) -> CoursewareAssetListResp:
    """素材库检索（T04）：跨课件列出本人全部素材，可按知识点 / 文件名过滤。

    - ``knowledge_point_id`` 非 None 时断言该知识点属于本人（``require_owned`` 默认
      403）；跨教师传入即越权，统一返回 403（不降级成 404）。
    - ``filename`` 做大小写不敏感子串匹配（SQLite 的 LIKE 本身对 ASCII 不敏感，
      SQLAlchemy 的 ``ilike`` 在 SQLite 下编译为 ``LIKE``，语义一致）。
    - 结果永远只含本人素材：``teacher_id`` 在 WHERE 里硬约束，越权行根本不进结果。
    """
    if knowledge_point_id is not None:
        # 知识点归属校验：不属于本人 → 403（暴露越权而非伪装不存在）。
        require_owned(
            session=session,
            owner_id=teacher_id,
            model=KnowledgePoint,
            obj_id=knowledge_point_id,
            code=ErrCode.FORBIDDEN,
            message="知识点不存在或无权限",
        )
    # 本人全部素材 ∪ 平台 CC0 公共素材（对所有教师可见，与本人素材并列展示）。
    # 知识点过滤只作用于「本人素材」一侧——CC0 是通用公共素材，不受知识点约束。
    own = CoursewareAsset.teacher_id == teacher_id
    cc0 = CoursewareAsset.source == COURSEWARE_ASSET_SOURCE_PLATFORM_CC0
    stmt = (
        select(CoursewareAsset)
        .where(own | cc0)
        .order_by(CoursewareAsset.created_at)
    )
    if knowledge_point_id is not None:
        stmt = stmt.where(
            (CoursewareAsset.knowledge_point_id == knowledge_point_id) | cc0
        )
    if filename:
        stmt = stmt.where(CoursewareAsset.name.ilike(f"%{filename}%"))
    return CoursewareAssetListResp(
        items=[asset_resp(a) for a in session.exec(stmt).all()]
    )


def delete_asset(
    session: Session, *, teacher_id: uuid.UUID, asset_id: uuid.UUID
) -> None:
    """删除素材（决策 10）：**不查是否被课件引用**、不维护引用计数。

    引用它的环节留在课件里，展示侧按「素材已移除」占位渲染——「删不掉」比
    「出现空洞」更让人恼火（§4.2）。物理文件 best-effort 删除：文件不在不报错，
    DB 行已删，残留文件不影响正确性。

    **平台 CC0 公共素材禁止删除**：它不是任何教师的私有财产，删了会影响所有人
    引用它的课件。拦截返回 403（而非伪装 404），让调用方明确「这不是你的素材」。
    该检查放在归属校验之前——CC0 归系统哨兵教师，走 ``_owned`` 会先 404，必须
    先按 ``source`` 识别并拦下。
    """
    asset = session.get(CoursewareAsset, asset_id)
    if asset is None:
        raise AppErrorException(
            ErrCode.COURSEWARE_ASSET_NOT_FOUND, "素材不存在或无权限"
        )
    if asset.source == COURSEWARE_ASSET_SOURCE_PLATFORM_CC0:
        raise AppErrorException(
            ErrCode.FORBIDDEN, "平台 CC0 公共素材不可删除"
        )
    # 普通素材才做归属校验（CC0 已在上一步拦下，不会走到这里）。
    require_owned(
        session=session,
        owner_id=teacher_id,
        model=CoursewareAsset,
        obj_id=asset_id,
        code=ErrCode.COURSEWARE_ASSET_NOT_FOUND,
        message="素材不存在或无权限",
    )
    storage_key = asset.storage_key
    session.delete(asset)
    session.commit()
    if storage_key:
        try:
            (Path(settings.MATERIAL_UPLOAD_ROOT) / storage_key).unlink(missing_ok=True)
        except OSError:
            pass


def asset_file(
    session: Session, *, teacher_id: uuid.UUID, asset_id: uuid.UUID
) -> tuple[Path, str]:
    """取原图的 (落盘路径, MIME)；越权 / 不存在 / 文件已丢失一律 404 同一语义。

    读侧放开平台 CC0：任意教师都可在自己的课件里引用并取到 CC0 原图（写侧删
    除仍由 ``delete_asset`` 拦截）。
    """
    asset = _owned_or_cc0(session, teacher_id=teacher_id, asset_id=asset_id)
    path = Path(settings.MATERIAL_UPLOAD_ROOT) / asset.storage_key
    if not path.is_file():
        # 文件被外部清理过（删除是 best-effort，DB 行可能先于文件消失）：
        # 明确 404，别让 Starlette 的 FileResponse 抛 FileNotFoundError 变 500。
        raise AppErrorException(
            ErrCode.COURSEWARE_ASSET_NOT_FOUND, "素材文件不存在或无权限"
        )
    return path, asset.mime
