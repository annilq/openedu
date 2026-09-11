# 遗忘曲线调度与出题推理揭示

错题复习按阶段递增间隔调度，出题过程以打字机式推理文本营造连续感（原 ADR-0017）。

- **间隔重复阶段制**：`review_scheduler.py` 用阶段 0..4、间隔 1/2/4/7/15 天调度（`review` feature）；末位阶段答对即毕业、从错题本移除。
- **出题推理打字机**：`reasoning_typewriter.dart` 把推理文本逐字揭示，营造「AI 正在思考出题」的连续感；推理仅预览态展示、不落库（`frontend/.../models.dart:186`）。
- **出题流式协议**：单调用流式——先发 `STEP` 进度锚点，模型推理逐 token 转 `THINKING` 增量，JSON 解析 + 安全闸门通过后发 `DATA` 题卡（`backend/app/ai/subagents/question/agent.py:8`）。
- **原生思维链升级路径**：`ai/engine.py` 检测 DeepSeek-R1 / o-series / QwQ 等具备原生 CoT 的模型，直接转发提供方 `REASONING` 增量（`:33`）。

**Consequences**：推理文本在「生成中」阶段必须持续可见而非闪现（已在 `parent_task_form_view.dart:757` 落地，题卡落定后持久显示），否则用户感知不到 AI 在思考——这正是你之前排查的 streaming 缺陷的约束来源。
