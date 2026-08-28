from sqlalchemy import text
from sqlalchemy.exc import OperationalError

from sqlmodel import SQLModel, create_engine

from app.core.config import settings

_connect_args = (
    {"check_same_thread": False}
    if str(settings.DATABASE_URL).startswith("sqlite")
    else {}
)

engine = create_engine(str(settings.DATABASE_URL), connect_args=_connect_args)


def run_migrations() -> None:
    """无 Alembic：启动期轻量迁移。

    - question 表补 parent_id 列（owner 隔离，题库复用闭环）。
    - 回填：通过 task_question -> task 找到原题归属家长；孤儿行保持 NULL
      （作用域查询会排除，dev 期可 rm app.db 重置）。
    """
    with engine.begin() as conn:
        if engine.dialect.name == "sqlite":
            cols = [r[1] for r in conn.execute(text("PRAGMA table_info(question)")).fetchall()]
            if "parent_id" not in cols:
                conn.execute(text("ALTER TABLE question ADD COLUMN parent_id VARCHAR(36)"))
        else:  # postgres
            conn.execute(
                text("ALTER TABLE question ADD COLUMN IF NOT EXISTS parent_id UUID")
            )
        # 回填：通过 task_question -> task 找到原题归属家长；孤儿行保持 NULL。
        # 旧库若尚未建 task_question 表（偏序迁移），跳过回填（owner 隔离降级，dev 可重置）。
        try:
            conn.execute(
                text(
                    """
                    UPDATE question SET parent_id = (
                        SELECT t.parent_id FROM task_question tq
                        JOIN task t ON t.id = tq.task_id
                        WHERE tq.question_id = question.id LIMIT 1
                    ) WHERE parent_id IS NULL
                    """
                )
            )
        except OperationalError:
            pass  # 偏序迁移：task_question 不存在，回填降级


def init_db() -> None:
    # 确保模型已注册后再建表（详见 SQLModel 关系初始化注意事项）
    import app.models  # noqa: F401

    SQLModel.metadata.create_all(engine)
    run_migrations()
