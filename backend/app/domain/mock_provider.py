import hashlib
import random

from app.domain.provider import GeneratedQuestion, LLMProvider


class MockProvider(LLMProvider):
    """无外部依赖的兜底实现：无需模型 key 即可跑通完整闭环。"""

    async def generate_question(
        self, *, subject, grade, knowledge_point, qtype, difficulty
    ) -> GeneratedQuestion:
        seed = int(hashlib.sha256(f"{subject}{grade}{knowledge_point}{qtype}".encode()).hexdigest(), 16)
        rng = random.Random(seed)
        if qtype == "choice":
            correct = rng.randint(0, 3)
            options = ["A", "B", "C", "D"]
            answer = options[correct]
            stem = f"【{subject}】{knowledge_point} 的正确答案是什么？(难度 {difficulty})"
            explanation = f"根据{knowledge_point}的定义，正确答案是 {answer}。"
        elif qtype == "calc":
            a, b = rng.randint(1, 20), rng.randint(1, 20)
            answer = str(a + b)
            stem = f"计算：{a} + {b} = ?"
            explanation = f"{a} + {b} = {answer}。"
        elif qtype == "fill":
            answer = f"示例{grade}年级{knowledge_point}"
            stem = f"请根据“{knowledge_point}”填空。"
            explanation = f"应填写：{answer}。"
        else:  # open
            answer = f"关于{knowledge_point}的要点说明。"
            stem = f"请简述{knowledge_point}。"
            explanation = answer
        return GeneratedQuestion(
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            qtype=qtype,
            stem=stem,
            options=options if qtype == "choice" else None,
            answer=answer,
            explanation=explanation,
            difficulty=difficulty,
        )

    async def grade_open(self, *, question, student_answer) -> dict:
        # Mock 模式对开放题做简单包含判定
        correct = bool(student_answer) and any(
            kw in (student_answer or "") for kw in (question.knowledge_point,)
        )
        return {
            "correct": correct,
            "score": 1.0 if correct else 0.0,
            "explanation": question.explanation or "已收到作答。",
        }

    async def tutor(
        self, *, grade, subject, knowledge_point, context, question
    ) -> str:
        return (
            f"【{subject} · {grade}年级】关于“{knowledge_point}”：\n"
            f"你问的“{question}”，我们可以这样想——先回顾{knowledge_point}的定义，"
            f"再一步步分析。举例来说，{knowledge_point}常出现在{subject}的基础练习里，"
            f"多练几道就会啦！如果有具体题目，可以把题目发给我哦～"
        )
