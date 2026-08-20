from datetime import timedelta

from fastapi import APIRouter, HTTPException

from app.api.deps import CurrentUser, SessionDep
from app.core.config import settings
from app.core.security import create_access_token
from app.crud import authenticate, create_user, get_user_by_username
from app.models import LoginRequest, Token, UserCreate, UserPublic

router = APIRouter(prefix="/auth", tags=["auth"])


def _token_for(user) -> Token:
    access_token = create_access_token(
        user.id,
        expires_delta=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    return Token(access_token=access_token)


@router.post("/register", response_model=Token)
def register(*, session: SessionDep, user_in: UserCreate) -> Token:
    if get_user_by_username(session=session, username=user_in.username):
        raise HTTPException(status_code=400, detail="Username already registered")
    user = create_user(session=session, user_create=user_in, role="parent")
    return _token_for(user)


@router.post("/login", response_model=Token)
def login(*, session: SessionDep, credentials: LoginRequest) -> Token:
    user = authenticate(
        session=session, username=credentials.username, password=credentials.password
    )
    if not user:
        raise HTTPException(status_code=401, detail="Incorrect username or password")
    return _token_for(user)


@router.get("/me", response_model=UserPublic)
def me(current_user: CurrentUser) -> UserPublic:
    """前端登录后用 token 调此端点获取当前用户信息（含 role/grade）。"""
    return UserPublic.model_validate(current_user)
