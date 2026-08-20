from sqlmodel import SQLModel, create_engine

from app.core.config import settings

_connect_args = (
    {"check_same_thread": False}
    if str(settings.DATABASE_URL).startswith("sqlite")
    else {}
)

engine = create_engine(str(settings.DATABASE_URL), connect_args=_connect_args)


def init_db() -> None:
    # 确保模型已注册后再建表（详见 SQLModel 关系初始化注意事项）
    import app.models  # noqa: F401

    SQLModel.metadata.create_all(engine)
