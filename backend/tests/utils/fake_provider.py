"""测试专用确定性 LLM 替身（test double）。

背景：生产侧已**移除 mock 兜底**——未配置真实引擎时出题 / 答疑返回 None、批改抛错
（见 ``app/domain/genkit_provider.py``），需 ``LLM_PROVIDER`` + key 才能跑通 AI 闭环。

但**测试不得依赖真实模型**：本地 ``.env`` 配了 key 时走真实调用，CI（无 key）走
``mock``，同一份代码两处行为分叉，出题/答疑断言随环境随机红（本次 CI 两条红线即因此）。
本替身把「模型产出」这一不确定性来源钉死为固定文本 / 固定题卡，使：

- 断言确定性（不因模型温度/版本漂移而红）；
- 零网络、零费用、秒级；
- 真实模型连通性由 ``tests/domain/test_llm_smoke.py -m smoke`` 单独负责。

替身实现 agent_core 消息级 ``LLMProvider.stream``（schema / tools / 纯文本三态）：
- ``schema``：产出推理 + 末帧 ``StructuredDone(data=题面字典)``，供出题 SubAgent 解析成题卡；
- ``tools``：首轮发 ``ToolCall``，工具回灌后再请求时给收尾文本（避免 tool loop 死循环）；
- 纯文本：直接产出讲解文本。
"""
from __future__ import annotations

from agent_core.seams import StructuredDone, TextDelta, ToolCall
from app.domain.provider import EducationLLMProvider

# 固定讲解文本（须与安全词表无交集，保证 check_output 放行）。
_TUTOR_TEMPLATE = "这道题我们一步步来：先看清题目给的条件，再选合适的方法计算，最后检查一遍。答案是 68。"

# 出题固定题面（只含题面四要素；subject/grade 等由 spec 回填）。
_FAKE_QUESTION: dict = {
    "stem": "这是一道测试题的题干，用于测试替身产出。",
    "options": ["A. 第一个选项", "B. 第二个选项", "C. 第三个选项", "D. 第四个选项"],
    "answer": "B",
    "explanation": "把条件代入概念逐步推导即可得出结论。",
}

# 出题固定推理（随题卡整体到达）。
_REASONING = "先确认考查点，再设计干扰项与答案，难度与年级匹配。"


class FakeLLMProvider(EducationLLMProvider):
    """确定性 LLM 替身：同样的入参永远得到同样的产出。"""

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if tools:
            # 首轮（history 尚无工具回灌）→ 发 ToolCall；回灌后再请求 → 收尾文本。
            if history:
                yield TextDelta(delta="已为你列出任务。")
                return
            for t in tools:
                name = t.get("name") if isinstance(t, dict) else getattr(t, "name", None)
                if name:
                    yield ToolCall(name=name, args={})
                    return
            yield TextDelta(delta="已处理")
            return
        if schema is not None:
            yield TextDelta(delta=_REASONING)
            yield StructuredDone(data=dict(_FAKE_QUESTION))
            return
        yield TextDelta(delta=_TUTOR_TEMPLATE)

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
