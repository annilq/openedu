# openedu AI Agent 架构 · Resources

## Knowledge

### 设计法（先读这两份，再读具体来源）

- [`reference/agent-architecture-design.md`](./reference/agent-architecture-design.md)
  **通用设计法**：该不该用 agent / workflow 与 agent 的分界 / 六个接缝 / 工具九条 / 接入业务系统七条 / 自检清单 / 什么时候该改用框架。
- [`reference/research-agent-architecture-sources.md`](./reference/research-agent-architecture-sources.md)
  上面那份的**一手出处清单**（S1–S14，含原文引用与 URL，附「未能证实」），需要向他人论证某条原则时用这份。

### 一手来源（按主题）

- [Building effective agents (Anthropic)](https://www.anthropic.com/research/building-effective-agents)
  workflow vs agent 的官方分界、五种 workflow 模式、"先找最简方案"、ACI 原则。**本仓路由模式的理论出处。**
- [Writing effective tools for agents (Anthropic)](https://www.anthropic.com/engineering/writing-tools-for-agents)
  工具是「确定性系统与非确定性 agent 之间的契约」；禁 1:1 包 API、禁裸 UUID、结果要限流截断、错误文案要可消费。**工具评审 checklist 的来源。**
- [Effective context engineering for AI agents (Anthropic)](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
  上下文是有限资源（diminishing marginal returns）；长任务三件套 compaction / 结构化笔记 / sub-agent。**SubAgent 形态的一手背书。**
- [A Practical Guide to Building Agents (OpenAI, PDF)](https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf)
  agent 三要素、何时该建 agent 的三判据、单 agent 优先、工具风险分级（low/medium/high）、guardrails 与人工介入触发条件。
- [12-Factor Agents](https://github.com/humanlayer/12-factor-agents)
  与自研内核最贴的经验集：own your prompts、own your context、**统一执行状态与业务状态**、工具即结构化输出、pause/resume、contact humans with tool calls、compact errors、small focused agents。注意是**从业观察**非官方标准。
- [OpenAI Agents SDK · Tools](https://openai.github.io/openai-agents-python/tools/) 与 [CrewAI Concepts](https://docs.crewai.com/en/concepts/agents)
  **装配机制的一手事实**：`@tool` 只生成 schema，装配永远显式；CrewAI 当前推荐路径已是无装饰器的配置/显式定义。用于：否定「装饰器 = 自动注册」。
- [Model Context Protocol](https://modelcontextprotocol.io/) · [Tools 概念](https://modelcontextprotocol.io/docs/concepts/tools) · [Architecture](https://modelcontextprotocol.io/docs/learn/architecture)
  真正的动态发现在这里：capability negotiation + `tools/list`；另要求 human-in-the-loop 能拒绝工具调用、工具顺序必须确定（影响 prompt cache）。
- [AG-UI 协议 · Overview](https://docs.ag-ui.com/) · [Events](https://docs.ag-ui.com/concepts/events)
  「一切可见行为都在一条有序类型化事件流里，没有旁道」——本仓事件帧设计的对照蓝本。用于：事件帧设计、客户端折叠、工具调用回显。
  ⚠️ 2026-09-22 复核：文档站标注 **Documentation 1.0 Specification**（不是 draft，只有 Meta Events 等提案页标 DRAFT）；1.0 事件名为 **PascalCase**（`RunStarted` / `TextMessageStart` / `ToolCallStart` / `StateDelta`），`RUN_STARTED` 这类全大写下划线属旧式写法（且 `THINKING_*` 已被 `REASONING_*` 取代）。旧链接 `docs.ag-ui.com/spec/draft/architecture` 已过期。
- [LangGraph 概览](https://docs.langchain.com/oss/python/langgraph/overview)
  框架即编排的代表：durable execution、持久化、human-in-the-loop。用于：判断「自写内核放弃了多少」、对照 checkpointer 与本仓自建会话表。⚠️ 旧域名 `langchain-ai.github.io/langgraph/` 已 301 至此。
- [How to think about agent frameworks (LangChain 博客, 2025-04-20)](https://blog.langchain.dev/how-to-think-about-agent-frameworks/)
  竞品方自己承认「可以自建」的那一篇：框架的价值清单是 8 项（短/长期记忆、HITL、HOTL、streaming、observability、fault tolerance、optimization），并点明真难点是「每一步喂给模型的上下文」。**自写 vs 框架的取舍依据在这里，不在 API 文档。**
- [LangChain Agent Protocol](https://langchain-ai.github.io/agent-protocol)
  threads + runs 的服务端会话建模（含 `/runs/stream`）。用于：多轮状态该放服务端还是客户端的选型讨论。
- [LangGraph · Graph API / State 模型](https://langchain-ai.github.io/langgraph/how-tos/state-model/)
  显式图（node / edge / state）与本仓「文件夹发现 + 手写 loop」的对照面。用于：编排方式的取舍。
- [OpenAI Function Calling 指南](https://platform.openai.com/docs/guides/function-calling)
  工具消息为什么必须与前一条 assistant 的 `tool_calls` 配对、strict 模式的官方口径。用于：ADR-0033 回灌契约、ADR-0040 strict schema。
- [ReAct 论文（arXiv 2210.03629）](https://arxiv.org/abs/2210.03629)
  Thought-Action-Observation 循环的原点，所有 tool loop 的思想来源。用于：理解为什么要有轮次上限。
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

- **context compaction**：一手资料已补齐（Anthropic「Effective context engineering」的 compaction / 结构化笔记 / sub-agent 三件套），但**本仓尚未实现任何一档**——最轻量的「工具结果清理（tool result clearing）」也没有。参考 `reference/agent-architecture-design.md` §3 接缝 3。
- **工具风险分级与 per-tool 失败计数**：OpenAI 指南的 low/medium/high 分级、12-Factor 的 `errorCounter`（~3 次上限）都未落地；本仓只有全局 `max_turns`。
- **儿童产品的 AI 安全边界**：目前只有本仓 ADR-0008 / 0026 的自建实践，**一手来源里没有任何专门针对 K12/未成年人的条款**（research 文件「存疑」第 8 条），不要写成"某厂商明确要求"。
- **GenUI 方向**：CopilotKit generative UI、A2UI、MCP-UI 等「服务端下发 UI schema」方案尚未系统调研，只在本仓 ADR-0042 里作为「明确不做」被提及。
