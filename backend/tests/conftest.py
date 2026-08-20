import os
from collections.abc import Generator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, delete

# 测试强制使用独立临时库：避免本地 app.db 旧 schema 影响（无迁移流程，表结构演进靠重建）
_TEST_DB = Path(__file__).resolve().parent.parent / "test_app.db"
os.environ["DATABASE_URL"] = f"sqlite:///{_TEST_DB}"
_TEST_DB.unlink(missing_ok=True)

from app.core.db import engine, init_db  # noqa: E402
from app.main import app  # noqa: E402
from app.models import (  # noqa: E402
    AnswerRecord,
    Checkin,
    Question,
    Task,
    User,
    WrongQuestion,
)


@pytest.fixture(scope="session", autouse=True)
def db() -> Generator[Session]:
    init_db()
    with Session(engine) as session:
        yield session
        for model in (AnswerRecord, Checkin, WrongQuestion, Question, Task, User):
            session.execute(delete(model))
        session.commit()


@pytest.fixture()
def client() -> Generator[TestClient]:
    with TestClient(app) as c:
        yield c
