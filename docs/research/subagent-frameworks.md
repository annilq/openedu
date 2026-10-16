# Subagent / Multi-agent 组织设计方式调研报告

> 调研对象：Genkit（Multi-agent delegation）、Pydantic AI（Harness Subagents）、LangChain（Multi-agent Subagents）三份官方文档。
> 所有论断均基于 2026-10-16 抓取的官方页面原文，关键处附代码片段；未能获取的内容会明确标注。

---

## ① 三框架横向对比表

| 维度 | Genkit（multi-agent delegation） | Pydantic AI（harness subagents） | LangChain（subagents） |
|---|---|---|---|
| **推荐粒度** | 明确倾向少拆：「单个 agent + 多个工具通常更简单」；只有当各专家需要不同的指令、模型设置、持久记忆或可独立检查的产物时才拆（https://genkit.dev/docs/js/agents/multi-agent/） | 文档不规定数量，只给拆分动机（工具集和上下文膨胀）与深度护栏（`max_depth` 默认 3）；官方示例固定「1 编排 + 2 专家」（https://pydantic.dev/docs/ai/harness/subagents/） | 明确反对过度拆分：「只有少量工具的简单场景，请使用单个 agent」；列举了适合拆分的三类信号（多领域、子 agent 不需直接对话、要集中控制流）；提示词枚举/枚举约束仅适合 **< 10 个** agent，超过应改用工具发现（https://docs.langchain.com/oss/python/langchain/multi-agent/subagents） |
| **主 agent 如何感知 subagent 能力** | 中间件 `agents()` 为**每个 subagent 注入一个委派工具**，默认命名 `delegate_to_<agentName>`；描述可来自 action metadata 或在配置中覆盖，「描述会变成编排器模型的工具描述」（同上） | 单一工具 `delegate_task(agent_name, task)`（可用 `tool_name=` 改名）；可用 subagent 通过 `get_instructions` 以**静态指令写入系统提示**（「留在可缓存前缀中」，利于 prompt caching）；支持从磁盘发现 Claude 风格 `.md` / Codex 风格 `.toml` 定义（同上） | 两种模式：**每个 subagent 一个工具**（如 `call_research_agent`）或**单一分发工具 `task(agent_name, description)`**；文档原话「subagent 的名称和描述是主 agent 知道该调用谁的主要方式」；发现方式三种：系统提示枚举（<10）、Enum 约束（<10）、工具发现（`list_agents`/`search_agents`，>10 或动态）（同上） |
| **上下文隔离** | `historyLength` 控制转发给 subagent 的最近消息条数（示例中为 4）；client-managed subagent 会收到历史，server-managed subagent 不转发（它拥有自己的服务端会话）；产物通过 `artifactStrategy: 'session'` 合并进父会话（同上） | **完全隔离**：「每次委派都在子 agent 自己的 run 中执行，有自己的消息历史，永远看不到父对话」；结果是 `str(result.output)`——**原样字符串化返回，框架不做摘要/压缩**（事件流中的截断 `MAX_EVENT_TEXT_CHARS=4096` 只是展示保护）（同上） | 默认**无状态**：subagent 不记得过去交互，每次调用在干净的上下文窗口中运行以防 context bloat；两种输入模式：**Isolated**（默认，仅任务描述）vs **Forked**（父级对话历史）；结果默认返回**最终消息**作为工具结果，可用 `Command` 额外回传 state keys（同上） |
| **控制流（路由决策）** | **LLM 路由**：编排器（orchestrator）决定哪个专家处理哪部分请求，然后综合最终答案；subagent 的中断和失败作为**工具输出**返回给编排器，不会自动变成顶层中断（同上） | **LLM 路由**：父模型通过发起 `delegate_task(agent_name, task)` 工具调用选择 subagent 并撰写任务简报；「编排者在写简报时最清楚任务有多难，所以它是决定跑哪个模型的正确位置」；**subagent 之间可以互调**（`SubAgents` 可嵌套成树，受 `max_depth` 限制）；模型并行发出的委派作为独立子 run 并发运行（同上） | **集中式 LLM 路由**：supervisor 是维护对话上下文的完整 agent，动态决定调用哪个 subagent、给什么输入、如何组合结果；**文档未提及 subagent 之间直接互调**；单轮内可并行调用多个 subagent（同上）；对照的 router 模式是单步分类、不维护对话状态，适合「清晰的输入分类 + 确定性/轻量分类」（https://docs.langchain.com/oss/python/langchain/multi-agent/router） |
| **工具归属** | 工具挂在各 subagent 自己的定义上（`use: [artifacts(), retry()]`）；编排器持委派中间件 + 只读 `artifacts({ readonly: true })`，通过 `read_artifact` 工具检查委派成果（https://genkit.dev/docs/js/agents/multi-agent/） | **默认不传递**：「父 agent 的工具不会传给子 agent，subagent 用自己的工具跑」；三条路径：① 把工具直接绑到 subagent 自己的 `Agent`（推荐做法）② `include_self=True` 委派给拥有全部绑定的 agent 的一次全新 run ③ 磁盘 agent 用 `tool_resolver` 映射；`inherit_tools=True` 已弃用（https://pydantic.dev/docs/ai/harness/subagents/） | **subagent 拥有自己的工具**（`create_agent(tools=[...])`），主 agent 只拥有「包装工具」（调用 subagent 的那个）；示例体现的模式是「领域工具归 subagent，调度工具归主 agent」（https://docs.langchain.com/oss/python/langchain/multi-agent/subagents） |
| **后台执行** | Agents API 与「sessions、streaming、persistence、background execution 和 HTTP clients」集成（旧版 prompts-as-tools 页面对新 API 的说明，见 legacy 一节）；委派在编排器流中表现为普通工具活动，可流式观察委派进度（https://genkit.dev/docs/js/agents/multi-agent/） | opt-in 托管委派会话（`DelegationTasks`）：工具 schema 增加 `background`/`resume` 参数；每个后台 subagent 有稳定 conversation ID；支持 `background(task_id)`、`cancel(task_id)`、`allow_resume(task_id)`；`DelegationReports` 把后台报告投递给父 run（默认 `when_idle` 优先级）；`event_stream_handler` 可把子 run 的模型流式与工具事件转发给调用方（https://pydantic.dev/docs/ai/harness/subagents/） | 默认同步（主 agent 等待完成）；异步用**三工具模式**：start job（返回 job ID）/ check status / get result，完成通知由应用层负责；单轮并行调用多个 subagent 已确认；**文档未明确描述** subagent 向主 agent 流式回传中间结果的机制（https://docs.langchain.com/oss/python/langchain/multi-agent/subagents） |
| **官方示例典型规模** | coordinator + researcher + coder = **1 编排 + 2 专家**（https://genkit.dev/docs/js/agents/multi-agent/） | 全部示例为 **1 编排 + 2 专家**（researcher/writer、reproducer/librarian、reviewer/linter），无 5+ 规模示例（https://pydantic.dev/docs/ai/harness/subagents/） | 1–3 个 subagent（basic 1 个、registry 2 个、枚举示例 3 个），建议超过 10 个改用工具发现（https://docs.langchain.com/oss/python/langchain/multi-agent/subagents） |

---

## ② 每框架详述

### 2.1 Genkit：Multi-agent delegation

**定位与拆分态度。** Genkit 把多 agent 系统定义为「专家 agent + 编排者」：编排者决定哪个专家处理请求的哪一部分，然后综合最终答案。文档对拆分时机给出了少见的明确表态——「当单独的能力受益于单独的 prompt、工具、状态或评估时使用此模式。当一条 prompt 就能协调整个任务时，**单个 agent 加若干工具通常更简单**。当专家需要不同的指令、不同的模型设置、持久的专家记忆或可独立检查的产物时，多个 agent 才有用」（https://genkit.dev/docs/js/agents/multi-agent/）。

**能力感知机制。** 中间件包提供 `agents()` 做委派，「它为每个 subagent 注入一个委派工具」，默认工具名 `delegate_to_<agentName>`。描述可以从 action metadata 自动发现，也可以在中间件配置里覆盖；文档提醒「描述要保持具体，因为它们会变成编排器模型的工具描述」（同上）。

**配置样例**（每段不超过 15 行，下同）：

```ts
const coordinator = ai.defineAgent({
  name: 'coordinator',
  system: 'Delegate to specialists, inspect their results, then answer the user.',
  use: [
    agents({
      agents: [
        'researcher',
        { name: 'coder', description: 'Writes, debugs, and explains code. Use for programming tasks.' },
      ],
      historyLength: 4,
      maxDelegations: 5,
      artifactStrategy: 'session',
    }),
    artifacts({ readonly: true }),
  ],
});
```
（https://genkit.dev/docs/js/agents/multi-agent/#add-delegation-middleware）

**委派选项。** `agents` 接受 agent 名、agent action 或「名字 + 描述覆盖」条目；`toolPrefix` 控制生成的工具名前缀（默认 `delegate_to`，设为空串则用裸 agent 名）；`historyLength` 决定转发多少条最近消息给 subagent；`maxDelegations` 限制编排者单轮内的委派次数；`artifactStrategy` 控制 subagent 产物是否合并进父会话。历史转发规则：client-managed subagent 会在其 state 中收到最近消息，server-managed subagent 则不转发（它们拥有自己的服务端会话）（同上，#delegation-options）。

**产物与流式。** 设 `artifactStrategy: 'session'` 后，subagent 产物按调用命名空间合并进父会话，配合编排器的 `artifacts({ readonly: true })`，编排器可通过 `read_artifact` 工具检查委派工作；文档建议「当委派工作应该对最终用户或后续轮次可见时用 session 产物；当专家输出只是编排者当前答案的实现细节时保持隔离」。流式方面，「委派在编排器流中表现为普通工具活动」，可以监听 `toolRequests` 里以 `delegate_to_` 开头的请求来展示委派进度（同上，#stream-delegation-progress、#artifacts-from-sub-agents）。

**失败语义。** 「subagent 的中断和失败作为工具输出返回给编排器，不会自动变成原始客户端的顶层中断」；文档要求编排者指令写明如何处理委派失败——重试、换一个专家或向用户澄清（同上，#interrupts-and-failures）。

**新旧 API 关系。** 页面底部注明旧的「Building multi-agent systems」页描述的是 prompts-as-tools 模式，新工作应优先用 Agents API 中间件，「因为它与 sessions、streaming、persistence、background execution 和 HTTP clients 集成」（https://genkit.dev/docs/js/agents/multi-agent/#existing-legacy-page）。

### 2.2 Pydantic AI：Harness Subagents

**定位与拆分动机。** Subagents 文档的「The problem」一节指出：单个包打天下的 agent 会累积「庞大的工具集和漫长的上下文」，把工作拆分到专门化子 agent 上可以「让每个上下文保持专注」。手工接线委派意味着「每个 agent 写一个工具、转发依赖、串用量限制、还要告诉模型它能委派谁」——这些正是 `SubAgents` 能力要消除的样板工作。文档没有给出数量建议，也没有明确的「不要过度拆分」警告，但 `max_depth` 默认 3（含顶层 run）实质上限制了无限嵌套（https://pydantic.dev/docs/ai/harness/subagents/）。

**能力感知机制。** 把 `SubAgents` 放进父 agent 的 `capabilities=[...]`；框架只暴露**一个**工具 `delegate_task(agent_name, task)`（可改名），配置 `models` 菜单后该工具多一个 `model` 参数。可用 subagent 通过 `get_instructions` 以静态指令写入系统提示，「留在可缓存前缀中」，内容取自每个 agent 的 `description`。未知 `agent_name` 抛 `ModelRetry` 让模型自我纠正；`agent_folders` 可在每次 run 开始时从 workspace 读取 Claude 风格 `*.md` 与 Codex 风格 `*.toml` 定义（同上）。

**基础示例：**

```python
researcher = Agent('anthropic:claude-opus-5-5', name='researcher', description='Researches a topic and reports findings')
writer = Agent('anthropic:claude-opus-5-5', name='writer', description='Turns notes into polished prose')
orchestrator = Agent(
    'anthropic:claude-opus-5-5',
    capabilities=[SubAgents(agents=[SubAgent(researcher), SubAgent(writer)])],
)
result = orchestrator.run_sync('Research the history of TLS and write a one-paragraph summary.')
```
（https://pydantic.dev/docs/ai/harness/subagents/）

**上下文隔离。** 「每次委派都在子 agent 自己的 run 中执行，有自己的消息历史，**永远看不到父对话**」，因此 `task` 参数必须自包含。回传给父 agent 的结果是 `str(result.output)`——子 agent 最终输出的字符串化原样返回，**框架本身不做摘要或压缩**（同上）。

**控制流。** 路由由**父模型**决定：它通过发起 `delegate_task(agent_name, task)` 工具调用选择 subagent 并撰写任务简报。文档原话：「编排者在写简报时最清楚任务有多难，所以它是决定跑哪个模型的正确位置。」没有代码级「选哪个 subagent」的 API。**subagent 之间可以互调**：「Subagent 自己也可以拥有 `SubAgents`，形成一棵树」，深度受 `max_depth` 限制（默认 3，含顶层 run）。并行方面：「模型并行发出的委派作为独立子 agent run 并发运行」（同上）。

**工具归属。** 「父 agent 的工具不会传下去，subagent 用自己的工具跑。」框架给三条路径：① 把显式子 agent 需要的工具直接绑到它自己的 `Agent`（推荐做法）；② `include_self=True` 委派给拥有全部绑定的 agent 的一次全新 run；③ 磁盘加载的 agent 用 `tool_resolver` 把 frontmatter 工具名映射为 toolsets。`inherit_tools=True` 已弃用（会发 `HarnessDeprecationWarning`）。此外 `deps` 会转发、子 agent 共享父的 `AgentDepsT`；`shared_capabilities` 会应用到每个子 run（例如统一加 guardrail/memory/planning）（同上）。

**后台/异步执行（opt-in）。** 默认 `SubAgents` 仅前台行为。显式打开并绑定 `DelegationTasks` 后：delegate 工具 schema 增加 `background` 和 `resume` 参数；每个子 agent 获得稳定 conversation ID；`opened()` 上下文退出时排空 workers；`background(task_id)` 释放前台等待器；`await cancel(task_id)` 停止并排空该子 agent 及其后代；用户停止后模型请求的 resume 被阻塞，直到应用显式 `await allow_resume(task_id)`。`DelegationReports` 通过 core 的 `SystemPromptPart` 队列把后台报告投递给父 run，默认 `priority='when_idle'`；报告被明确为「自动化的、不可信的数据，不是用户指令或授权」。流式方面：传入 `event_stream_handler` 会转发到每个子 run，子 agent 的模型流式与工具事件浮现给调用方；`SubAgents` 还在 `sub_agents` 命名空间发 `DelegationStartEvent`/`DelegationEndEvent` 类型化事件，一次委派共享同一 `tool_call_id` 便于配对（同上）。

**完整签名要点**（`SubAgents`）：`agents`、`models`（每次委派的模型菜单）、`agent_folders`、`agent_overrides`、`tool_resolver`、`forward_usage=True`（全树聚合用量）、`inherit_tools=False`（已弃用）、`shared_capabilities`、`event_stream_handler`、`tool_name='delegate_task'`、`tool_retries=2`、`contain_errors`、`include_self`、`max_depth=3`。`SubAgent` 每个委派可配 `name`、`description`、`models`、`usage_limits`、`timeout_seconds`、`max_calls`、`on_failure`、`contain_errors`（同上）。

**版本提示。** Harness 处于 0.x，「API 可能在 minor 版本间变化」，变更会伴随弃用警告和迁移说明（同上）。

**补充：多 agent 指南的复杂度阶梯。** Pydantic AI 的多智能体应用指南把多 agent 架构分为五个复杂度层级：① 单 agent 工作流（大多数文档覆盖的内容）→ ② Agent delegation（agent 通过工具调用另一个 agent，可手工或用 `SubAgents`）→ ③ Programmatic agent hand-off（多个 agent 顺序调用，由应用代码/人类决定下一个）→ ④ Graph based control flow（「为最复杂的场景」保留的图状态机）→ ⑤ Deep Agents（规划、文件操作、任务委派、沙箱代码执行的自主 agent）。「当然，你可以在单个应用里组合多种策略。」该页同时强调 delegation 与 hand-off 的路由差异：delegation 由 LLM 通过工具调用决定且完成后控制权返回父 agent；hand-off 由应用代码和/或人类决定，且「这里 agent 之间不需要用相同的 deps」。所有可运行示例都只有 2 个 agent（https://pydantic.dev/docs/ai/guides/multi-agent-applications/）。

### 2.3 LangChain：Multi-agent Subagents

**拆分时机与反过度拆分。** 文档列举了使用 subagents 模式的三个信号：存在多个不同领域（如 calendar、email、CRM、database）；子 agent 不需要直接与用户对话；希望集中式工作流控制。同时明确反对过度拆分：**「对于只有少量工具的简单情况，请使用单个 agent。」** 没有硬性数字门槛，但在「Subagent specs」部分指出：系统提示枚举或枚举约束只适合 **< 10 个 agent** 的小型静态列表；超过此规模或注册表频繁变动时应改用基于工具的发现（https://docs.langchain.com/oss/python/langchain/multi-agent/subagents）。

**能力感知机制。** 核心机制是**子 agent 被包装成工具**暴露给主 agent，主 agent 根据工具的 name/description 决定何时调用。两种工具模式：**Tool per agent**（每个子 agent 一个独立工具，适合细粒度控制输入输出）和 **Single dispatch tool**（单一参数化工具 `task`，通过 `agent_name` 调用注册表中任意子 agent，适合多团队协作、约定优于配置）。文档原话：「**subagent 的名称和描述是主 agent 知道该调用谁的主要方式。**」主 agent 获取子 agent 信息的三种方式：系统提示枚举（<10）、Enum 约束（<10）、工具发现（`list_agents`/`search_agents`，>10 或动态注册表）（同上）。

**注册表示例：**

```python
SUBAGENTS = {
    "research": research_agent,
    "writer": writer_agent,
}

@tool
def task(agent_name: str, description: str) -> str:
    """Launch an ephemeral subagent for a task.

    Available agents:
    - research: Research and fact-finding
    - writer: Content creation and editing
    """
    agent = SUBAGENTS[agent_name]
    result = agent.invoke({"messages": [{"role": "user", "content": description}]})
    return result["messages"][-1].content
```
（https://docs.langchain.com/oss/python/langchain/multi-agent/subagents）

**上下文隔离。** 子 agent 默认**无状态**：不记得过去交互，所有对话记忆由主 agent 维护；每次调用在**干净的上下文窗口**中运行，防止主对话 context bloat。两种输入模式：**Isolated**（默认，子 agent 只收到任务描述；强隔离，但需重新推导父级已完成的工作）与 **Forked**（收到父级对话历史，Deep Agents 中还包含 system prompt；有先前上下文但 prompt 更大、隔离性更弱）。结果默认返回子 agent 的**最终消息**作为工具结果；文档给两种策略保证结果质量：① 在子 agent 提示中明确要求返回结果（避免「只做工具调用但最终消息不含结果」的失败模式）；② 用代码格式化/丰富响应，例如通过 `Command` 回传额外 state keys（同上）。

**控制流。** 集中式：所有路由通过主 agent（supervisor）。**Supervisor 是维护对话上下文的完整 agent**，动态决定调用哪个子 agent、提供什么输入、如何组合结果，并可跨多轮持续决策；对照的 **Router 通常是单步分类，不维护持续对话状态**。router 文档进一步对比：「Router 是专用的路由步骤（通常是单次 LLM 调用或规则逻辑），本身通常不维护对话历史、不做多轮编排，是预处理步骤；Subagents 是主 supervisor agent 作为进行中对话的一部分动态决定调用哪些 subagent。」并给出选用建议：「有清晰输入分类、想要确定性或轻量分类时用 router；需要灵活、感知对话的编排、由 LLM 基于演进上下文决定下一步时用 supervisor。」子 agent 默认把结果返回主 agent 而非直接与用户对话（除非在子 agent 内用 interrupts 收集用户输入）。**文档未提及子 agent 之间可直接互调**的机制。主 agent 可在单轮内并行调用多个子 agent（https://docs.langchain.com/oss/python/langchain/multi-agent/subagents、https://docs.langchain.com/oss/python/langchain/multi-agent/router）。

**工具归属。** 子 agent 在 `create_agent` 时通过 `tools=[...]` 附加自己的工具；主 agent 拥有「包装工具」（即调用子 agent 的那个工具）。文档没有强制规定，但示例模式一致：「领域工具归子 agent，调度工具归主 agent」（https://docs.langchain.com/oss/python/langchain/multi-agent/subagents）。

**后台/异步执行。** 同步（默认）：主 agent 等待子 agent 完成后再继续，适用于下一步依赖子 agent 结果、有顺序依赖、子 agent 失败应阻塞主响应的场景；缺点是长任务会冻结对话。异步（后台）：主 agent 启动后台作业（独立进程/服务）后继续响应用户，用**三工具模式**实现——start job（返回 job ID）、check status（pending/running/completed/failed）、get result；作业完成需由应用层通知用户（例如用户点击通知后发送「Check job_123 and summarize the results.」这样的 HumanMessage）。流式方面：文档确认单轮并行调用多个子 agent，但**未明确描述**子 agent 向主 agent 流式回传中间结果的机制，异步模式通过「状态查询 + 获取结果」轮询实现（同上）。

**Checkpointing 细节。** 默认子 agent 使用 inherited checkpointer 模式：每次调用从干净状态开始，支持 interrupts，可安全并行；若需子 agent 跨调用保持持久对话历史，需编译时设置 `checkpointer=True`（continuations 模式）。因子 agent 在工具函数内调用，LangGraph 无法静态发现它们，`get_state` with `subgraphs` 不会返回子 agent 状态（同上）。

---

## ③ 「对过度拆分的态度」专项总结

| 框架 | 对过度拆分的态度 | 原文依据 |
|---|---|---|
| **Genkit** | 三家中表态最明确的「少拆」派：默认推荐单 agent + 多工具；多 agent 只在专家需要不同指令/模型设置/持久记忆/可独立检查产物时才值得。同时用 `maxDelegations` 提供运行时护栏。 | 「当一条 prompt 就能协调整个任务时，单个 agent 加若干工具通常更简单。当专家需要不同的指令、不同的模型设置、持久的专家记忆或可独立检查的产物时，多个 agent 才有用。」（https://genkit.dev/docs/js/agents/multi-agent/） |
| **Pydantic AI** | 保持中立、不给数字建议，也不警告过度拆分；只陈述拆分动机（工具集/上下文膨胀）并提供结构性护栏：委派深度 `max_depth` 默认 3、每个子 agent 可有独立 `usage_limits`/`timeout_seconds`/`max_calls`。多 agent 指南把「单 agent 工作流」列为第一层级、图控制流保留给「最复杂的场景」，示例全部控制在 2 个 agent。 | 「把工作拆分到专门化子 agent 上可以让每个上下文保持专注」（https://pydantic.dev/docs/ai/harness/subagents/）；五层级阶梯见 https://pydantic.dev/docs/ai/guides/multi-agent-applications/ |
| **LangChain** | 明确反对：「对于只有少量工具的简单情况，请使用单个 agent。」虽无硬性数字，但给出了可操作的规模分界：**10 个 agent** 是提示词枚举/枚举约束的上限，超过应改用工具发现；官方示例稳定在 1–3 个 subagent。 | 「For simpler cases with just a few tools, use a single agent.」；「< 10 agents」适用于提示词枚举/枚举约束（https://docs.langchain.com/oss/python/langchain/multi-agent/subagents） |

**横向观察：** 三家文档在「示例规模」上高度一致——官方 example 都是 **1 个编排者 + 1~3 个专家**，没有任何一家展示 5+ agent 的大规模编排。这直接反映框架设计者的心理预期：subagent 模式的首选形态是「小而专的专家集合」，而非层级深、数量大的 agent 组织。Genkit 和 LangChain 把「单 agent 优先」写成了明文建议，Pydantic AI 则通过复杂度阶梯和默认参数（`max_depth=3`）隐式表达同样的倾向。

---

## ④ 来源清单

| # | 页面 | URL | 用途 |
|---|---|---|---|
| 1 | Genkit — Multi-agent delegation | https://genkit.dev/docs/js/agents/multi-agent/ | 主来源（含 #add-delegation-middleware、#delegation-options、#stream-delegation-progress、#interrupts-and-failures、#artifacts-from-sub-agents、#existing-legacy-page 小节） |
| 2 | Pydantic AI — Harness Subagents | https://pydantic.dev/docs/ai/harness/subagents/ | 主来源 |
| 3 | Pydantic AI — Multi-agent applications 指南 | https://pydantic.dev/docs/ai/guides/multi-agent-applications/ | 补充：五复杂度层级、delegation vs hand-off、路由语义 |
| 4 | LangChain — Multi-agent Subagents | https://docs.langchain.com/oss/python/langchain/multi-agent/subagents | 主来源 |
| 5 | LangChain — Router | https://docs.langchain.com/oss/python/langchain/multi-agent/router | 补充：router vs subagents/supervisor 的路由决策对比 |

> 备注：Genkit 旧版「Building multi-agent systems」（prompts-as-tools）页面（https://genkit.dev/docs/js/multi-agent/）未单独抓取，仅通过新页面 #existing-legacy-page 小节的说明间接引用；其内容以本报告第 2.1 节末段为限，未做展开。三家主页面均一次抓取成功，无重定向、无「未能获取」项。

---

## ⑤ 对 openedu 的适用性评估（2026-10-16，分支 `integration/business-feature-agents`）

### 5.1 现状实测（ADR-0097 落地后）

| business | priority | 工具数 | 执行模型 |
|---|---|---|---|
| capability | 16 | 0 | 固定文案，**零 LLM**（`capability/agent.py` 不接 provider） |
| tasks | 14 | 7 | tool loop，`requires_tool_data=True` |
| question | 12 | 4 | tool loop + 流式 tool（`generate_questions` 的 `stream_handler`） |
| students | 10 | 1 | tool loop，`requires_tool_data=True` |
| tutor | -10 | 0 | **另一套执行引擎**：`TutorService`（输入/输出安全闸门 + RAG 检索 + 学科 persona + 流式），不经 tool loop |
| 合计 | — | **12** | — |

### 5.2 框架拆分标准逐条对标

| 框架标准（三家共识） | 本项目是否满足 | 证据 |
|---|---|---|
| **不同指令**（Genkit 第 1 条） | ✅ 真实满足 | question 的出题 SOP + 收尾话术纪律（`question/agent.py:32-48`）、tasks 的「只起草 + 确认卡」纪律（`tasks/agent.py`）、tutor 的安全锁 + persona（`tutor/agent.py:54-64`）是三套不可互替的指令 |
| **不同模型设置** | ❌ 不满足 | 全部经 `resolve_engine` 读同一份家长 `ModelConfig`，无 per-agent 模型分化 |
| **持久专家记忆** | ❌ 不满足 | 无 |
| **可独立检查的产物** | ⚪ 假象 | 题卡/确认卡是 tool 产物（`render_tool_result`），不靠拆分获得；拆出 students 反而拿不到任何独立产物 |
| **上下文隔离**（三框架拆分的头号动机） | ❌ **不满足** | `agent_core/subagent.py:258`：`history = list(ctx.history or [])`——每个 subagent 都收到**完整对话历史**，与 Pydantic「永远看不到父对话」/ LangChain「干净上下文窗口」/ Genkit `historyLength` 全部相反 |
| **多领域**（LangChain 信号 1） | ⚪ 单业务内多域 | 教育单一业务内的学情/题库/人群/伴学，不是 calendar/email/CRM 式的异质业务 |

### 5.3 结论

1. **「拆得过细」有实据**：按三家官方示例的「1 编排 + 1~3 专家」形态，5 个 agent 超规格；其中 students（1 工具）与 capability（0 工具 0 LLM）在框架视角下**不构成 agent**——前者是一个工具，后者是一条路由分支（固定回复），而非需要独立指令与工具集的专家。
2. **但拆分的核心收益并没有拿到**：三框架把 subagent 的首要价值定为上下文隔离，而本项目 `subagent.py:258` 全量共享历史——当前拓扑只买到「指令分化 + 路由精度 + `requires_tool_data` 闸门 + `Conversation.kind` 审计」，没买到隔离。
3. **「全部并成一个 agent」会丢掉真实存在的东西**：tutor 是另一套执行引擎（安全闸门 + RAG + persona，`tutor/agent.py:47-153`），无法与 12 工具的 tool loop 合并——合并要么丢掉安全闸门/RAG，要么在单类里留 mode 分支（那是换汤不换药的路由）。且 `requires_tool_data` 硬闸门源于真机事故（`subagent.py:94`：本地小模型编造「3 个学生 / 掌握度 85%」），合并后该闸门无法对「伴学答题零工具」统一生效。
4. **框架对齐的中间态**：3 个执行体——tutor（独立引擎）/ tasks（吸收 students 的 `list_students` + 名单 triggers，8 工具）/ question（4 工具 + SOP）；capability 从「agent」降级为路由层固定回复（或保留零成本薄 manifest）。这正好落在三家官方示例的 1+2 形态上，且不丢任何已证明必要的分化。

