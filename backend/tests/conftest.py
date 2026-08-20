from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, delete

from app.core.db import engine, init_db
from app.main import app
from app.models import AnswerRecord, Checkin, Question, Task, User, WrongQuestion


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
