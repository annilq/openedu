from fastapi import APIRouter, HTTPException, status
from uuid import UUID

from app.api.deps import CurrentParent, SessionDep
from app.crud import create_user, get_user_by_username, list_children, update_user
from app.models import UserCreate, UserPublic, UserUpdate, UsersPublic

router = APIRouter(prefix="/children", tags=["children"])


@router.post("", response_model=UserPublic, status_code=status.HTTP_201_CREATED)
def create_child(
    *, session: SessionDep, parent: CurrentParent, child_in: UserCreate
) -> UserPublic:
    if get_user_by_username(session=session, username=child_in.username):
        raise HTTPException(status_code=400, detail="Username already registered")
    child = create_user(
        session=session,
        user_create=child_in,
        role="child",
        parent_id=parent.id,
    )
    return child


@router.put("/{child_id}", response_model=UserPublic)
def update_child(
    *,
    session: SessionDep,
    parent: CurrentParent,
    child_id: UUID,
    payload: UserUpdate,
) -> UserPublic:
    """编辑娃娃资料（WF-5）：仅昵称/年级/兴趣可改，账号密码锁定不编辑。

    仅传入非 None 的字段生效；目标娃娃须属于当前家长。
    """
    child = session.get(User, child_id)
    if child is None or child.parent_id != parent.id:
        raise HTTPException(status_code=404, detail="娃娃不存在或不属于你的账号")
    if child.role != "child":
        raise HTTPException(status_code=400, detail="仅可编辑娃娃账号")
    # 局部更新：忽略未传入（None）的字段
    patch = payload.model_dump(exclude_unset=True)
    if not patch:
        return child
    updated = update_user(
        session=session,
        user=child,
        display_name=payload.display_name,
        grade=payload.grade,
        interests=payload.interests,
    )
    return updated


@router.get("", response_model=UsersPublic)
def get_children(*, session: SessionDep, parent: CurrentParent) -> UsersPublic:
    children = list_children(session=session, parent_id=parent.id)
    return UsersPublic(data=children, count=len(children))
