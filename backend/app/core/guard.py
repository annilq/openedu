"""归属校验（ownership guard）——「某资源是否属于当前家长」的唯一归属模块。

此前这条不变量散在 7 处各写一遍 ``obj.parent_id != parent.id``，失败语义互相
矛盾：同一种越权，tutor 返 403、children 返 404、tasks/router 报「任务不存在」
（把越权伪装成不存在），校验还横跨 router 与 repository 两层。漏写一处即越权读。

现在只有一个接口：:func:`require_owned`（以及它针对娃娃的别名
:func:`require_owned_child`）。调用方只决定**失败时暴露什么**（错误码与文案），
因为那是各自端点的对外契约；「怎么判归属」不再有第二份实现。

放在 ``core`` 而非某个 feature：它同时被 router、service、repository 与
ADR-0033 的业务查询工具调用，不属于任何单一能力。
"""

from __future__ import annotations

from typing import TypeVar
from uuid import UUID

from sqlmodel import Session, SQLModel

from app.core.errors import AppErrorException, ErrCode
from app.db.models import User

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
    if obj is None or getattr(obj, "parent_id", None) != owner_id:
        raise AppErrorException(code, message)
    return obj


def find_owned(
    *, session: Session, owner_id: UUID, model: type[_T], obj_id: UUID
) -> _T | None:
    """软判定：归属则返回该行，否则 ``None``，由调用方决定错误语义。

    给「取不到就当没配」这类读路径用（如家长自定义模型：未配置回落全局默认，
    不该抛错）。硬失败一律走 :func:`require_owned`。
    """
    obj = session.get(model, obj_id)
    if obj is None or getattr(obj, "parent_id", None) != owner_id:
        return None
    return obj


def require_owned_child(
    *,
    session: Session,
    owner_id: UUID,
    child_id: UUID,
    code: ErrCode = ErrCode.TASK_NOT_YOUR_CHILD,
    message: str = "该娃娃不属于你的账号",
) -> User:
    """断言 ``child_id`` 是 ``owner_id`` 名下娃娃，返回该 ``User``。

    只判归属，**不判角色**：调用方若要求目标必须是娃娃账号（而非家长），
    自行再校验 ``role``——那是另一个不变量。
    """
    return require_owned(
        session=session,
        owner_id=owner_id,
        model=User,
        obj_id=child_id,
        code=code,
        message=message,
    )
