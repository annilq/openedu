"""LangChainProvider 契约测试（T03）。

不触网：patch ChatOpenAI，验证
1) _build_model 把 settings 的 base_url/model/api_key 接线给模型（换厂商零业务改动）
2) 模型输出解析成 GeneratedQuestion 契约（字段齐全）
3) JSON 解析容错。
"""
import asyncio
from types import SimpleNamespace
from unittest.mock import patch

import pytest

from app.core.config import settings
from app.domain.langchain_provider import LangChainProvider
from app.domain.provider import GeneratedQuestion

_BASE_URL = "https://api.hunyuan.example.com/v1"
_MODEL = "test-model-v1"


@pytest.fixture()
def provider(monkeypatch):
    monkeypatch.setattr(settings, "LLM_PROVIDER", "langchain")
    monkeypatch.setattr(settings, "LLM_BASE_URL", _BASE_URL)
    monkeypatch.setattr(settings, "LLM_MODEL", _MODEL)
    monkeypatch.setattr(settings, "LLM_API_KEY", "sk-test")
    monkeypatch.setattr(settings, "LLM_TEMPERATURE", 0.2)
    return LangChainProvider()


class FakeModel:
    """模拟 ChatOpenAI 实例：记录构造参数，ainvoke 返回固定文本。"""

    def __init__(self, payload, **kwargs):
        self._payload = payload
        self.kwargs = kwargs

    async def ainvoke(self, messages):
        return SimpleNamespace(content=self._payload)


def _run_with(payload):
    """返回 (fake, patch)。调用方需在 with 作用域内执行 provider 调用。"""
    fake = FakeModel(payload)
    return fake, patch("langchain_openai.ChatOpenAI", return_value=fake)


# —— _build_model 接线 ——


def test_build_model_uses_settings_config(provider):
    fake, mock_patch = _run_with("{}")
    with mock_patch as mock_cls:
        provider._build_model()
    assert mock_cls.call_args.kwargs["base_url"] == _BASE_URL
    assert mock_cls.call_args.kwargs["model"] == _MODEL
    assert mock_cls.call_args.kwargs["api_key"] == "sk-test"
    assert mock_cls.call_args.kwargs["temperature"] == 0.2


def test_empty_api_key_falls_back_to_placeholder(monkeypatch):
    monkeypatch.setattr(settings, "LLM_PROVIDER", "langchain")
    monkeypatch.setattr(settings, "LLM_BASE_URL", _BASE_URL)
    monkeypatch.setattr(settings, "LLM_MODEL", _MODEL)
    monkeypatch.setattr(settings, "LLM_API_KEY", "")
    provider = LangChainProvider()
    fake, mock_patch = _run_with("{}")
    with mock_patch as mock_cls:
        provider._build_model()
    assert mock_cls.call_args.kwargs["api_key"] == "none"


def test_deepseek_preset_uses_deepseek_settings(monkeypatch):
    """LLM_PROVIDER=deepseek 时 _build_model 从 DEEPSEEK_* 取值（快捷预设）。"""
    monkeypatch.setattr(settings, "LLM_PROVIDER", "deepseek")
    monkeypatch.setattr(settings, "DEEPSEEK_BASE_URL", "https://api.deepseek.com")
    monkeypatch.setattr(settings, "DEEPSEEK_MODEL", "deepseek-chat")
    monkeypatch.setattr(settings, "DEEPSEEK_API_KEY", "sk-deepseek")
    provider = LangChainProvider()
    fake, mock_patch = _run_with("{}")
    with mock_patch as mock_cls:
        provider._build_model()
    assert mock_cls.call_args.kwargs["base_url"] == "https://api.deepseek.com"
    assert mock_cls.call_args.kwargs["model"] == "deepseek-chat"
    assert mock_cls.call_args.kwargs["api_key"] == "sk-deepseek"
    assert mock_cls.call_args.kwargs["temperature"] == settings.LLM_TEMPERATURE


# —— generate_question 契约 ——


def test_generate_question_contract_fields(provider):
    payload = (
        '{"stem": "2 + 3 = ?", "options": ["4", "5", "6"], '
        '"answer": "5", "explanation": "2+3=5。"}'
    )
    fake, mock_patch = _run_with(payload)

    with mock_patch:
        question = asyncio.run(
            provider.generate_question(
                subject="数学",
                grade=2,
                knowledge_point="加法",
                qtype="choice",
                difficulty="easy",
            )
        )

    assert isinstance(question, GeneratedQuestion)
    # 透传字段
    assert question.subject == "数学"
    assert question.grade == 2
    assert question.knowledge_point == "加法"
    assert question.qtype == "choice"
    assert question.difficulty == "easy"
    # 模型字段
    assert question.stem == "2 + 3 = ?"
    assert question.options == ["4", "5", "6"]
    assert question.answer == "5"
    assert question.explanation == "2+3=5。"


def test_generate_question_missing_fields_never_crash(provider):
    fake, mock_patch = _run_with('{"stem": "只有题干"}')
    with mock_patch:
        question = asyncio.run(
            provider.generate_question(
                subject="数学", grade=3, knowledge_point="乘法", qtype="fill", difficulty="medium"
            )
        )
    assert question.answer == ""
    assert question.explanation == ""
    assert question.options is None


# —— grade_open ——


def test_grade_open_parses_result(provider):
    fake, mock_patch = _run_with('{"correct": true, "score": 1.0, "explanation": "正确"}')
    with mock_patch:
        result = asyncio.run(
            provider.grade_open(question=SimpleNamespace(stem="题目"), student_answer="作答")
        )
    assert result == {"correct": True, "score": 1.0, "explanation": "正确"}


# —— JSON 解析容错 ——


def test_parse_json_handles_markdown_fence():
    content = '```json\n{"stem": "x"}\n```'
    assert LangChainProvider._parse_json(content) == {"stem": "x"}


def test_parse_json_handles_trailing_text():
    assert LangChainProvider._parse_json('好的，题目如下：{"answer": "1"} 完毕') == {
        "answer": "1"
    }


def test_parse_json_returns_empty_on_garbage():
    assert LangChainProvider._parse_json("这不是 JSON") == {}
    assert LangChainProvider._parse_json(None) == {}
