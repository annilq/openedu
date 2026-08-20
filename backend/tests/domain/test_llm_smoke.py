"""真实大模型连通 smoke（T03）。

仅在显式开启时运行：
    LLM_PROVIDER=langchain LLM_API_KEY=sk-xxx LLM_BASE_URL=... LLM_MODEL=... \
        uv run pytest tests/domain/test_llm_smoke.py -m smoke -v
    # 或 DeepSeek 快捷预设：
    LLM_PROVIDER=deepseek RUN_LLM_SMOKE=1 \
        uv run pytest tests/domain/test_llm_smoke.py -m smoke -v

验证：QuestionGenerator 经真实模型出题、业务代码零改动、结果符合 GeneratedQuestion 契约。
"""
import os

import pytest

from app.core.config import settings
from app.domain import build_provider
from app.domain.langchain_provider import LangChainProvider
from app.domain.provider import GeneratedQuestion
from app.domain.question_generator import QuestionGenerator

_smoke_enabled = (
    settings.LLM_PROVIDER == "deepseek"
    and bool(settings.DEEPSEEK_API_KEY)
    and os.environ.get("RUN_LLM_SMOKE") == "1"
) or (
    settings.LLM_PROVIDER == "langchain"
    and bool(settings.LLM_API_KEY)
    and os.environ.get("RUN_LLM_SMOKE") == "1"
)

pytestmark = [
    pytest.mark.smoke,
    pytest.mark.skipif(
        not _smoke_enabled,
        reason="需要 LLM_PROVIDER=langchain+LLM_API_KEY 或 deepseek+DEEPSEEK_API_KEY，并设 RUN_LLM_SMOKE=1",
    ),
]


def test_question_generator_uses_real_model_without_business_change():
    """业务层只依赖 build_provider()，切真实模型不改任何业务代码。"""
    provider = build_provider()
    assert isinstance(provider, LangChainProvider)

    generator = QuestionGenerator(provider)
    question = generator.generate(
        subject="数学",
        grade=2,
        knowledge_point="两位数加法",
        qtype="calc",
        difficulty="easy",
    )

    assert isinstance(question, GeneratedQuestion)
    for field in (
        "subject",
        "grade",
        "knowledge_point",
        "qtype",
        "stem",
        "options",
        "answer",
        "explanation",
        "difficulty",
    ):
        assert getattr(question, field) is not None, f"契约字段缺失: {field}"
    assert question.stem.strip(), "真实模型未返回题干"
    assert question.answer.strip(), "真实模型未返回答案"
    # 返回的题目必须适配当前学科/年级/知识点请求
    assert question.subject == "数学"
    assert question.grade == 2
    assert question.qtype == "calc"
