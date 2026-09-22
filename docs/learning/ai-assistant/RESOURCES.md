# openedu AI Agent 架构 · Resources

## Knowledge

- [AG-UI 协议 · Architecture](https://docs.ag-ui.com/spec/draft/architecture)
  「一切可见行为都在一条有序类型化事件流里，没有旁道」——本仓事件帧设计的对照蓝本。注意：**规范目前仍是 draft**，不要当作稳定契约引用。用于：事件帧设计、客户端折叠、工具调用回显。
- [LangGraph 概览](https://langchain-ai.github.io/langgraph/tutorials/introduction/)
  框架即编排的代表：durable execution、持久化、human-in-the-loop。用于：判断「自写内核放弃了多少」、对照 checkpointer 与本仓自建会话表。
- [LangChain Agent Protocol](https://langchain-ai.github.io/agent-protocol)
  threads + runs 的服务端会话建模（含 `/runs/stream`）。用于：多轮状态该放服务端还是客户端的选型讨论。
- [LangGraph · Graph API / State 模型](https://langchain-ai.github.io/langgraph/how-tos/state-model/)
  显式图（node / edge / state）与本仓「文件夹发现 + 手写 loop」的对照面。用于：编排方式的取舍。
- [OpenAI Function Calling 指南](https://platform.openai.com/docs/guides/function-calling)
  工具消息为什么必须与前一条 assistant 的 `tool_calls` 配对、strict 模式的官方口径。用于：ADR-0033 回灌契约、ADR-0040 strict schema。
- [ReAct 论文（arXiv 2210.03629）](https://arxiv.org/abs/2210.03629)
  Thought-Action-Observation 循环的原点，所有 tool loop 的思想来源。用于：理解为什么要有轮次上限。
- [Model Context Protocol](https://modelcontextprotocol.io/)
  把工具外置到独立进程的另一条路线（与本仓「工具即进程内函数」相反）。用于：跨应用复用工具时的选型。
- [Hexagonal Architecture（Alistair Cockburn）](https://alistair.cockburn.us/hexagonal-architecture/)
  端口与适配器的原始表述。用于：`agent_core` 分层与 `adapters/` 唯一落点的理论底。
- [Genkit 文档](https://genkit.dev/)
  本仓唯一引擎适配器的上游，用于理解 `return_tool_requests=True`、schema 约束解码、流式 chunk 结构。

### 仓库内一手资料（优先级高于任何外部文档）

- `docs/agents/architecture.md` —— 分层、不变量、历史评审结论（已闭环）。
- `docs/adr/0024 · 0025 · 0033 · 0038 · 0040 · 0042 · 0043 · 0048 · 0054` —— 每条决策的「为什么」与被否掉的选项。
- `docs/adr/0035`（扩展钩子 seam）· `docs/adr/0041`（配置健壮性）· `docs/adr/0048`（会话历史 SSE） —— 早期架构评审知识点的落点。
- `backend/tests/ai/*.py` —— 不变量如何被 CI 钉住（分层、工具契约、tool loop 边界、失败归因）。

## Wisdom (Communities)

- 本仓库的 ADR 评审流程本身即「同行评议」：每条决策都要写 Considered Options 与验证判据，新增能力请照此格式。
- 尚未确认用户是否愿意加入外部社区；在用户表态前，不主动推荐外部社群。

## Gaps

- **context compaction**：本仓只有「摘要注入」的自制实现，缺少关于长上下文压缩策略的系统性资料（LangChain 的 `SummarizationNode`、mem0 等值得后续补做对比）。
- **GenUI 方向**：CopilotKit generative UI、A2UI、MCP-UI 等「服务端下发 UI schema」方案尚未系统调研，只在本仓 ADR-0042 里作为「明确不做」被提及。
- **儿童产品的 AI 安全边界**：目前只有本仓 ADR-0008 / 0026 的自建实践，缺少行业级参考资料。
