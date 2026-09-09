from fastapi import APIRouter

from app.core.deps import CurrentUser, SessionDep
from app.core.errors import AppErrorException, ErrCode
from app.features.auth.repository import authenticate, create_user, get_user_by_username
from app.features.auth.schemas import LoginRequest, Token, UserCreate, UserPublic
from app.features.auth.service import create_token_for

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=Token)
def register(*, session: SessionDep, user_in: UserCreate) -> Token:
    if get_user_by_username(session=session, username=user_in.username):
        raise AppErrorException(ErrCode.AUTH_USERNAME_TAKEN, "用户名已注册")
    user = create_user(session=session, user_create=user_in, role="parent")
    return create_token_for(user)


@router.post("/login", response_model=Token)
def login(*, session: SessionDep, credentials: LoginRequest) -> Token:
    user = authenticate(
        session=session, username=credentials.username, password=credentials.password
    )
    if not user:
        raise AppErrorException(
            ErrCode.AUTH_BAD_CREDENTIALS, "账号或密码错误"
        )
    return create_token_for(user)


@router.get("/me", response_model=UserPublic)
def me(current_user: CurrentUser) -> UserPublic:
    """前端登录后用 token 调此端点获取当前用户信息（含 role/grade）。"""
    return UserPublic.model_validate(current_user)
