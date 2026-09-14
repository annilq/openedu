# 出题推理打字机流式揭示

出题推理过程以打字机流式逐步揭示，仅预览态展示、不落库；该决策与 ADR-0005 互补——ADR-0005 主体为遗忘曲线调度并顺带提及出题推理打字机，本 ADR 将「出题推理流式揭示、仅预览不落库」独立成文。

- **仅预览态、不落库**：`QuestionPreview.reasoning` 承载出题推理过程，仅在预览卡展示、不落库；旧服务端不下发时为空字符串兜底（`frontend/lib/shared/domain/models/models.dart:186`、`:199`）。
- **打字机揭示**：前端 `reasoning_typewriter.dart` 逐字揭示推理文本，营造「AI 正在思考出题」的连续感；也是「生成任务闪现」缺陷的约束来源（`docs/agents/architecture.md:106`）。
- **原生思维链升级路径**：`EngineResolution.supports_reasoning` 检测 DeepSeek-R1 / o-series / QwQ 等原生 CoT 模型，直接转发提供方 `REASONING` 增量；否则走单次调用 + 结构化 `reasoning` 字段打底，由前端打字机揭示（`backend/app/ai/engine.py:37`、`:40`）。

**Considered Options**：① 出题结果一次性返回（无连续感、暴露闪现缺陷，拒绝）；② 推理以打字机流式逐步揭示、仅预览态（采用）。

**Consequences**：用户在「生成中」能持续看到 AI 推理而非题卡闪现；推理文本不持久化，避免把模型中间产物写进题库。代价是前端须保证打字机组件与 SSE 帧持续可见。
