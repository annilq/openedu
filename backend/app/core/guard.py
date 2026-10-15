"""归属校验（ownership guard）——「某资源是否属于当前教师」的唯一归属模块。

此前这条不变量散在 7 处各写一遍 ``obj.teacher_id != teacher.id``，失败语义互相
矛盾：同一种越权，tutor 返 403、students 返 404、tasks/router 报「任务不存在」
（把越权伪装成不存在），校验还横跨 router 与 repository 两层。漏写一处即越权读。

现在只有一个接口：:func:`require_owned`（以及它针对学生的别名
:func:`require_owned_student`）。调用方只决定**失败时暴露什么**（错误码与文案），
因为那是各自端点的对外契约；「怎么判归属」不再有第二份实现。

放在 ``core`` 而非某个 feature：它同时被 router、service、repository 与
ADR-0033 的业务查询工具调用，不属于任何单一能力。
"""

from __future__ import annotations

from typing import TypeVar
from uuid import UUID

from sqlalchemy import and_
from sqlmodel import Session, SQLModel, select

from app.core.errors import AppErrorException, ErrCode
from app.db.models import Conversation, Role, User

_T = TypeVar("_T", bound=SQLModel)


def require_owned(
    *,
    session: Session,
    owner_id: UUID,
    model: type[_T],
    obj_id: UUID,
    code: ErrCode = ErrCode.FORBIDDEN,
    message: str = "无权访问该资源",
) -> _T:
    """断言 ``obj_id`` 指向的 ``model`` 行属于 ``owner_id``，返回该行。

    不存在与不属于**抛同一个错误**：返回 404 会把「越权」降级成「不存在」，
    掩盖越权尝试；除端点明确要伪装（见 ``tasks`` 的「任务不存在」）外，
    默认按 403 处理。
    """
    obj = session.get(model, obj_id)
    if obj is None or getattr(obj, "teacher_id", None) != owner_id:
        raise AppErrorException(code, message)
    return obj


def find_owned(
    *, session: Session, owner_id: UUID, model: type[_T], obj_id: UUID
) -> _T | None:
    """软判定：归属则返回该行，否则 ``None``，由调用方决定错误语义。

    给「取不到就当没配」这类读路径用（如教师自定义模型：未配置回落全局默认，
    不该抛错）。硬失败一律走 :func:`require_owned`。
    """
    obj = session.get(model, obj_id)
    if obj is None or getattr(obj, "teacher_id", None) != owner_id:
        return None
    return obj


def require_owned_or_admin(
    *,
    session: Session,
    owner_id: UUID,
    model: type[_T],
    obj_id: UUID,
    user: User,
    code: ErrCode = ErrCode.FORBIDDEN,
    message: str = "无权访问该资源",
) -> _T:
    """归属校验，但 ``admin`` 豁免（ADR-0088）。

    admin 是「超级教师」，可越教师边界读全部资源（如查看任意教师的 AI 运行轨迹）。
    仅用于「只读审计 / 排障」类端点；任何写操作仍需显式 owner 校验，不被此函数豁免。
    """
    if user.role == Role.ADMIN:
        obj = session.get(model, obj_id)
        if obj is None:
            raise AppErrorException(code, message)
        return obj
    return require_owned(
        session=session,
        owner_id=owner_id,
        model=model,
        obj_id=obj_id,
        code=code,
        message=message,
    )


# ── 会话归属（ADR-0096） ────────────────────────────────────────────────────
def conversation_owner_clause(user: User):
    """「这条会话属于本人」的 SQL 判据——会话归属的**唯一真源**（ADR-0096）。

    - 学生：``student_id == 本人``；
    - 教师 / admin：``teacher_id == 本人 AND student_id IS NULL``——只看自己聊的，
      不再看名下学生的（ADR-0048 §3 的反转）。

    **``teacher_id`` 列不等于归属**：它在 chat 链路里还表示教学域（RAG 检索范围、
    引擎解析，见 ``service.chat`` 的角色分流），学生的会话也填的是其教师。所以
    「谁的教学域」与「谁能看」在这里是两件事，本函数只表达后者——别把它改成
    单字段比较，那会把教学域重新混进归属口径。

    列表（SQL 过滤）、详情（单行断言）、删除（批量过滤）三处都从这里取判据，
    避免「列表里有但详情 403」这类分裂。
    """
    if user.role == Role.STUDENT:
        return Conversation.student_id == user.id
    return and_(
        Conversation.teacher_id == user.id,
        Conversation.student_id.is_(None),
    )


def require_owned_conversation(
    *,
    session: Session,
    user: User,
    conv_id: UUID,
    code: ErrCode = ErrCode.FORBIDDEN,
    message: str = "无权访问该会话",
) -> Conversation:
    """断言 ``conv_id`` 是**本人**的会话，返回该行。

    不存在与不属于抛同一个错误（同 :func:`require_owned`）：否则「越权」会被
    降级成「不存在」，掩盖越权尝试。
    """
    obj = session.exec(
        select(Conversation).where(
            Conversation.id == conv_id,
            conversation_owner_clause(user),
        )
    ).first()
    if obj is None:
        raise AppErrorException(code, message)
    return obj


def owned_conversation_ids(
    *, session: Session, user: User, ids: list[UUID]
) -> list[UUID]:
    """批量版：返回给定 id 中**确实属于本人**的那些（其余静默忽略）。

    给多选删除用——越权 id 不报错也不删，与 :func:`require_owned_conversation`
    共用同一判据，不会出现「列表能列出、删除却删不掉」的口径差。
    """
    if not ids:
        return []
    return list(
        session.exec(
            select(Conversation.id).where(
                Conversation.id.in_(ids),
                conversation_owner_clause(user),
            )
        ).all()
    )


def require_owned_student(
    *,
    session: Session,
    owner_id: UUID,
    student_id: UUID,
    code: ErrCode = ErrCode.TASK_NOT_YOUR_STUDENT,
    message: str = "该学生不属于你的账号",
) -> User:
    """断言 ``student_id`` 是 ``owner_id`` 名下学生，返回该 ``User``。

    只判归属，**不判角色**：调用方若要求目标必须是学生账号（而非教师），
    自行再校验 ``role``——那是另一个不变量。
    """
    return require_owned(
        session=session,
        owner_id=owner_id,
        model=User,
        obj_id=student_id,
        code=code,
        message=message,
    )
