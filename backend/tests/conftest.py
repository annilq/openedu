import os
from collections.abc import Generator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, delete

# 测试强制使用独立临时库：避免本地 app.db 旧 schema 影响（无迁移流程，表结构演进靠重建）
_TEST_DB = Path(__file__).resolve().parent.parent / "test_app.db"
os.environ["DATABASE_URL"] = f"sqlite:///{_TEST_DB}"
# 测试一律不接真实模型：本地 .env 常配了 deepseek key，会让同一份测试在本地与
# CI（无 key）行为分叉。LLM 产出统一由 fake_llm 夹具的确定性替身提供（见下）。
os.environ["LLM_PROVIDER"] = "mock"
_TEST_DB.unlink(missing_ok=True)

from app.core.db import engine, init_db  # noqa: E402
from app.db.models import (  # noqa: E402
    AnswerRecord,
    Checkin,
    ModelConfig,
    Question,
    Task,
    TutorLog,
    TutorQuota,
    TutorUsage,
    User,
    WrongQuestion,
)
from app.main import app  # noqa: E402
from tests.utils.fake_provider import FakeLLMProvider  # noqa: E402


@pytest.fixture(autouse=True)
def fake_llm(monkeypatch) -> FakeLLMProvider:
    """全套件注入确定性 LLM 替身：任何测试都不得真实调用模型。

    打桩点是 Agent Runtime 的 provider 工厂（``app.ai.runtime.runtime.build_provider``，
    该模块在 import 期就把名字绑进了自己的命名空间，故须就地打桩）。
    生产路径不受影响：真实模型仍由 ``GenkitProvider`` + ``resolve_engine`` 解析。

    ADR-0030：Runtime 会把解析好的引擎以 ``engine=`` 关键字注入工厂，替身签名须接受它
    （替身不需要引擎，忽略即可）。
    """
    provider = FakeLLMProvider()

    def _factory(engine=None):  # noqa: ARG001 — 替身忽略引擎，仅为匹配工厂签名
        return provider

    monkeypatch.setattr("app.ai.runtime.runtime.build_provider", _factory)
    return provider


@pytest.fixture(scope="session", autouse=True)
def db() -> Generator[Session]:
    init_db()
    with Session(engine) as session:
        yield session
        for model in (
            TutorUsage,
            TutorQuota,
            TutorLog,
            AnswerRecord,
            Checkin,
            WrongQuestion,
            ModelConfig,
            Question,
            Task,
            User,
        ):
            session.execute(delete(model))
        session.commit()


@pytest.fixture()
def client() -> Generator[TestClient]:
    with TestClient(app) as c:
        yield c
