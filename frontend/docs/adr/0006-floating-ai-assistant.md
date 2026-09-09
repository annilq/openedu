# 悬浮 AI 助手：全局入口 + SSE 客户端 + 角色感知

新增「悬浮 AI 助手」为全局入口：双端通用固定右下角悬浮按钮，点击弹对话框（消息列表 + 输入框），用户输入自由文本经 `POST /api/v1/assistant/chat` 调后端 AgentRuntime（意图识别 → 路由 → subagent 执行 → AG-UI 事件流）。后端架构见 ADR-0024/0025/0026。现有 `tutor_chat_screen.dart` 保留为娃娃端专用伴学页，二者共用 `tutor_message_list`/`tutor_chat_input_bar` 组件，不重复实现。客户端 `AssistantClient` 按 AG-UI 信封 `fromChunk(type, payload)` 分发渲染（text 打字机 / THINKING 折叠 / TOOL_CALL 可视化 / CARD 题卡浮现）。客户端带 `role` + `session_id`；孩子端 runtime 已按角色过滤可见 subagent（仅伴学答疑），输入框 hint 随角色变。

## Considered Options

- **A. 悬浮助手替代 tutor_chat_screen（已否决）**：全局统一入口、去掉专用伴学页。改动最大，且孩子端伴学体验（欢迎提示/额度卡）会丢失。
- **B. 悬浮助手 + 保留专用伴学页（采纳）**：悬浮助手为统一全局入口；tutor_chat_screen 保留，共用消息/输入组件。改动聚焦在悬浮壳 + SSE client，复用现有聊天组件。
- **C. 仅家长端悬浮（已否决）**：用户明确要双端通用 + 角色感知；孩子端经 runtime 过滤只暴露伴学答疑，无需前端两套逻辑。

## Consequences

- 新增 `features/assistant/`：`presentation/widgets/app_floating_assistant.dart`（全局 `Overlay`/`Stack` 悬浮按钮 + 对话框壳）、`assistant_notifier.dart`（SSE 流状态）、`assistant_client.dart`（HTTP SSE 调 `/api/v1/assistant/chat`）。
- `app_floating_assistant` 在 `app.dart` 根 `Stack` 上层挂载，双端显示；点击切对话框显隐，对话框内嵌复用 `tutor_message_list` + `tutor_chat_input_bar`。
- `assistant_client` 单例持有 `session_id` + `role`，请求体 `{role, session_id, message, model?, focus_interest?}`；解析 SSE `data: {type, ...}`，路由到 `fromChunk` 分发器（独立实现，不依赖任何 genkit 客户端）。
- 事件渲染：ASSISTANT_MESSAGE → 打字机追加；THINKING → 折叠推理区；TOOL_CALL/TOOL_RESULT → 工具调用可视化条；CARD → 题卡浮现（复用 `QuestionPreview` 渲染）；ERROR/DONE → 终态。
- 安全：违规回显由后端经 `ERROR`/`DONE` 控制，前端不展示拒绝原因（ADR-008）。
- 零新设计令牌：复用 `App*` 语义组件与 `.impeccable.md` 令牌，不引入新色/字号。
