# 悬浮助手 SSE 事件帧契约

服务端经 ADR-0024 端点以 SSE 逐帧推送 AG-UI 式事件，前端按 `eventType` 分发渲染。本 ADR 固定「帧类型与字段约定」这一线协议，与端点路由（ADR-0024）、意图收敛（ADR-0026）正交，前后端任一端改动帧结构须同步本协议。

- **事件类型常量（帧判别字段）**：`RUN_STARTED / USER_MESSAGE / THINKING / ASSISTANT_MESSAGE / TOOL_CALL / TOOL_RESULT / STEP / DATA / ERROR / DONE / RUN_FINISHED`，定义在 `agent_core.protocol`（`backend/agent_core/protocol.py:18-28`）。
- **统一信封字段**：`AssistantEvent` 以 `eventType` 判别，按类型选用 `text/delta`、`tool/label/args/result`、`status`、`data`、`message/code`、`session_id`、`blocked`、`extra`（`backend/agent_core/protocol.py:35-54`）。
- **线协议序列化**：`to_sse()` 产出 `data: {json}\n\n`，省略 None 字段保帧精简（`backend/agent_core/protocol.py:56-82`）。
- **DATA 帧载荷约定**：`{status, type(经 extra), result}`，业务类型（`question`/`query`/`task`）走 `extra.type`，core 不感知（`backend/agent_core/protocol.py:110-125`）。
- **前端镜像契约**：`AssistantEvent.fromJson` 与 `AssistantEventType` 常量逐字段对齐后端（`frontend/lib/features/assistant/domain/assistant_event.dart:1-69`）；`ERROR.code == INPUT_UNSAFE` 标「已拦截」而非报错（`:71-77`）。
- **端到端帧证据**：DATA 携 `type:"question"` 题卡（`backend/tests/api/routes/test_assistant.py:104-107`）；ERROR 帧拦截非学习输入（`:84-93`）；前端 fold 按 `eventType` 折叠文本/卡片/错误（`frontend/lib/features/assistant/domain/ai_text_fold.dart:40-55`）。

**Consequences**：前后端以 `eventType` 为唯一分发键，新增语义走 `extra` 而非新帧类型，避免协议膨胀；SSE 分帧解析为前端单一事实源（`frontend/lib/features/assistant/data/assistant_api_client.dart:53-90`）。
