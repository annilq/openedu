"""Provider 工厂测试（迁移 08b）：统一单栈后 build_provider() 始终返回 GenkitProvider。"""
from __future__ import annotations

from app.domain import build_provider
from app.domain.genkit_provider import GenkitProvider


def test_build_provider_returns_genkit_provider():
    assert isinstance(build_provider(), GenkitProvider)
