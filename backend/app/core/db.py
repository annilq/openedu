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
    - user 表补 interests 列（兴趣画像，WF-1/WF-2）；task 表补 focus_interest 列（兴趣题模式，WF-4）。
    - 回填：通过 task_question -> task 找到原题归属家长；孤儿行保持 NULL
      （作用域查询会排除，dev 期可 rm app.db 重置）。
    """
    with engine.begin() as conn:
        is_sqlite = engine.dialect.name == "sqlite"

        # —— question.parent_id ——（既有迁移，保留）
        if is_sqlite:
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

        # —— user.interests（JSON）——（WF-2）
        if is_sqlite:
            user_cols = [
                r[1] for r in conn.execute(text('PRAGMA table_info("user")')).fetchall()
            ]
            if "interests" not in user_cols:
                conn.execute(text('ALTER TABLE "user" ADD COLUMN interests TEXT'))
        else:
            conn.execute(
                text('ALTER TABLE "user" ADD COLUMN IF NOT EXISTS interests JSON')
            )

        # —— task.focus_interest（JSON）——（WF-4）
        if is_sqlite:
            task_cols = [
                r[1] for r in conn.execute(text("PRAGMA table_info(task)")).fetchall()
            ]
            if "focus_interest" not in task_cols:
                conn.execute(text("ALTER TABLE task ADD COLUMN focus_interest TEXT"))
        else:
            conn.execute(
                text("ALTER TABLE task ADD COLUMN IF NOT EXISTS focus_interest JSON")
            )


def init_db() -> None:
    # 确保模型已注册后再建表（详见 SQLModel 关系初始化注意事项）
    import app.models  # noqa: F401

    SQLModel.metadata.create_all(engine)
    run_migrations()
