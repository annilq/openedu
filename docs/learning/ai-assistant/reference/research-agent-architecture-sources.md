# AI Agent 架构：一手来源事实清单

## 元信息

- **研究问题**：一个极薄的自研 agent 内核（意图路由 → SubAgent → 工具循环 → 统一 SSE 事件流），用什么设计原则来对照评审？
- **方法**：直接抓取官方一手页面/PDF/GitHub 原始 Markdown（curl + 本地转文本），只记录原文明确写出的主张；推断部分标 `[推断]`。
- **抓取日期**：2026-09-22（所有 URL 均实际访问，HTTP 200）
- **未做**：不读本仓库代码；不引用二手博客/公众号转述。

### 来源清单

| # | 来源 | URL | 发布方 | 页面标注日期 |
|---|---|---|---|---|
| S1 | Building effective agents | https://www.anthropic.com/research/building-effective-agents | Anthropic（Erik S. / Barry Zhang） | Published Dec 19, 2024（页面含后续更新注记，见 §存疑） |
| S2 | Writing effective tools for agents — with agents | https://www.anthropic.com/engineering/writing-tools-for-agents | Anthropic（Ken Aizawa 等） | Published Sep 11, 2025 |
| S3 | Effective context engineering for AI agents | https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents | Anthropic（Applied AI team） | Published Sep 29, 2025 |
| S4 | What is the Model Context Protocol (MCP)? | https://modelcontextprotocol.io/ | MCP 官方 | 规范版本 **2026-07-28 (latest)**；页面无发布日期 |
| S5 | MCP Architecture | https://modelcontextprotocol.io/docs/learn/architecture | MCP 官方 | 同 S4（版本 2026-07-28） |
| S6 | MCP Server Features: Tools | https://modelcontextprotocol.io/docs/concepts/tools | MCP 官方 | 同 S4 |
| S7 | A Practical Guide to Building Agents (PDF, 34 页) | https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf | OpenAI | 正文未标注；PDF 元数据 `CreationDate: 2025-04-07` |
| S8 | 12-Factor Agents（README + 各 factor 页） | https://github.com/humanlayer/12-factor-agents | Dex Horthy / HumanLayer | 未标注（仓库 `pushed_at` 2025-09-21） |
| S8.2 | Factor 2 Own your prompts | https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-02-own-your-prompts.md | 同上 | 未标注 |
| S8.3 | Factor 3 Own your context window | https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-03-own-your-context-window.md | 同上 | 未标注 |
| S8.4 | Factor 4 Tools are just structured outputs | https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-04-tools-are-structured-outputs.md | 同上 | 未标注 |
| S8.5 | Factor 5 Unify execution state and business state | https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-05-unify-execution-state.md | 同上 | 未标注 |
| S8.6 | Factor 6 Launch/Pause/Resume | https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-06-launch-pause-resume.md | 同上 | 未标注 |
| S8.7 | Factor 7 Contact humans with tool calls | https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-07-contact-humans-with-tools.md | 同上 | 未标注 |
| S8.9 | Factor 9 Compact Errors | https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-09-compact-errors.md | 同上 | 未标注 |
| S8.10 | Factor 10 Small, Focused Agents | https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-10-small-focused-agents.md | 同上 | 未标注 |
| S9 | AG-UI Overview / Events | https://docs.ag-ui.com/ 与 https://docs.ag-ui.com/concepts/events | AG-UI Protocol（ag-ui-protocol/ag-ui, MIT） | 未标注；页面标注 **Documentation 1.0 Specification** |
| S10 | OpenAI Agents SDK: Agents / Tools | https://openai.github.io/openai-agents-python/agents/ 与 https://openai.github.io/openai-agents-python/tools/ | OpenAI | 未标注（仓库 `pushed_at` 2026-09-22） |
| S11 | CrewAI Concepts: Agents / Crews | https://docs.crewai.com/en/concepts/agents 与 https://docs.crewai.com/en/concepts/crews | CrewAI | 文档版本 **v1.15.22** |
| S12 | LangGraph Overview | https://docs.langchain.com/oss/python/langgraph/overview | LangChain（原 langchain-ai.github.io 已 301 至此） | 未标注 |
| S13 | How to think about agent frameworks（博客） | https://blog.langchain.dev/how-to-think-about-agent-frameworks/ | LangChain（Harrison Chase） | Published **April 20, 2025** |
| S14 | Pydantic AI 首页 | https://ai.pydantic.dev/ | Pydantic | 未标注 |

---

## (A) agent 的定义与「何时不该用 agent」

**A1｜workflow 与 agent 的官方分界是「谁来编排」**
- 出处：S1 https://www.anthropic.com/research/building-effective-agents
- 原文要点：**"Workflows are systems where LLMs and tools are orchestrated through predefined code paths." / "Agents, on the other hand, are systems where LLMs dynamically direct their own processes and tool usage, maintaining control over how they accomplish tasks."** Anthropic 把两者加起来叫 *agentic systems*。
- 对本项目的含义：「意图路由 → SubAgent」是典型的 workflow（predefined code path）；SubAgent 内部的工具循环才是 agent。评审时要能分别说清：哪条脉络是代码决定的，哪条是模型决定的。这一点直接影响能否定位 bug。

**A2｜默认不用 agent：先找最简方案**
- 出处：S1（同上）
- 原文要点：**"When building applications with LLMs, we recommend finding the simplest solution possible, and only increasing complexity when needed. This might mean not building agentic systems at all."** 并补充："For many applications, however, optimizing single LLM calls with retrieval and in-context examples is usually enough."
- 对本项目的含义：若某个意图（如「查作业」）能用单次 LLM + 检索解决，就不该引入 agent 循环。审核清单：每个 SubAgent 都要能回答「为什么不能用一次调用解决」。

**A3｜三条核心原则（simplicity / transparency / ACI）**
- 出处：S1「Summary」
- 原文要点：**1. Maintain simplicity in your agent's design. 2. Prioritize transparency by explicitly showing the agent's planning steps. 3. Carefully craft your agent-computer interface (ACI) through thorough tool documentation and testing.**
- 对本项目的含义：第 2 条对教育产品是硬需求——家长的界面必须能展示 agent 的规划步骤；自研内核的 SSE 事件流必须能承载 planning steps（不只是最终文本）。

**A4｜agent 的最小定义 =「能够在环境里循环调工具」**
- 出处：S3 https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents ；S1「Agents」节
- 原文要点：S3 说他们现在倾向一个简单定义：**"LLMs autonomously using tools in a loop."** 同时 S1 强调：**"It's crucial for the agents to gain 'ground truth' from the environment at each step (such as tool call results or code execution) to assess its progress."**
- 对本项目的含义：工具返回值就是 ground truth；如果工具返回「假装成功」的字符串，整个内核失去校准源。

**A5｜OpenAI 的判据：不用 LLM 控制 workflow 执行，就不是 agent**
- 出处：S7 https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf （p.4）
- 原文要点：**"Agents are systems that independently accomplish tasks on your behalf." / "Applications that integrate LLMs but don't use them to control workflow execution—think simple chatbots, single-turn LLMs, or sentiment classifiers—are not agents."**
- 对本项目的含义：给外部描述这个系统时要诚实——若大多路径仍是代码编排，应叫 workflow-based agentic system，而不是「自主 agent」。

**A6｜OpenAI 的「何时该建 agent」三判据**
- 出处：S7（p.5–6）
- 原文要点：**01 Complex decision-making；02 Difficult-to-maintain rules；03 Heavy reliance on unstructured data。** 并明确收边：**"Before committing to building an agent, validate that your use case can meet these criteria clearly. Otherwise, a deterministic solution may suffice."**
- 对本项目的含义：中小学场景最贴合的是第 3 条（自然语言、图片题面）；「规则复杂」类（如批改流程、权限判定）不该交给 LLM。

---

## (B) workflow 模式与路由

**B1｜五种 workflow 模式，附原文「何时用」判据**
- 出处：S1 https://www.anthropic.com/research/building-effective-agents
- 原文要点（五种，附原文「何时用」）：
  - **Prompt chaining**：把任务拆成固定子步骤，原文："The main goal is to trade off latency for higher accuracy, by making each LLM call an easier task." 可加 programmatic gate。
  - **Routing**："classifies an input and directs it to a specialized followup task… This workflow allows for separation of concerns, and building more specialized prompts." 且 "Without this workflow, optimizing for one kind of input can hurt performance on other inputs."
  - **Parallelization**：两种变体 **sectioning**（拆独立子任务并行）与 **voting**（同一任务跑多次）。原文："For complex tasks with multiple considerations, LLMs generally perform better when each consideration is handled by a separate LLM call."
  - **Orchestrator-workers**：与 parallelization 形似但不同——**"subtasks aren't pre-defined, but determined by the orchestrator based on the specific input."**
  - **Evaluator-optimizer**：一条 LLM 生成、另一条评估并反馈。适用判据原文："first, that LLM responses can be demonstrably improved when a human articulates their feedback; and second, that the LLM can provide such feedback."
- 对本项目的含义：自研的「意图路由」正是 Anthropic 定义的 **routing** 模式；SubAgent 之间若是预定义分工则是 workflow，若由主 agent 动态派工则是 orchestrator-workers。二者对可测试性的要求完全不同，必须在文档里写明属于哪一种。

**B2｜路由的隐藏价值：可以按难度分流模型**
- 出处：S1「Routing」例子
- 原文要点：**"Routing easy/common questions to smaller, cost-efficient models like Claude Haiku 4.5 and hard/unusual questions to more capable models like Claude Sonnet 4.5 to optimize for best performance."**
- 对本项目的含义：教育场景高并发、多数请求简单——路由层天然是成本优化的第一道阀门，而不是只做「意图分类」。

**B3｜模式可混合，但复杂度必须证明有效**
- 出处：S1「Combining and customizing these patterns」
- 原文要点：**"These building blocks aren't prescriptive… you should consider adding complexity *only* when it demonstrably improves outcomes."**（斜体为原文）
- 对本项目的含义：每新增一个 SubAgent/工具，都要有对应 eval 分数支撑，否则回滚。

**B4｜OpenAI：先榨干单 agent，再谈多 agent**
- 出处：S7（p.16）
- 原文要点：**"Our general recommendation is to maximize a single agent's capabilities first. More agents can provide intuitive separation of concepts, but can introduce additional complexity and overhead, so often a single agent with tools is sufficient."** 拆分判据两条：**Complex logic**（条件分支过多、模板难扩展）与 **Tool overload**（工具**重叠**）。
- 对本项目的含义：SubAgent 数量应有「分裂理由」，每条理由对应 S7 的两种之一。

**B5｜OpenAI 的两种多 agent 形态**
- 出处：S7（p.17–21）；S10 文档同构
- 原文要点：**Manager (agents as tools)**——中心 manager 通过 tool call 调用专业 agent，**"This pattern is ideal for workflows where you only want one agent to control workflow execution and have access to the user."**；**Decentralized (handoffs)**——peer agent 单向移交执行权。原文总结："Regardless of the orchestration pattern, the same principles apply: keep components flexible, composable, and driven by clear, well-structured prompts."
- 对本项目的含义：中小学 App 只有一个用户会话入口，应优先 **manager 模式**（保持单一「面对用户」的 agent），避免 handoff 造成上下文所有权不清。

---

## (C) 工具设计原则

**C1｜工具是「确定性系统与非确定性 agent 之间的契约」**
- 出处：S2 https://www.anthropic.com/engineering/writing-tools-for-agents
- 原文要点：**"Tools are a new kind of software which reflects a contract between deterministic systems and non-deterministic agents."** 并给出核心论证：**"instead of writing tools and MCP servers the way we'd write functions and APIs for other developers or systems, we need to design them for agents."**
- 对本项目的含义：这是「面向模型的工具 ≠ 面向人的 API」的一手出处。反例：把后端 REST 端点逐个 1:1 包成工具，就算 offer 给模型也不好用。

**C2｜不要 1:1 包 API，要按「高价值工作流」重构**
- 出处：S2「Choosing the right tools for agents」
- 原文要点：**"More tools don't always lead to better outcomes. A common error we've observed is tools that merely wrap existing software functionality or API endpoints—whether or not the tools are appropriate for agents."** 建议："We recommend building a few thoughtful tools targeting specific high-impact workflows… In the address book case, you might choose to implement a `search_contacts` or `message_contact` tool instead of a `list_contacts` tool." 工具应整合多步操作："Tools can consolidate functionality, handling potentially *multiple* discrete operations (or API calls) under the hood."
- 对本项目的含义：与其暴露 `get_student / list_homework / get_score`，不如做 `get_student_learning_context`。这同时也省 token。

**C3｜工具过多/重叠会「分散注意力」**
- 出处：S2；S3 补强
- 原文要点：S2 **"Too many tools or overlapping tools can also distract agents from pursuing efficient strategies."**；S3 更狠：**"If a human engineer can't definitively say which tool should be used in a given situation, an AI agent can't be expected to do better."**
- 对本项目的含义：这条可直接做成评审 checklist——给两个工具描述，问三个人类工程师能否确定该用哪个；答不出来就该合并。

**C4｜命名空间：prefix vs suffix 的效果要实测**
- 出处：S2「Namespacing your tools」
- 原文要点：**"Namespacing (grouping related tools under common prefixes) can help delineate boundaries between lots of tools; MCP clients sometimes do this by default."** 例子 `asana_search` / `jira_search` / `asana_projects_search`。且 **"We have found selecting between prefix- and suffix-based namespacing to have non-trivial effects on our tool-use evaluations. Effects vary by LLM."**
- 对本项目的含义：工具命名前缀应与业务域一致（如 `homework_*`、`plan_*`），且 prefix/suffix 的选择要有 eval 支撑，别凭惯例決定。

**C5｜返回「有意义的上下文」，而非底层标识符**
- 出处：S2「Returning meaningful context from your tools」
- 原文要点：**"They should prioritize contextual relevance over flexibility, and eschew low-level technical identifiers (for example: `uuid`, `256px_image_url`, `mime_type`)."**；**"merely resolving arbitrary alphanumeric UUIDs to more semantically meaningful and interpretable language (or even a 0-indexed ID scheme) significantly improves Claude's precision in retrieval tasks by reducing hallucinations."** 需要 ID 做后续调用时，可用 `response_format` enum（`concise`/`detailed`）控制。同时承认结构无万能解：**"there is no one-size-fits-all solution"**（XML/JSON/Markdown 需按 eval 选）。
- 对本项目的含义：DB 主键（student_id UUID）直接进上下文是明确反例；应返回姓名/年级/错题知识点等自然语言可判定字段。

**C6｜token 效率：分页/过滤/截断 + 有默认值的限流**
- 出处：S2「Optimizing tool responses for token efficiency」
- 原文要点：**"We suggest implementing some combination of pagination, range selection, filtering, and/or truncation with sensible default parameter values for any tool responses that could use up lots of context. For Claude Code, we restrict tool responses to 25,000 tokens by default."** 并提示原文："We expect the effective context length of agents to grow over time, but the need for context-efficient tools to remain."
- 对本项目的含义：每个返回列表/文档的工具都必须有上限参数；这条最容易被自研内核漏掉。

**C7｜错误信息要「可被模型消费」**
- 出处：S2「Optimizing tool responses…」
- 原文要点：**"if a tool call raises an error (for example, during input validation), you can prompt-engineer your error responses to clearly communicate specific and actionable improvements, rather than opaque error codes or tracebacks."**
- 对本项目的含义：工具层的异常文案是 agent 行为的一部分，应与 prompt 同版本管理（配合 D4）。

**C8｜工具描述/规格本身要 prompt-engineering**
- 出处：S2「Prompt-engineering your tool descriptions」；S1 附录 2
- 原文要点：**"Because these are loaded into your agents' context, they can collectively steer agents toward effective tool-calling behaviors."** 写描述时设想对象：**"think of how you would describe your tool to a new hire on your team."** 参数命名不许含糊：**"instead of a parameter named `user`, try a parameter named `user_id`."** S1 附录 2 补两条：给模型足够 token "think"、格式要贴近互联网上自然出现的文本；以及 **Poka-yoke**（"Change the arguments so that it is harder to make mistakes."）。他们在 SWE-bench 上 "actually spent more time optimizing our tools than the overall prompt"，并把相对路径改成绝对路径后模型再无失误。
- 对本项目的含义：工具描述应进 Git、可 review、可 A/B；这是投入产出比最高的一块。

**C9｜工具必须服务于「可验证 eval」**
- 出处：S2「Running an evaluation」
- 原文要点：评测循环建议用最朴素的 agent loop：**"Use simple agentic loops (`while`-loops wrapping alternating LLM API and tool calls): one loop for each evaluation task."** 除准确率外还要收集 **"total runtime… total number of tool calls, the total token consumption, and tool errors"**；"Tracking tool calls can help reveal common workflows that agents pursue and offer some opportunities for tools to consolidate."
- 对本项目的含义：极薄内核在这里是优势——自写的 while 循环与官方建议的评测写法一致，比黑盒框架更好插桩。

**C10｜工具的分类：data / action / orchestration**
- 出处：S7（p.9）
- 原文要点：**"Each tool should have a standardized definition, enabling flexible, many-to-many relationships between tools and agents."** 三类：Data（取上下文）、Action（写/发/handoff 给人类）、**Orchestration（"Agents themselves can serve as tools for other agents"）**。
- 对本项目的含义："SubAgent 作为工具" 属于 OpenAI 明确归一化的第三类，不需要另发明概念。

---

## (D) 上下文 / 状态管理

**D1｜上下文是有限资源，收益递减**
- 出处：S3 https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- 原文要点：**"Context… must be treated as a finite resource with diminishing marginal returns."** 机制解释是 transformer 的 n² pairwise relationships 与 "attention budget"："Every new token introduced depletes this budget by some amount."
- 对本项目的含义：这是「为什么 SubAgent 之间不能直接共享 messages」的理论依据。

**D2｜目标函数：最小的高信号 token 集合**
- 出处：S3
- 原文要点：**"good context engineering means finding the *smallest* *possible* set of high-signal tokens that maximize the likelihood of some desired outcome."** system prompt 要在"right altitude"：**"specific enough to guide behavior effectively, yet flexible enough to provide the model with strong heuristics"**，两端反例是硬编码 if-else 与过度笼统。
- 对本项目的含义：每个 SubAgent 的 system prompt 应独立审视，而不是复制一个「通用教育助手」长文档。

**D3｜长任务三件套：compaction / 结构化笔记 / sub-agent**
- 出处：S3「Context engineering for long-horizon tasks」
- 原文要点：
  - **Compaction**："taking a conversation nearing the context window limit, summarizing its contents, and reinitiating a new context window with the summary." 最轻量的做法：**"One of the safest lightest touch forms of compaction is tool result clearing."**
  - **Structured note-taking**："the agent regularly writes notes persisted to memory outside of the context window. These notes get pulled back into the context window at later times."
  - **Sub-agent architectures**："specialized sub-agents can handle focused tasks with clean context windows… Each subagent might explore extensively, using tens of thousands of tokens or more, but returns only a condensed, distilled summary of its work (often 1,000-2,000 tokens)."
  - 选择依据（原文）：compaction 适合多轮对话式；note-taking 适合有清晰里程碑的迭代；multi-agent 适合 "complex research and analysis where parallel exploration pays dividends"。
- 对本项目的含义：**这是对自研内核最强的背书之一**——「SubAgent 返回精炼摘要」正是官方推荐的第三件套；但也要检查：是否真的实现了 compaction（工具结果清理）？多数自研内核没有。

**D4｜12-Factor Factor 3：自己控制上下文格式，不要迷信标准 message 格式**
- 出处：S8.3 https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-03-own-your-context-window.md
- 原文要点：**"You don't necessarily need to use standard message-based formats for conveying context to an LLM."** 核心心智模型原文："At any given point, your input to an LLM in an agent is 'here's what's happened so far, what's the next step'"。并明确排除 tuning/训练自己的模型等手段。
- 对本项目的含义：我们有权不用标准 messages 数组来承载上下文（例如把历史事件压缩成结构化块再放进单条消息），但代价是失去一些生态工具兼容性；折中做法是底层存标准格式、喂给模型前另做一次渲染。

**D5｜12-Factor Factor 5：执行状态与业务状态统一**
- 出处：S8.5 https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-05-unify-execution-state.md
- 原文要点：定义 **execution state**（current step / waiting status / retry counts）与 **business state**（已发生的事件流）；结论 **"If possible, SIMPLIFY - unify these as much as possible."** 好处 7 条：**Simplicity / Serialization（"The thread is trivially serializable/deserializable"）/ Debugging / Flexibility（加新状态=加新事件类型）/ Recovery（加载 thread 即可续跑）/ Forking / Human Interfaces and Observability（"Trivial to convert a thread into a human-readable markdown or a rich Web app UI"）**。session id、密码上下文等不能进上下文的东西要最小化。
- 对本项目的含义：**最该对照评审的一条。** 若 FastAPI 侧存在"agent 运行时状态表"与"业务事件表"两套，就是在重复官方点名的复杂度。

**D6｜12-Factor Factor 10：agent 要小，步数要有上限**
- 出处：S8.10 https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-10-small-focused-agents.md
- 原文要点：**"Rather than building monolithic agents that try to do everything, build small, focused agents that do one thing well. Agents are just one building block in a larger, mostly deterministic system."** 量化经验：**"By keeping agents focused on specific domains with 3-10, maybe 20 steps max, we keep context windows manageable and LLM performance high."**
- 对本项目的含义：给每个 SubAgent 设 max_step，并记录理由；超过 20 步的 SubAgent 应拆分。

**D7｜12-Factor Factor 4：工具调用 = 结构化输出**
- 出处：S8.4 https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-04-tools-are-structured-outputs.md
- 原文要点：**"tools are just structured output from your LLM that triggers deterministic code."** 关键推论：**"The LLM decides what to do, but your code controls how it's done. Just because an LLM 'called a tool' doesn't mean you have to go execute a specific corresponding function in the same way every time."**
- 对本项目的含义：工具执行器天然可以有权限门、限流、mock、副作用隔离——不要让它退化成 `globals()[name](**args)`。

---

## (E) 错误与失败边界

**E1｜把错误压缩回上下文让它自愈，但要设上限**
- 出处：S8.9 https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-09-compact-errors.md
- 原文要点：**"One of these benefits of agents is 'self-healing' - for short tasks, an LLM might call a tool that fails. Good LLMs have a fairly good chance of reading an error message or stack trace and figuring out what to change in a subsequent tool call."** 并给出 `errorCounter` 模式：**"limit to ~3 attempts of a single tool"**；否则 "break the loop, reset parts of the context window, escalate to a human"。作者也警告："if you do this TOO much, your agent will start to spin out and might repeat the same error over and over again."
- 对本项目的含义：工具循环必须有 per-tool 失败计数 + 全局失败计数；这是最低限度的安全网。

**E2｜停止条件是一等公民**
- 出处：S1「Agents」
- 原文要点：**"it's also common to include stopping conditions (such as a maximum number of iterations) to maintain control."** 且 "The autonomous nature of agents means higher costs, and the potential for compounding errors. We recommend extensive testing in sandboxed environments, along with the appropriate guardrails."
- 出处：S7（p.14）同样要求 run 有 exit condition：**"Common exit conditions include tool calls, a certain structured output, errors, or reaching a maximum number of turns."**
- 对本项目的含义：max_turns 应存在服务端配置里并可热改，而不是在循环里写死常量。

**E3｜OpenAI 的 guardrails 分层清单**
- 出处：S7（p.24–27）
- 原文要点：Relevance classifier、Safety classifier、PII filter、Moderation、**Tool safeguards**（"Assess the risk of each tool available to your agent by assigning a rating—low, medium, or high—based on factors like read-only vs. write access, reversibility, required account permissions, and financial impact. Use these risk ratings to trigger automated actions, such as pausing for guardrail checks before executing high-risk functions or escalating to a human if needed."）、Rules-based protections、Output validation。落地启发式三条：先做数据与内容安全；按真实 edge case 增量加；兼顾安全与体验。
- 对本项目的含义：**工具级风险分级（low/medium/high）是可以直接照搬的**：涉及"给家长发消息""修改学生作业/成绩"的工具必须是 high + 人工确认。

**E4｜中小学特殊要求：未成年人场景的输出校验**
- 出处：[推断]（基于 E3 的 Output validation 与 Anthropic 的建议 extrapolation）
- 说明：一手来源没有专门针对"教育/app未成年人"的条款；不要把它写成"OpenAI 明确要求"。

---

## (F) 人工介入与权限

**F1｜把「找人」做成一个工具调用**
- 出处：S8.7 https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-07-contact-humans-with-tools.md
- 原文要点：起点是一个观察——**"By default, LLM APIs rely on a fundamental HIGH-STAKES token choice: Are we returning plaintext content, or are we returning structured data?"** 建议做法：**"You might get better results by having the LLM *always* output json, and then declare it's intent with some natural language tokens like `request_human_input` or `done_for_now`."** 流程示例：收到该 intent → 写 "human_input_requested" 事件 → 保存 thread → 通知人类 → 跳出循环；回复通过 webhook 带着 thread id 回来再继续。
- 对本项目的含义：人工介入应是内核里有名字的一等 intent（而不是「工具抛异常然后前端兜住」）。这也自然是 pause/resume 的实现基础。

**F2｜OpenAI：人工介入的两个触发条件**
- 出处：S7（p.31）
- 原文要点：**Exceeding failure thresholds**（"Set limits on agent retries or actions. If the agent exceeds these limits (e.g., fails to understand customer intent after multiple attempts), escalate to human intervention."）与 **High-risk actions**（"Actions that are sensitive, irreversible, or have high stakes should trigger human oversight until confidence in the agent's reliability grows. Examples include canceling user orders, authorizing large refunds, or making payments."）
- 对本项目的含义：与 E1 的 error counter 串起来——同一条链接 exposes 给家长/老师。

**F3｜MCP 明确要求 human-in-the-loop 能拒绝工具调用**
- 出处：S6 https://modelcontextprotocol.io/docs/concepts/tools
- 原文要点：**"For trust & safety and security, there SHOULD always be a human in the loop with the ability to deny tool invocations."** 具体三条：UI 要清楚表明暴露了哪些工具、调用时要有视觉指示、对操作要有确认提示。
- 对本项目的含义：即便现在不用 MCP，这份 UI 清单也可作为对齐目标；自研 SSE 事件里 TOOL_CALL_START 就应能让前端渲染确认卡。

**F4｜12-Factor Factor 6：暂停/恢复必须能在"选中工具之后、执行之前"发生**
- 出处：S8.6 https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-06-launch-pause-resume.md
- 原文要点：**"It should be easy for users, apps, pipelines, and other agents to launch an agent with a simple API."** Agents 与其编排代码应能在长耗时操作时暂停；**"External triggers like webhooks should enable agents to resume from where they left off without deep integration with the agent orchestrator."** 关键 Notes：**"often AI orchestrators will allow for pause and resume, but not between the moment of tool selection and tool execution."**
- 对本项目的含义：**这是审批类功能的可行性硬指标**——若要实现"agent 想给家长发消息 → 老师点同意 → 继续"，内核必须支持工具执行前的挂起点；AG-UI 也专门为此引入了 interrupt（`RunFinished` 的 `outcome: {type:"interrupt"}`）。

**F5｜guardrails 默认「乐观执行 + 并发检查」**
- 出处：S7（p.31）；S10 文档一致
- 原文要点：**"The Agents SDK treats guardrails as first-class concepts, relying on optimistic execution by default. Under this approach, the primary agent proactively generates outputs while guardrails run concurrently, triggering exceptions if constraints are breached."**
- 对本项目的含义：安全护栏不要串行阻塞首 token（影响体感），而是并发跑、命中再终止/改写。这条直接决定流式体验设计。

---

## (G) 前端 / 协议层

**G1｜为什么需要类型化事件流（AG-UI 的一手论证）**
- 出处：S9 https://docs.ag-ui.com/
- 原文要点：**"Agentic applications break the simple request/response model that dominated frontend-backend development in the pre-agentic era."** 列出的 agent 特性：long-running 且要流式吐中间产物；**"Agents are nondeterministic and can control application UI nondeterministically."**；同时混合结构化与非结构化 IO；需要 user-interactive composition（递归调 sub-agent）。AG-UI 自我定位：**"an open, lightweight, event-based protocol that standardizes how AI agents connect to user-facing applications."**
- 对本项目的含义：**这正是自研 SSE 事件流存在的理由**，且论证来自一手规范而非博客。缺什么可从下面的事件清单反推。

**G2｜事件类型全集（AG-UI 文档 1.0）**
- 出处：S9 https://docs.ag-ui.com/concepts/events
- 原文要点（按文档分类，1.0 用 PascalCase 事件名）：
  - **生命周期**：`RunStarted`（threadId/runId/parentRunId/input）、`RunFinished`、`RunError`、`StepStarted`、`StepFinished`。原文约束：**"The RunStarted and either RunFinished or RunError events are mandatory, forming the boundaries of an agent run. Step events are optional."**
  - **文本消息**：`TextMessageStart` / `TextMessageContent`（delta）/ `TextMessageEnd`，另有便捷事件 `TextMessageChunk`（客户端自动展开成三元组）。
  - **工具调用**：`ToolCallStart` / `ToolCallArgs` / `ToolCallEnd` / `ToolCallResult` / `ToolCallChunk`。
  - **状态同步**：`StateSnapshot` + `StateDelta`（**"delta Array of JSON Patch operations (RFC 6902)"**）、`MessagesSnapshot`。
  - **其它**：`Raw`（外部事件透传容器）、**`Custom`（"comelib extension mechanism… with application-defined semantics"、"This mechanism allows for protocol extensions without requiring formal specification changes."）**、`Reasoning*`（含 `ReasoningEncryptedValue`）、**Subagent 事件**（`SubagentStarted/Finished/Error` + 大多数事件上的 `subagentRunId` 归因）。
  - 所有事件共享基础属性 type / timestamp / rawEvent / metadata。
- 对本项目的含义：对照检查自研 SSE 是否至少覆盖了生命周期边界（必须有确定开始/终止事件）、工具调用三段式、以及一个和 `Custom` 等价的扩展通道。缺少 `Raw`/`Custom` 时，业务方只能靠往 JSON 里偷偷塞字段，最终失控。

**G3｜AG-UI 不是 web 专用，Flutter App 也在射程内**
- 出处：S9（overview 页「Clients」节）
- 原文要点：**"An AG-UI client does not have to be a web application. The protocol describes an event stream rather than a rendering target, so a terminal, a mobile app, or a chat platform can each act as a client."**
- 对本项目的含义：把 SSE 事件设计成"传输/渲染无关"是官方立场；Flutter 侧不应该因为不是 React 就裁掉协议结构。

**G4｜Pydantic AI 已内置 AG-UI / Vercel AI 的 UI event stream**
- 出处：S14 https://ai.pydantic.dev/
- 原文要点：**"UI event streams (AG-UI, Vercel AI) connect it to your own frontend or anything else"**（列在各 interface 之一）。
- 对本项目的含义：如果未来换框架，自研的 SSE schema 不一定白写——对齐 AG-UI 命名可直接接上。

---

## (H) 框架的取舍（自写 vs 框架）

**H1｜Anthropic：从最简开始，框架要在上生产前减掉抽象层**
- 出处：S1 https://www.anthropic.com/research/building-effective-agents
- 原文要点：**"We suggest that developers start by using LLM APIs directly: many patterns can be implemented in a few lines of code. If you do use a framework, ensure you understand the underlying code. Incorrect assumptions about what's under the hood are a common source of customer error."** 收尾更重：**"Frameworks can help you get started quickly, but don't hesitate to reduce abstraction layers and build with basic components as you move to production."**
- 对本项目的含义：**这是自研内核最强的合法性依据**，但不是免死金牌——前提是你真的能读懂自己那层薄内核的下游代码。

**H2｜LangChain 官方：多数框架只提供「agent 抽象」，而抽象会遮蔽上下文**
- 出处：S13 https://blog.langchain.dev/how-to-think-about-agent-frameworks/ （April 20, 2025）
- 原文要点：**"Most agentic frameworks are neither declarative or imperative orchestration frameworks, but rather just a set of agent abstractions."** / **"Agent abstractions can make it easy to get started, but they can often obfuscate and make it hard to make sure the LLM has the appropriate context at each step."** / **"Agentic systems of all shapes and sizes (agents or workflows) all benefit from the same set of helpful features, which can be provided by a framework, or built from scratch."** 核心判断：**"The hard part of building reliable agentic systems is making sure the LLM has the appropriate context at each step."**
- 对本项目的含义：竞品方（LangChain）自己也承认「可以自建」；选型标准不是"有没有框架"，而是"你能不能在每一步准确控制喂给模型的上下文"。

**H3｜LangGraph 官方劝退：新手别直接用 LangGraph**
- 出处：S12 https://docs.langchain.com/oss/python/langgraph/overview
- 原文要点：**"LangGraph is very low-level, and focused entirely on agent orchestration."** / **"If you are just getting started with agents or want a higher-level abstraction, we recommend you use LangChain's agents that provide prebuilt architectures for common LLM and tool-calling loops."** 正面价值清单（S13）：**short term memory / long term memory / human-in-the-loop / human-on-the-loop（含 time travel）/ streaming / debugging & observability / fault tolerance / optimization**；S13 直言：**"For most agent frameworks, [abstractions] is the sole value they provide."**
- 对本项目的含义：**自写 vs 框架的取舍点非常具体**——上面 8 项任何一项变成刚需（尤其是 durable execution / time travel / 可视化 trace），自研成本会陡增；在此之前，自写是合理的。

**H4｜12-Factor 的行业观察：产品化的 agent 大多是「披着皮的确定性代码」**
- 出处：S8 https://github.com/humanlayer/12-factor-agents
- 原文要点：**"most of the products out there billing themselves as 'AI Agents' are not all that agentic. A lot of them are mostly deterministic code, with LLM steps sprinkled in at just the right points to make the experience truly magical."** 以及：**"Agents, at least the good ones, don't follow the ['here's your prompt, here's a bag of tools, loop until you hit the goal'] pattern. Rather, they are comprised of mostly just software."** 结论性建议：**"The fastest way I've seen for builders to get good AI software in the hands of customers is to take small, modular concepts from agent building, and incorporate them into their existing product."**
- 对本项目的含义：**这条几乎就是给本项目量身写的**——把小而模块化的 agent 概念嵌进既有产品（Flutter + FastAPI），而不是 greenfield 重写。注意这是个人项目/作者的从业观察，不是大厂官方标准 [推断权重]。

**H5｜12-Factor Factor 2：prompt 不能外包给框架**
- 出处：S8.2 https://github.com/humanlayer/12-factor-agents/blob/main/content/factor-02-own-your-prompts.md
- 原文要点：**"Don't outsource your prompt engineering to a framework."** 对黑盒式 `Agent(role=…, goal=…, tools=[…])` 的评价：**"This is great for pulling in some TOP NOTCH prompt engineering to get you started, but it is often difficult to tune and/or reverse engineer to get exactly the right tokens into your model."** 主张把 prompt 当一等代码，好处 5 条（Full Control / Testing and Evals / Iteration / Transparency / Role Hacking），并强调："I don't know what's the best prompt, but I know you want the flexibility to be able to try EVERYTHING."
- 对本项目的含义：prompt 必须在仓库里、可 diff、可测，不能藏在框架默认模板里。

**H6｜Pydantic AI 的自我定位（可作为"轻量 vs 全栈"的另一个锚点）**
- 出处：S14 https://ai.pydantic.dev/
- 原文要点：**"Pydantic AI is the Python AI SDK: a typed, extensible agent loop with every model a string swap away."** 四个卖点：Typed end to end、Measured not vibes（OpenTelemetry-native + Pydantic Evals，"tests agent behavior the way pytest tests code"）、**Batteries, composably**（"One primitive, the capability, bundles tools, instructions, hooks, and model settings into reusable units… Or skip code entirely with YAML/JSON agent specs."）、Durable execution（Temporal/DBOS/Prefect/Restate/Lambda/Airflow/Kitaru，"with human-in-the-loop approval built in"）。
- 对本项目的含义：如果 FastAPI 已重度用 Pydantic，这是自写循环的最佳折中（保留 own your loop，换来类型与 eval）；注意它也提供 AG-UI 事件流，替换成本低于换 LangGraph。

---

## (I) 注册与装配机制（显式 vs 装饰器 vs 发现）

**I1｜OpenAI Agents SDK：装饰器只负责"把函数变成工具对象"，注册仍然必须显式传列表**
- 出处：S10 https://openai.github.io/openai-agents-python/agents/ 与 https://openai.github.io/openai-agents-python/tools/
- 原文要点：
  - Agents 定义：**"An agent is a large language model (LLM) configured with instructions, tools, and optional runtime behavior such as handoffs, guardrails, and structured outputs."** 工具通过 `Agent(tools=[...])` 显式装配；多 agent 也是显式：`handoffs=[booking_agent, refund_agent]` 或 `tools=[booking_agent.as_tool(tool_name="booking_expert", ...)]`。
  - Tools 页原文：**"You can use any Python function as a tool. The Agents SDK will set up the tool automatically: The name of the tool will be the name of the Python function… Tool description will be taken from the docstring… The schema for the function inputs is automatically created from the function's arguments."** ——注意这里"automatically"指的是**生成 schema/描述**，不是把它塞进某个 agent。
  - 文档中的示范代码仍然是 `agent = Agent(name="Assistant", tools=[fetch_weather, read_file])`；且警告直接调用被装饰函数会绕过运行时：**"calling it directly bypasses the tool runtime pipeline, including schema validation, context injection, guardrails, timeouts, failure handling, and tracing."**
- 对本项目的含义：**`@tool` ≠ 自动注册，这只是给 OpenAI SDK 的事实回答**：装饰器 = schema 提取糖 + 运行时包装，装配永远显式。自研内核里若出现"装饰器自动注册到全局注册表"，就偏离了主流 SDK 的显式约定。

**I2｜OpenAI SDK：连"要不要用它的循环"都给了显式开关**
- 出处：S10 https://openai.github.io/openai-agents-python/agents/
- 原文要点：**"The SDK uses the Responses API by default for OpenAI models, but the distinction here is orchestration: Agent plus Runner lets the SDK manage turns, tools, guardrails, handoffs, and sessions for you. If you want to own that loop yourself, use the Responses API directly instead."**
- 对本项目的含义：官方区分"编排层"与"模型层"——自研内核处在编排层，完全可以用官方 SDK 的模型调用/工具 schema，不必二选一。

**I3｜CrewAI：官方文档当前推荐的是显式定义/显式装配，装饰器只留给 classic 项目**
- 出处：S11 https://docs.crewai.com/en/concepts/agents （v1.15.22）与 https://docs.crewai.com/en/concepts/crews
- 原文要点：
  - **"There are two common ways to create agents in CrewAI: using JSONC project configuration (recommended for new crews) or defining them directly in code."** 即：`agents/<name>.jsonc` + `crew.jsonc`（`"agents": ["researcher"]`、`"tasks": [... {"agent": "researcher"}]`），或直接 `Agent(role=…, goal=…, backstory=…, tools=[SerperDevTool()])`。
  - 装饰器的定位被明确降格：**"Classic projects created with `crewai create crew <name> --classic` use config/agents.yaml and a @CrewBase class in crew.py. This remains supported for teams that want Python decorators or existing YAML projects."**
- 对本项目的含义：**"装饰器 = 自动注册"这个刻板印象在当前 CrewAI 官方推荐路径里并不成立**——推荐路径是无装饰器的配置化/显式装配。评审自研注册表时，"业界都用装饰器自动发现"这个前提应被否定（至少对这两个 SDK 不成立）。

**I4｜真正的"发现机制"不在 SDK，而在 MCP**
- 出处：S5 https://modelcontextprotocol.io/docs/learn/architecture ；S6 https://modelcontextprotocol.io/docs/concepts/tools
- 原文要点：MCP 的三个 server primitive（原文定义）：**"Tools: Executable functions that AI applications can invoke to perform actions" / "Resources: Data sources that provide contextual information" / "Prompts: Reusable templates that help structure interactions with language models"**。发现机制是 capability negotiation：**"Capability Discovery: The client declares its capabilities in io.modelcontextprotocol/clientCapabilities on every request, and the server returns its own capabilities object from server/discover. This tells each party which primitives the other can handle (tools, resources, prompts)… so unsupported operations are never attempted."** 工具清单用 `tools/list` 拉取；server 必须声明 `tools` capability（`listChanged` 表示是否会推送变更通知）。另有性能约束原文：**"Servers SHOULD return tools in a deterministic order… Deterministic ordering enables clients to reliably cache the tool list and improves LLM prompt cache hit rates when tools are included in model context."**
- 对本项目的含义：**把"动态发现"留给 MCP，而不是在进程内搞魔法注册**——需要跨服务动态工具时走 MCP；进程内的工具表应当是一份可审计的显式清单。另外"工具顺序要稳定"这条直接影响 prompt cache 命中率，容易被自研内核忽略（例如用 dict 遍历或按注册时间戳排序）。

---

## 未能证实 / 存疑

1. **OpenAI《A Practical Guide》的发布日期**：PDF 正文全篇未标注日期，只在 PDF 元数据里读到 `CreationDate: D:20250407142051Z`（2025-04-07）。外部常说的具体发布月份无法从一手段据证实。→ 表中记为 "2025-04-07（PDF 元数据）"，非正文标注。
2. **「AG-UI 规范当前是 draft」不成立**：AG-UI 文档站标注的是 **Documentation 1.0 Specification**；只有提案性质的页面显式标注 **DRAFT**（如 Meta Events：*"These events are currently in draft status and may change before finalization."*）。另：1.0 文档中的事件名是 PascalCase（`RunStarted`、`TextMessageStart`、`ToolCallStart`、`StateDelta`），我在官方页面里没有找到 `RUN_STARTED` / `TEXT_MESSAGE_*` 这种全大写下划线的写法（`THINKING_*` 系列只出现在「已废弃事件」列表中，被 `REASONING_*` 取代）。→ 若项目引用了旧式大写事件名，应以 1.0 文档为准复核。
3. **Anthropic《Building effective agents》的日期与内容版本不一致**：页面标注 Dec 19, 2024，但正文已出现 2025 年后的内容（顶部有指向 Claude Managed Agents 的更新注记，路由示例提到 Claude Haiku 4.5 / Sonnet 4.5）。因此「这段话是 2024 原版」无法证实；本清单按**当前页面内容**引用。
4. **12-Factor Agents 无发布日期/版本号**：README 与各 factor 页均未标注日期，只能用仓库 `pushed_at`（2025-09-21）作参考；作者 Dex Horthy 在文中自述其为个人/团队经验观察（"I've tried every agent framework out there… I've talked to a lot of really strong founders"），**不是官方标准**。引用时应降级为"行业实践建议"。
5. **LangGraph 官方没有「何时不需要 graph」的原话**：官网（S12）只有反向表述（LangGraph 很底层，新手建议用 LangChain 高层 agents）；明确讨论"agent 抽象会遮蔽上下文""可以在 from scratch 自建"的是官方博客 S13，而非 API 文档。
6. **未能找到 CrewAI 关于 `@tool` 装饰器自动注册的一手说明**：当前抓取的 Agents/Tools/Crews 三页中，`@tool` 主要出现在集成文档与其他 SDK 的对照里；"装饰是否等于自动注册"对 CrewAI **无法直接证实**，只能用 I3 的替代事实（官方推荐路径是无装饰器的 JSONC/显式代码）来旁证。
7. **LangGraph 官网 URL 变更**：https://langchain-ai.github.io/langgraph/ 现在 301 到 https://docs.langchain.com/oss/python/langgraph/overview；引用旧 URL 会在未来失效。
8. **未找到任何一手来源专门讨论「中小学/教育/未成年人」场景的 agent 架构要求**：所有涉及安全的内容都来自通用条款（S7 guardrails、S6 human-in-the-loop）。E4 条目为 [推断]。
