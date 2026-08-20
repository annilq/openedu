import asyncio

from app.domain.provider import GeneratedQuestion, LLMProvider


class QuestionGenerator:
    """出题领域服务：薄封装，委托 provider 产出 GeneratedQuestion。"""

    def __init__(self, provider: LLMProvider) -> None:
        self.provider = provider

    def generate(
        self, *, subject, grade, knowledge_point, qtype, difficulty
    ) -> GeneratedQuestion:
        return asyncio.run(
            self.provider.generate_question(
                subject=subject,
                grade=grade,
                knowledge_point=knowledge_point,
                qtype=qtype,
                difficulty=difficulty,
            )
        )
