# 语义事件流式转帧（translate_stream）

agent_core 产出「语义事件」（出题域 `ReasoningDelta / QuestionCard / QuestionFailed`），经 `translate_stream` 转译为前端 SSE 帧（ADR-0025）。该转换属教育集成层，不进 agent_core；加新语义事件 = 在 `to_frames` 的 `match` 加分支，不动 SSE 协议。

- **转换落点**：`app.ai.subagents.question.translate.translate_stream`，纯转换 + 思维链聚合，SubAgent 只写 `async for frame in translate_stream(stream): yield frame`（`backend/app/ai/subagents/question/translate.py:1-13,53-71`）。
- **语义事件 → 帧映射**：`to_frames` 中 `ReasoningDelta→THINKING`、`QuestionCard→DATA(extra.type=question)`、`QuestionFailed→STEP(status=error)`，未知类型显式抛错不静默丢弃（`backend/app/ai/subagents/question/translate.py:37-50`）。
- **推理增量按字符攒批**：`_COALESCE_CHARS=16`，THINKING 帧文本入 `buf`，满阈值或遇他帧 / 流结束才冲刷，帧数降一量级而打字机观感不变（`backend/app/ai/subagents/question/translate.py:34,60-71`）。
- **管线上游证据**：provider 流（`TextDelta`/`StructuredDone`）→ 语义事件，逐段 `ReasoningDelta` 拼接一致；无增量则取结构化 `reasoning`（`backend/tests/ai/test_generate_question_stream.py:1-9,97-116`）。
- **攒批效果证据**：每题 2 个推理增量（15 字 < 阈值）合并为 1 帧，THINKING 帧数少于语义事件数（`backend/tests/ai/test_question_subagent_stream.py:7-8,112-113`）。

**Consequences**：语义事件与线协议解耦，出题逻辑只产语义、转换层统管帧结构；字符攒批避免数百 THINKING 帧拖垮前端 setState，同时保留连续打字机效果。
