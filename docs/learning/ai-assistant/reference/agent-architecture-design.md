# 如何设计一个 agent 架构，并把它接入业务系统

> **这是「设计法」，不是「本仓说明书」。** 前三课讲 openedu 现状，这一份讲的是通用的判断顺序：
> 拿到一个业务需求，怎么决定「该不该用 agent」「接缝画在哪」「工具怎么设计」「怎么接进既有业务系统」。
> 每条原则都标了一手出处；出处编号（`S1`…`S14`）对照
> [`research-agent-architecture-sources.md`](./research-agent-architecture-sources.md)，那里有完整 URL 与原文引用。
> 落地对照以本仓代码与 ADR 为准（仓库内一手资料优先于任何外部文档）。

---

## 0. 心法：agent 不是系统的形状，是系统里的一个零件

两条一手观察决定了后面所有判断：

- **「好 agent 大多是披着皮的确定性代码」**（S8，12-Factor）：*"most of the products out there billing themselves as 'AI Agents' are not all that agentic. A lot of them are mostly deterministic code, with LLM steps sprinkled in at just the right points."* 同一来源更直接的一句：*"Agents, at least the good ones, don't follow the ['here's your prompt, here's a bag of tools, loop until you hit the goal'] pattern. Rather, they are comprised of mostly just software."*
- **难点从来不是编排，而是每一步喂给模型的上下文**（S13，LangChain 官方博客）：*"The hard part of building reliable agentic systems is making sure the LLM has the appropriate context at each step."* 同一篇也承认那些通用能力 *"can be provided by a framework, or built from scratch"*。

**因此设计顺序是反的**：先画确定性系统的骨架（数据流、权限、状态、失败处理），再找「哪几步非 LLM 不可」，把 LLM 嵌进去。不要先搭一个 agent 循环，再把业务往里塞。

---

## 1. 第一问：这里到底需不需要 agent

| 判据 | 出处 | 原文要点 |
|---|---|---|
| 默认找最简方案 | S1 | *"we recommend finding the simplest solution possible, and only increasing complexity when needed. This might mean not building agentic systems at all."* |
| 用 LLM 控制流程才算 agent | S7 | *"Applications that integrate LLMs but don't use them to control workflow execution—think simple chatbots, single-turn LLMs, or sentiment classifiers—are not agents."* |
| OpenAI 的三条该建判据 | S7 | 复杂决策 / 规则难以维护 / 重度依赖非结构化数据；并收边：*"Otherwise, a deterministic solution may suffice."* |

**不要用的三种信号**（[推断]，由上述判据外推）：

1. **规则可枚举**（权限判定、状态机流转、格式校验）——写规则，别交给模型。
2. **结果必须 100% 可复现**（计费、成绩落库）——LLM 只做草稿，落库前过确定性校验。
3. **你已经能用一次调用解决**（S1：*"optimizing single LLM calls with retrieval and in-context examples is usually enough"*）。

**可执行动作**：为每个候选能力写一句「不用 LLM 的解法是什么」。写不出来说明你还没理解需求；写出来了发现它更好，就别做 agent。

---

## 2. 第二问：workflow 还是 agent —— 把「谁决定下一步」画出来

分界是官方的，不是约定俗成的（S1）：

- **Workflow**：*"systems where LLMs and tools are orchestrated through predefined code paths"*
- **Agent**：*"systems where LLMs dynamically direct their own processes and tool usage"*

两者的工程后果完全不同，必须先分清：

| | workflow（代码定路径） | agent（模型定路径） |
|---|---|---|
| 验证方式 | 单测断言 | eval + 统计指标 |
| 失败形态 | 可复现的 bug | 概率性退化 |
| 停止条件 | 代码天然有终点 | **必须显式设**（S1、S7 均要求 max iterations） |
| 成本 | 可预测 | 可能失控 |

Anthropic 给了五种 workflow 模式（S1，附原文「何时用」）：prompt chaining（用延迟换准确率）、**routing**（*"separation of concerns, and building more specialized prompts"*）、parallelization（sectioning / voting）、orchestrator-workers（子任务**不是预定义的**，由 orchestrator 决定）、evaluator-optimizer（有明确可改进反馈时）。

**路由的一个隐藏价值常被忽略**（S1）：*"Routing easy/common questions to smaller, cost-efficient models… and hard/unusual questions to more capable models"*——路由层天然是成本阀门，不只是意图分类器。

**复杂度必须有证据**（S1）：*"you should consider adding complexity *only* when it demonstrably improves outcomes."*

多 agent 的拆分裂由只有两条（S7）：**Complex logic**（分支过多、模板难扩展）与 **Tool overload**（工具**重叠**）；在此之先 *"maximize a single agent's capabilities first"*。规模上限参考 S8.10：*"3-10, maybe 20 steps max"*。

---

## 3. 第三问：接缝画在哪 —— 六个必答问题

> 开一条缝的成本 = 一个抽象 + 一个适配器 + 一组测试。**一个适配器 = 假想缝；两个适配器才是真缝。**
> 没有第二个实现的缝，要么删掉，要么承认它是「预留」并标注。

| # | 接缝 | 隔离什么变化 | 什么时候不值得开 |
|---|---|---|---|
| 1 | **模型调用** | 换厂商 / 换 SDK / 没装 SDK 也要能测 | 只可能用一个厂商且永不换 → 直接依赖也行，但要付出「单测必须打桩网络」 |
| 2 | **工具** | 业务能力如何被模型调用 | 见 §4，工具本身永远要有 seam（它是权限与副作用的唯一收口） |
| 3 | **上下文 / 状态** | 多轮、长任务、压缩 | 单轮问答 → 别建状态机 |
| 4 | **事件流（前端）** | 客户端形态（Web / Flutter / 终端） | 只有一种客户端且不需要中间态 → 可以只回文本 |
| 5 | **权限 / 人工介入** | 谁能做什么、何时停下来问人 | 只读场景可简化，但**写操作必须有** |
| 6 | **装配** | 能力如何被找到 | 见 §6，N 小且无外部插件 → 显式表更划算 |

关于第 3 条，最该照做的一条是 **12-Factor Factor 5（S8.5）**：把 execution state（当前步骤、重试次数）与 business state（已发生事件）**统一**，*"If possible, SIMPLIFY - unify these as much as possible."* 它列的收益里对业务系统最有价值的是 Serialization（*"The thread is trivially serializable/deserializable"*）、Recovery（加载 thread 即可续跑）、Human Interfaces（*"Trivial to convert a thread into a human-readable markdown or a rich Web app UI"*）。**如果你有「agent 运行时表」和「业务事件表」两套，就是在重复官方点名的复杂度。**

关于第 4 条，AG-UI（S9）给了存在理由：*"Agentic applications break the simple request/response model that dominated frontend-backend development in the pre-agentic era."* 并明确 *"An AG-UI client does not have to be a web application… a terminal, a mobile app, or a chat platform can each act as a client."* 事件全集（1.0，PascalCase）至少应覆盖：生命周期边界（`RunStarted` + `RunFinished`/`RunError` **是强制的**）、文本消息三段式、工具调用三段式、状态同步（`StateSnapshot`/`StateDelta`，RFC 6902）、以及一个等价于 `Custom` 的**扩展通道**——没有扩展通道，业务方只能往 JSON 里偷偷塞字段，协议最终失控。

> ⚠️ 本仓 `RESOURCES.md` 里「AG-UI 规范目前仍是 draft」的说法已过时：文档站标注的是 Documentation 1.0，只有提案页（如 Meta Events）标 DRAFT；且 1.0 用 PascalCase 事件名，全大写下划线（`RUN_STARTED`）是旧式写法。详见 research 文件「存疑」第 2 条。

---

## 4. 工具层：整个架构里最该花时间的地方

一手结论（S2）的基石一句：**"Tools are a new kind of software which reflects a contract between deterministic systems and non-deterministic agents."** 推论是 *"instead of writing tools and MCP servers the way we'd write functions and APIs for other developers or systems, we need to design them for agents."*

九条可执行的规则：

1. **不要 1:1 包 API**（S2）：*"A common error we've observed is tools that merely wrap existing software functionality or API endpoints."* 按高价值工作流重构，一个工具可以在内部合并多次调用。
2. **重叠即缺陷**（S2/S3）：*"Too many tools or overlapping tools can also distract agents."* 更硬的判据（S3）：*"If a human engineer can't definitively say which tool should be used in a given situation, an AI agent can't be expected to do better."* → 拿两个工具描述问三个人，答不出来就合并。
3. **返回有意义的上下文，不是底层标识符**（S2）：*"eschew low-level technical identifiers (for example: `uuid`, `256px_image_url`, `mime_type`)"*；把 UUID 换成自然语言/0-indexed ID *"significantly improves Claude's precision… by reducing hallucinations"*。
4. **每个可能返回大内容的工具都要有上限**（S2）：pagination / range / filtering / truncation *"with sensible default parameter values"*（Claude Code 默认截到 25,000 tokens）。
5. **错误文案要可被模型消费**（S2）：*"prompt-engineer your error responses to clearly communicate specific and actionable improvements, rather than opaque error codes or tracebacks."*
6. **工具描述本身要 prompt-engineering**（S2）：*"think of how you would describe your tool to a new hire on your team."* 参数名不许含糊（`user` → `user_id`）；S1 附录的 poka-yoke：*"Change the arguments so that it is harder to make mistakes."* Anthropic 自述在 SWE-bench 上 *"actually spent more time optimizing our tools than the overall prompt"*。
7. **命名空间要有 eval 支撑**（S2）：prefix/suffix 的效果 *"non-trivial… Effects vary by LLM"*，别凭惯例。
8. **工具调用 = 结构化输出**（S8.4）：*"The LLM decides what to do, but your code controls how it's done."* → 执行器天然可以挂权限门、限流、mock、审计；绝不能退化成 `globals()[name](**args)`。
9. **工具顺序要稳定**（S6，MCP）：*"Servers SHOULD return tools in a deterministic order… improves LLM prompt cache hit rates."* 顺序不稳定会悄悄打掉 prompt cache。

**风险分级**（S7）：给每个工具打 low/medium/high，依据 read-only vs write、可逆性、所需权限、财务/后果影响，并据此触发暂停检查或人工确认。

---

## 5. 接入业务系统的七条规则

1. **工具直接调业务 service，不绕 HTTP、不重新实现权限。** 工具是业务能力的适配器，不是第二套业务层。重复实现权限等于两处真相。
2. **权限裁剪下沉到工具侧，不放提示词。** 提示词是软约束，可被诱导绕过且不可断言；工具侧过滤是结构性的，可以写成单测。（本仓：`core.guard` + 工具侧 `project_for_role`。）
3. **执行状态与业务状态统一**（S8.5，见 §3）。会话/消息表就是 thread，别再建一套运行时状态表。
4. **事件流即产品契约**：每一个值得展示的中间态都要有帧（选中了哪个助手、正在查什么、查到了什么卡片）。缺帧的地方，前端只能转圈，用户就会以为卡死。
5. **prompt 是一等代码**（S8.2）：*"Don't outsource your prompt engineering to a framework."* 进仓库、可 diff、可 A/B、可测；黑盒 `Agent(role=…, goal=…)` 无法微调到具体 token。
6. **错误分三类归因，不许抹成一句话**：模型能力问题（不支持工具调用）/ 厂商拒绝（401、限流、网络）/ 业务错误（参数不合法）。把 401 说成「不支持工具调用」会让用户去换模型，而真问题是密钥。
7. **成本与延迟是架构属性，不是调优项**：路由层按难度分流模型（S1）、工具结果截断（S2）、轮次上限可配置而非写死常量（S1/S7）、每工具失败计数 ~3 次后升级给人（S8.9：*"if you do this TOO much, your agent will start to spin out"*）。

---

## 6. 装配：能力到底怎么被找到

这一条有明确的一手事实，且**推翻了常见印象**：

- **OpenAI Agents SDK（S10）**：`@tool` 只是把函数变成工具对象（*"The name of the tool will be the name of the Python function… The schema for the function inputs is automatically created from the function's arguments"*），**装配永远显式**：`Agent(tools=[fetch_weather, read_file])`。
- **CrewAI（S11，v1.15.22）**：官方推荐路径是 JSONC 配置或直接代码显式定义；`@CrewBase/@agent` 装饰器被明确降格为 *"Classic projects… This remains supported for teams that want Python decorators"*。
- **真正的动态发现在 MCP（S5/S6）**：capability negotiation + `tools/list`，面向**跨进程**；进程内的能力表应当是可审计的显式清单。

**结论**：「装饰器 = 自动注册」不成立。进程内的能力装配，显式表是主流做法；目录扫描/魔法发现只有在「能力由第三方以包的形式提供」时才回本。**判据很简单：把发现机制删掉，复杂度会在一个 N 行的显式表里重生——如果 N 只有几十行，这个机制就没在赚钱。**

---

## 7. 什么时候该认输，改用框架

Anthropic（S1）：*"start by using LLM APIs directly… If you do use a framework, ensure you understand the underlying code."* 以及 *"don't hesitate to reduce abstraction layers and build with basic components as you move to production."*

LangChain 官方（S13）列出的框架价值清单，就是自写的对账单：**短期记忆 / 长期记忆 / human-in-the-loop / human-on-the-loop（含 time travel）/ streaming / debugging & observability / fault tolerance / optimization**。

**判据**：这 8 项里任何一项变成刚需（尤其 durable execution、time travel、可视化 trace），自研成本会陡增，此时应当换框架或只换那一块；在此之前自写合理。LangGraph 官方自己也劝退新手（S12）：*"LangGraph is very low-level… If you are just getting started… we recommend you use LangChain's agents"*。

---

## 8. 自检清单（改任何 agent 代码前过一遍）

**该不该做**
- [ ] 我能写出「不用 LLM 的解法」吗？它是不是其实更好？
- [ ] 这条路径是 workflow 还是 agent？谁决定下一步？
- [ ] 如果是 agent：停止条件在哪？max_turns 可配置吗？

**接缝**
- [ ] 每条缝至少有两个实现（含测试替身）吗？没有就删或标注为预留。
- [ ] 执行状态与业务状态是同一份吗？
- [ ] 事件流有确定的开始/终止事件和扩展通道吗？

**工具**
- [ ] 两个工具描述摆在一起，人类能确定该用哪个吗？
- [ ] 工具返回里有裸 UUID / 内部 ID 吗？
- [ ] 可能返回大内容的工具有默认上限吗？
- [ ] 工具错误文案能指导模型下一步吗？
- [ ] 写操作工具有风险分级和人工确认吗？
- [ ] 工具顺序是确定的吗（prompt cache）？

**接入**
- [ ] 工具是否直接调业务 service，权限判定只有一处？
- [ ] 权限是结构过滤还是提示词请求？
- [ ] prompt 在仓库里、可 diff、可测吗？
- [ ] 三类错误（能力 / 厂商 / 业务）能否被区分？
- [ ] 新增能力时，装配是显式可审计的吗？

---

## 9. 用这套法回看 openedu

**做对的（别动）**
- 意图路由是 workflow，SubAgent 内的 tool loop 才是 agent——这条分界清晰，正是 S1 的 routing 模式。
- 权限裁剪在工具侧而非提示词（对应 §5.2）。
- 单 SSE 端点 + 类型化事件帧 + `extra` 扩展通道（对应 §3 第 4 条与 AG-UI 的 Custom）。
- provider 端口只有一个适配器落点，可换厂商、可用替身跑测试。
- 轮次上限、REASONING/TEXT 分流、三类失败硬失败不静默降级——都是官方明确要求的边界。

**欠债（按本套原则诊断）**
- `registry.py` 的目录发现：N=4、单团队、无第三方插件，删除测试显示它不赚钱（§6）。
- `ports.Retriever` 零适配器，且生产传入的对象签名与端口不一致——假缝（§3）。
- `llm_classify` 已移除（T01）：它从未被调用，路由现为「规则匹配 → 启发式兜底」两级；真需要弱意图兜底，应重写一个**真被调用**的扩展点（§3）。
- `runtime_singleton` 只为不重复扫描而存在，随装配方式一起消失。
- 缺少 per-tool 失败计数（S8.9）与工具风险分级（S7）。
- 缺少 compaction / 工具结果清理（S3 的"最轻量压缩"）。
- `grade_open` 绕过适配器直调引擎——守住了「唯一 import」的字面，没守住实质。

**练习（先自己答，再对）**

1. 家长说「帮我把小明的错题导出成 PDF」——这是 workflow 还是 agent？理由？
2. 你在 `query` 下加了 `list_exam_scores`，又发现 `get_progress` 也会返回分数。按 §4 第 2 条，你该怎么做？
3. 一个工具返回 `[{"student_id": "3f2a…", "score": 87}]`，按 §4 第 3 条该怎么改？副作用是什么？
4. 什么信号出现时，你应该停掉自研内核改用框架？（答出 §7 的 8 项清单里任意两项）
5. 你们的能力表有 6 个、由一个团队维护、无第三方插件。按 §6，目录发现该保留还是换成显式表？判据是什么？

<details>
<summary>参考思路</summary>

1. workflow：路径可预定义（定位孩子 → 查错题 → 渲染 → 导出），没有需要模型动态决策的分支。做成工具 + 一次调用即可，不需要 agent 循环。
2. 合并。判据是「人类工程师能不能确定该用哪个」——不能，就该合并成一个工具，或把 `get_progress` 的分数返回去掉，让职责互斥。
3. 返回姓名/年级等自然语言可判定字段，把 ID 留在内部（必要时用 0-indexed 短 ID 供后续调用）。副作用：要多一次映射，但显著降低幻觉。
4. durable execution（服务重启后续跑）、time travel / 可视化 trace、HITL 审批流变成核心功能、长期记忆（跨会话用户画像）——任两项成刚需就该评估换框架。
5. 换成显式表。判据是删除测试：删掉发现机制后，复杂度只在一个 ~30 行的 `CAPABILITIES` 表里重生，说明它没在赚钱；第三方以包形式提供能力时才需要真发现（那时走 MCP）。
</details>

---

## 下一步

- 通读 [`research-agent-architecture-sources.md`](./research-agent-architecture-sources.md) 的 (C) 工具设计 与 (D) 上下文 两节，那是投入产出比最高的部分。
- 拿 §8 的自检清单跑一遍本仓某个 SubAgent，把「否」的项写成 issue。
- 想动手时：§6 的装配改造需要**先写 ADR 修订 ADR-0033**，不能静默改。
