"""AI 伴学答疑编排服务（F-302 适龄讲解 + F-304 内容安全）。

组装顺序：输入安全校验 → 调用 provider 讲解 → 输出安全校验。
仅同步封装（与 Grader 一致）：内部用 asyncio.run 驱动 provider 的 async 方法，
由 FastAPI 同步路由在独立线程中调用，无事件循环冲突。
"""

import asyncio
from dataclasses import dataclass

from app.domain.provider import LLMProvider
from app.domain.safety import SAFE_REFUSAL, check_input, check_output


@dataclass
class TutorResult:
    answer: str
    input_safe: bool
    output_safe: bool
    blocked: bool  # True 表示因安全原因返回兜底（未调用/未采用模型输出）
    reason: str | None = None


class TutorService:
    def __init__(self, provider: LLMProvider) -> None:
        self.provider = provider

    def explain(
        self,
        *,
        grade: int,
        subject: str,
        knowledge_point: str,
        context: str | None,
        question: str,
    ) -> TutorResult:
        # 1) 输入安全校验（越狱 / 非学习类主题）
        # 对所有娃娃可输入字段统一校验，避免越狱指令从知识点/上下文绕过年龄锁
        combined = "\n".join(
            p for p in (question, knowledge_point, context) if p
        )
        inp = check_input(combined)
        if not inp.safe:
            return TutorResult(
                answer=SAFE_REFUSAL,
                input_safe=False,
                output_safe=True,
                blocked=True,
                reason=inp.reason,
            )

        # 2) 调用模型（provider 内部已注入年龄锁系统提示）
        raw = asyncio.run(
            self.provider.tutor(
                grade=grade,
                subject=subject,
                knowledge_point=knowledge_point,
                context=context,
                question=question,
            )
        )

        # 3) 输出安全校验（敏感词）
        out = check_output(raw)
        if not out.safe:
            return TutorResult(
                answer=SAFE_REFUSAL,
                input_safe=True,
                output_safe=False,
                blocked=True,
                reason=out.reason,
            )

        return TutorResult(
            answer=raw,
            input_safe=True,
            output_safe=True,
            blocked=False,
            reason=None,
        )


__all__ = ["TutorService", "TutorResult"]
