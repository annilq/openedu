from fastapi import APIRouter, HTTPException, status

from app.api.deps import CurrentParent, SessionDep
from app.crud import create_user, get_user_by_username, list_children
from app.models import UserCreate, UserPublic, UsersPublic

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


@router.get("", response_model=UsersPublic)
def get_children(*, session: SessionDep, parent: CurrentParent) -> UsersPublic:
    children = list_children(session=session, parent_id=parent.id)
    return UsersPublic(data=children, count=len(children))
