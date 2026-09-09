"""Auth feature service helpers (token issuance)."""

from datetime import timedelta

from app.core.config import settings
from app.core.security import create_access_token
from app.features.auth.schemas import Token


def create_token_for(user) -> Token:
    """为已认证用户签发 JWT 访问令牌。"""
    access_token = create_access_token(
        user.id,
        expires_delta=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    return Token(access_token=access_token)
