"""测试专用确定性 LLM 替身（test double）。

背景：生产侧已**移除 mock 兜底**——未配置真实引擎时出题 / 答疑返回 None、批改抛错
（见 ``app/domain/genkit_provider.py``），需 ``LLM_PROVIDER`` + key 才能跑通 AI 闭环。

但**测试不得依赖真实模型**：本地 ``.env`` 配了 key 时走真实调用，CI（无 key）走
``mock``，同一份代码两处行为分叉，出题/答疑断言随环境随机红（本次 CI 两条红线即因此）。
本替身把「模型产出」这一不确定性来源钉死为固定文本 / 固定题卡，使：

- 断言确定性（不因模型温度/版本漂移而红）；
- 零网络、零费用、秒级；
- 真实模型连通性由 ``tests/domain/test_llm_smoke.py -m smoke`` 单独负责。

替身只实现 ``LLMProvider`` 契约，产出形状与真实 ``GenkitProvider`` 一致：
出题流式 = ``ReasoningDelta`` 增量 + ``QuestionCard`` 成品卡。
"""
from __future__ import annotations

from collections.abc import AsyncIterator

from app.domain.provider import (
    GeneratedQuestion,
    LLMProvider,
    QuestionCard,
    QuestionStreamEvent,
    ReasoningDelta,
)

# 固定讲解文本（须与安全词表无交集，保证 check_output 放行）。
_TUTOR_TEMPLATE = "这道题我们一步步来：先看清题目给的条件，再选合适的方法计算，最后检查一遍。答案是 68。"


def _options(qtype: str) -> list[str] | None:
    if qtype != "choice":
        return None
    return ["A. 第一个选项", "B. 第二个选项", "C. 第三个选项", "D. 第四个选项"]


def _stem(subject: str, grade: int, knowledge_point: str, qtype: str) -> str:
    kp = knowledge_point or "本节知识点"
    return f"【{grade}年级{subject}·{kp}】这是一道{qtype}题的题干，用于测试替身产出。"


def _card(
    *,
    subject: str,
    grade: int,
    knowledge_point: str,
    qtype: str,
    difficulty: str,
) -> GeneratedQuestion:
    return GeneratedQuestion(
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point or "本节知识点",
        qtype=qtype,
        stem=_stem(subject, grade, knowledge_point, qtype),
        options=_options(qtype),
        answer="B",
        explanation="把条件代入概念逐步推导即可得出结论。",
        difficulty=difficulty,
    )


class FakeLLMProvider(LLMProvider):
    """确定性 LLM 替身：同样的入参永远得到同样的产出。"""

    async def generate_question(
        self,
        *,
        system_prompt: str,
        user_prompt: str,
        spec,
        history: list[dict] | None = None,
    ) -> GeneratedQuestion:
        return _card(
            subject=spec.subject,
            grade=spec.grade,
            knowledge_point=spec.knowledge_point,
            qtype=spec.qtype,
            difficulty=spec.difficulty,
        )

    async def generate_question_stream(
        self,
        *,
        system_prompt: str,
        user_prompt: str,
        spec,
        history: list[dict] | None = None,
    ) -> AsyncIterator[QuestionStreamEvent]:
        # 与真实流式同样的事件序列：先推理增量，再成品题卡（单次调用 = 一道题）。
        yield ReasoningDelta(
            delta=f"先确认{spec.grade}年级{spec.subject}的考查点，再设计干扰项与答案，难度控制在{spec.difficulty}。"
        )
        yield QuestionCard(
            question=_card(
                subject=spec.subject,
                grade=spec.grade,
                knowledge_point=spec.knowledge_point,
                qtype=spec.qtype,
                difficulty=spec.difficulty,
            ),
            reasoning="情境取自教材例题，干扰项覆盖常见误算，难度与年级匹配。",
        )

    async def grade_open(self, *, question, student_answer) -> dict:
        return {
            "correct": True,
            "score": 1.0,
            "explanation": "思路正确，结论无误。",
        }

    async def tutor(
        self,
        *,
        grade,
        subject,
        knowledge_point,
        context,
        question,
        history: list[dict] | None = None,
    ) -> str:
        return _TUTOR_TEMPLATE


__all__ = ["FakeLLMProvider"]
