"""课件路由（ADR-0067 切片 3）：教师专属——列表 / 新建 / 最近 / 读 / 改 / 覆盖写环节 / 删。

路由只做「接参数 → 调 service」：归属校验在 service（经 ``core.guard``），
环节 kind 校验在 service（注册表 §3.3）。本文件不持有任何业务规则。

⚠️ ``/recent`` 必须声明在 ``/{courseware_id}`` **之前**：否则「recent」会被当成
一个 UUID 去解析，回执端点永远 422（§3.8 的补偿项会静默失效）。
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter

from app.core.deps import CurrentTeacher, SessionDep
from app.features.courseware import service
from app.features.courseware.schemas import (
    CoursewareCreate,
    CoursewareResp,
    CoursewareSectionsUpdate,
    CoursewareUpdate,
)

router = APIRouter(prefix="/courseware", tags=["courseware"])


@router.get("", response_model=list[CoursewareResp])
def list_coursewares(
    session: SessionDep,
    user: CurrentTeacher,
    knowledge_point_id: UUID | None = None,
    subject: str | None = None,
    grade: int | None = None,
    semester: str | None = None,
) -> list[CoursewareResp]:
    """本人的课件列表（四个范围维度全空 = 全部），按最近更新倒序。

    范围按**课件行的快照**筛（建课件时从知识点拷过来），不看知识点表——知识
    点被 ADR-0064 清理后课件照样筛得到（§4.1）。
    """
    return service.list_coursewares(
        session,
        teacher_id=user.id,
        knowledge_point_id=knowledge_point_id,
        subject=subject,
        grade=grade,
        semester=semester,
    )


@router.post("", response_model=CoursewareResp)
def create_courseware(
    session: SessionDep, user: CurrentTeacher, req: CoursewareCreate
) -> CoursewareResp:
    """新建课件：**AI 起草后落库**（决策 2 / §3.4）。

    未配模型 → 500 + ``LLM_UNAVAILABLE``（「未配置模型，无法起草课件」），且不落库；
    起草被厂商拒绝 / 产出解析不出 → 502 / ``LLM_REQUEST_FAILED`` 带实际原因。
    知识点不存在或非本人 → 404 + ``COURSEWARE_KP_NOT_FOUND``。
    """
    return service.create_courseware(session, teacher_id=user.id, req=req)


@router.get("/recent", response_model=CoursewareResp | None)
def recent_courseware(session: SessionDep, user: CurrentTeacher) -> CoursewareResp | None:
    """最近更新的那一份课件（ADR-0067 §3.8「最近课件」回执的数据源）。

    没有课件返回 ``null``（不是 404）：空态由知识点管理页自己决定怎么显示，
    接口只如实回答「有没有」。
    """
    return service.recent_courseware(session, teacher_id=user.id)


@router.get("/{courseware_id}", response_model=CoursewareResp)
def get_courseware(
    session: SessionDep, user: CurrentTeacher, courseware_id: UUID
) -> CoursewareResp:
    """读一份课件；不存在或非本人 → 404 + ``COURSEWARE_NOT_FOUND``。"""
    return service.get_courseware(
        session, teacher_id=user.id, courseware_id=courseware_id
    )


@router.patch("/{courseware_id}", response_model=CoursewareResp)
def update_courseware(
    session: SessionDep,
    user: CurrentTeacher,
    courseware_id: UUID,
    req: CoursewareUpdate,
) -> CoursewareResp:
    """改标题 / 状态（只传要改的字段）。

    状态**不阻塞任何读操作**：draft 也能开讲，它只是列表上的标签（§3.2）。
    """
    return service.update_courseware(
        session, teacher_id=user.id, courseware_id=courseware_id, req=req
    )


@router.put("/{courseware_id}/sections", response_model=CoursewareResp)
def replace_sections(
    session: SessionDep,
    user: CurrentTeacher,
    courseware_id: UUID,
    req: CoursewareSectionsUpdate,
) -> CoursewareResp:
    """整体覆盖写环节序列（排序 / 增删改都在前端完成，后端只存结果）。

    kind 不在注册表 → 422 + ``COURSEWARE_BAD_KIND``（§3.3：不接受自由字符串）。
    """
    return service.replace_sections(
        session, teacher_id=user.id, courseware_id=courseware_id, req=req
    )


@router.delete("/{courseware_id}")
def delete_courseware(
    session: SessionDep, user: CurrentTeacher, courseware_id: UUID
) -> dict:
    """删一份课件（不含素材：素材由 A 线的 ``/courseware/assets`` 管理）。"""
    service.delete_courseware(session, teacher_id=user.id, courseware_id=courseware_id)
    return {"deleted": True}
