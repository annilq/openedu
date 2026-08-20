"""Provider 工厂选择逻辑单测（T03）。

覆盖：mock 默认、langchain 显式、deepseek 快捷预设、未知值回退、缺配置报错。
"""
import pytest

from app.core.config import settings
from app.domain import build_provider
from app.domain.langchain_provider import LangChainProvider
from app.domain.mock_provider import MockProvider


@pytest.fixture()
def llm_settings(monkeypatch):
    """将 LLM 相关配置恢复为可控基线。"""

    def _set(**kwargs):
        for key, value in {
            "LLM_PROVIDER": "mock",
            "LLM_BASE_URL": "",
            "LLM_MODEL": "",
            "LLM_API_KEY": "",
            "DEEPSEEK_API_KEY": "",
            **kwargs,
        }.items():
            monkeypatch.setattr(settings, key, value)

    return _set


def test_default_is_mock(llm_settings):
    llm_settings()
    assert isinstance(build_provider(), MockProvider)


def test_langchain_explicit(llm_settings):
    llm_settings(
        LLM_PROVIDER="langchain",
        LLM_BASE_URL="https://api.example.com/v1",
        LLM_MODEL="test-model",
    )
    assert isinstance(build_provider(), LangChainProvider)


def test_unknown_value_falls_back_to_mock(llm_settings):
    llm_settings(LLM_PROVIDER="not-a-real-provider")
    with pytest.warns(UserWarning, match="回退到 mock"):
        assert isinstance(build_provider(), MockProvider)


def test_deepseek_explicit(llm_settings):
    llm_settings(LLM_PROVIDER="deepseek", DEEPSEEK_API_KEY="sk-test")
    assert isinstance(build_provider(), LangChainProvider)


def test_deepseek_without_key_raises(llm_settings):
    """显式选了 deepseek 但没配 key，启动即失败，避免线上静默降级。"""
    llm_settings(LLM_PROVIDER="deepseek", DEEPSEEK_API_KEY="")
    with pytest.raises(RuntimeError, match="DEEPSEEK_API_KEY"):
        build_provider()


def test_langchain_without_config_raises(llm_settings):
    """显式选了 langchain 但没配端点，启动即失败，避免线上静默降级。"""
    llm_settings(LLM_PROVIDER="langchain", LLM_BASE_URL="", LLM_MODEL="")
    with pytest.raises(RuntimeError, match="LLM_BASE_URL"):
        build_provider()
