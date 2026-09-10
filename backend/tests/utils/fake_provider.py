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
- ``tools``：按**工具脚本**逐跳发 ``ToolCall``，脚本走完后给收尾文本；
- 纯文本：直接产出讲解文本。

## 工具脚本（多轮 tool loop，ADR-0033 第 6 阶段）

``tool_script`` 是「模型每一跳选哪个工具、带什么入参」的显式声明：第 N 跳取第 N 项，
用完即收尾（不再请求工具）。不传脚本＝默认单跳（每轮取下发工具列表的第一个）——保留
原有行为，避免既有用例无谓改动。

跳数**由 history 中 ``role == "tool"`` 的条目数推断**（即已完成几次工具执行），而不是
「history 非空就收尾」：后者会让客户端自带的历史（``/assistant/chat`` 的 ``history``
字段，全是 user/assistant 轮次、无工具结果）把首轮工具调用吃掉，使「多轮上下文 + 查询」
组合静默退化——那是替身的失真，不是实现的缺陷。
"""
from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from agent_core.ports import StructuredDone, TextDelta, ToolCall
from app.domain.provider import EducationLLMProvider

# 固定讲解文本（须与安全词表无交集，保证 check_output 放行）。
_TUTOR_TEMPLATE = "这道题我们一步步来：先看清题目给的条件，再选合适的方法计算，最后检查一遍。答案是 68。"

# 工具脚本跑完后的收尾文本（可被 ``tool_text`` 覆盖）。
_TOOL_TEMPLATE = "已为你列出任务。"

# 出题固定题面（只含题面四要素；subject/grade 等由 spec 回填）。
_FAKE_QUESTION: dict = {
    "stem": "这是一道测试题的题干，用于测试替身产出。",
    "options": ["A. 第一个选项", "B. 第二个选项", "C. 第三个选项", "D. 第四个选项"],
    "answer": "B",
    "explanation": "把条件代入概念逐步推导即可得出结论。",
}

# 出题固定推理（随题卡整体到达）。
_REASONING = "先确认考查点，再设计干扰项与答案，难度与年级匹配。"

# 一跳工具调用：``(工具名, 入参)``；也接受裸字符串（等价于空入参）。
ToolStep = tuple[str, dict[str, Any]]


def _normalize_script(steps: Sequence[ToolStep | str] | None) -> list[ToolStep] | None:
    if steps is None:
        return None
    out: list[ToolStep] = []
    for step in steps:
        if isinstance(step, str):
            out.append((step, {}))
        else:
            name, args = step
            out.append((str(name), dict(args or {})))
    return out


def _tool_name_of(entry: Any) -> str | None:
    """从下发的工具声明里取名字（dict 或 ``ToolSpec`` 两种形态）。"""
    name = entry.get("name") if isinstance(entry, dict) else getattr(entry, "name", None)
    return str(name) if name else None


def _completed_hops(history: list[dict] | None) -> int:
    """已完成的工具跳数＝history 中工具结果条目数（回灌一条＝跑完一跳）。

    只认 ``role == "tool"``（runtime 的回灌契约），不把 user/assistant 轮次算进跳数。
    """
    if not isinstance(history, list):
        return 0
    return sum(1 for h in history if isinstance(h, dict) and h.get("role") == "tool")


class FakeLLMProvider(EducationLLMProvider):
    """确定性 LLM 替身：同样的入参永远得到同样的产出（工具脚本可控）。"""

    def __init__(
        self,
        *,
        tool_script: Sequence[ToolStep | str] | None = None,
        tool_text: str | None = None,
    ) -> None:
        self._script = _normalize_script(tool_script)
        self.tool_text = tool_text or _TOOL_TEMPLATE
        # 可观测（断言用）：requests＝被请求次数；calls＝实际发出的工具调用序列。
        self.requests = 0
        self.calls: list[ToolStep] = []

    # ── 脚本控制：端点/集成测试可在 fixture 交出的实例上就地改写 ──
    def script(self, *steps: ToolStep | str) -> "FakeLLMProvider":
        """声明工具脚本（``"list_children"`` 或 ``("list_children", {...})``），并清空计数。"""
        self._script = _normalize_script(steps)
        return self.reset()

    def reset(self) -> "FakeLLMProvider":
        self.requests = 0
        self.calls = []
        return self

    # ── 本轮该发什么 ──
    def _next_step(self, hop: int, tools: Sequence[Any]) -> ToolStep | None:
        if self._script is None:
            # 默认单跳：只在第一跳请求「下发列表的第一个工具」（保持既有行为）。
            if hop != 0:
                return None
            first = _tool_name_of(tools[0]) if tools else None
            return (first, {}) if first else None
        return self._script[hop] if hop < len(self._script) else None

    async def stream(self, system, prompt, *, schema=None, tools=None, history=None):
        if tools:
            self.requests += 1
            step = self._next_step(_completed_hops(history), tools)
            if step is None:
                yield TextDelta(delta=self.tool_text)
                return
            name, args = step
            self.calls.append((name, args))
            yield ToolCall(name=name, args=dict(args))
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


__all__ = ["FakeLLMProvider", "ToolStep"]
