# 术语表 · 娃娃学习应用

> 项目统一词汇，供产品、设计、研发对齐使用。

## 角色与用户
- **娃娃**：应用的终端学习者，本项目的两个孩子（二年级、四年级），各持独立账号。
- **家长 / 管理员**：应用的"班主任"角色，负责布置任务、查看报告、设定管控策略。
- **账号隔离**：不同娃娃的进度、题目、作答记录互不可见、互不干扰。

## 能力与场景
- **刷题练习（A）**：按学科/知识点生成练习题，娃娃作答、自动批改、给解析。
- **每日任务打卡（C）**：家长布置每日学习任务，娃娃完成并打卡。
- **错题本 / 遗忘曲线复习（D）**：归集错题，按间隔重复（spaced repetition）提醒复习。
- **AI 伴学答疑（B）**：娃娃自由提问，AI 讲解；三期能力，需内容安全防护。

## 领域服务（自封接口，业务只依赖此层）
- **QuestionGenerator（出题引擎）**：依据学科、年级、知识点、题型生成题目。
- **Grader（批改引擎）**：对作答自动判分并生成解析。
- **KnowledgeRetriever（知识库检索）**：从教材知识库中检索匹配内容（后期 RAG）。
- **IntentRouter（意图路由）**：识别娃娃问题意图，路由到对应知识点/能力（后期）。

## 技术与架构
- **Provider 抽象**：业务领域层 `LLMProvider` 抽象（`GenkitProvider` 实现），统一单栈经 `app/ai` 的 Genkit flow 调用各大模型厂商（genkit-openai / genkit-ollama）；厂商切换即改 `BUILTIN_MODELS` / `ModelConfig`（或 `LLM_PROVIDER`），业务零改动（迁移 08b 纯单栈）。
- **领域接口 / 框架 adapter**：本项目在 Genkit 之上自封的业务语义接口与适配层（`app/ai` 为唯一 `import genkit` 边界，ADR-003 隔离延续），使业务代码不绑定具体 agent 框架。
- **RAG（检索增强生成）**：先检索教材知识库、再将内容喂给 LLM 生成答案/题目。
- **Genkit**：Python AI 编排框架，本项目的运行时 agent 引擎（08b 纯单栈后统一接管流式与非流式；非流式真实调用也走 `GenkitProvider`）。
- **Flutter**：Google 跨平台 UI 框架，本项目前端（平板优先原生 App）。
- **PostgreSQL**：关系型数据库，本项目持久化存储。
- **Docker**：容器化运行环境，本地起步、预留云迁移。

## AI 可观测性（conversation/message 调试库）
- **Conversation（AI 运行）**：一次 Agent 运行的容器；聚合所有 message，携带运行类型 `kind`、归属 `parent_id`、触发者 `child_id`、所用模型、状态 `status`（ADR-0022）。
- **Message（运行步骤）**：Conversation 内带 `role` 与 `step` 的一步记录；`content`(TEXT) 存人类可读文本，`payload`(JSON) 存结构化原始数据（题卡 dict / 模型原始响应 / 检索块 / 工具参数）。
- **role（消息角色）**：`system`(系统提示) / `user`(用户或前端输入) / `assistant`(模型输出) / `tool`(工具调用)。
- **step（运行阶段）**：`input`(请求) / `retrieval`(检索) / `reasoning`(推理) / `generation`(生成中) / `tool_call`(工具调用) / `output`(最终输出) / `error`(异常)。
- **Agent 运行调试库**：`conversation`+`message` 组成、与 `TutorLog`(答疑合规) 职责分离的 AI 可观测存储，用于回放与定位 bad case（ADR-0022）。

## 产品机制
- **Streak（连续打卡）**：连续完成每日任务的天数计数，轻量激励。
- **徽章 / 积分**：学科成就与累计奖励，纯前端状态。
- **每日使用时长上限**：家长设定的娃娃单日可用时长。
- **双层防护**：①prompt 约束 ②输出后校验，保障娃娃面对 AI 的内容安全。
- **教材对齐**：练习内容匹配学校教材版本与年级进度。

## 年级与学年
- **年级 / Grade**：娃娃当前就读年级，取值 1~9（覆盖小学至初中 K9）。是出题难度/进度的核心锚定维度（`QuestionGenerator` 按年级生成适龄题）。**单一事实源 = 入学年份（`enrollment_year`）+ 可选例外覆盖（`grade_override`）**；有效年级 `effective_grade = clamp(grade_override ?? (当前学年 - 入学年份 + 1), 1, 9)`。无入学年份时回落手填 `grade`（旧行为）。详见 ADR-0005。
- **学年 / School Year**：以 **9 月 1 日** 为界的学业年度；标识取起始秋季公历年份（如 2025-2026 学年记为 `2025`）。年级在每年 9 月新学年升级，**不在娃娃生日**。计算：`当前学年 = 今天.year if 今天.month >= 9 else 今天.year - 1`。
- **入学年份 / Enrollment Year**：娃娃开始**一年级**的秋季公历年份，年级演进锚点（如 2023 年秋入学 → `2023`）。选它而非出生日期作锚点，避免"标准入学年龄 6 岁"假设与同年不同月娃娃的年级错位。

## 流式与多模型（ADR-0015）
- **SSE（Server-Sent Events）**：Genkit `serve_flow` 原生流式传输协议（后端 `genkit-fastapi` 经 `text/event-stream` 推送 `data: {"message": <chunk>}` 帧 + 末帧 `data: {"result": <output>}`）；前端经 `package:genkit/client.dart` 的 `defineRemoteAction(...).stream()` 解析原生块（自定义 SSE 信封已于 08b 退役）。
- **GenUI / 生成式 UI（Generative UI）**：AI 在输出文本的同时生成可渲染的 UI 组件（如 CopilotKit 模式）。本项目的"轻量"实现为 SSE 推文本块 + 结构化事件、前端边收边渲染，**不采用** `genui` 的 CatalogItem/工具调用式真·GenUI（见 ADR-0015）。
- **轻量流式渲染**：SSE 推 `token` 文本增量与结构化事件（`question` 等），前端增量渲染（答疑打字机、出题逐张题卡）；相对真·GenUI 更轻、更快落地。
- **模型注册表（`GET /models`）**：后端暴露的可用模型清单，含内置模型（settings/env 声明）与当前家长自定义模型；仅家长可见。
- **ModelConfig（模型配置）**：家长自定义模型的持久化记录（`label / provider / base_url / model_name / api_key`），按 `parent_id` 存库，仿 `TutorQuota`。
- **Ollama**：本地开源 LLM 运行时，提供 OpenAI 兼容 API；本项目通过 `OLLAMA_BASE_URL`（默认 `http://localhost:11434`）由后端代理调用，实现零云成本/零外网延迟。
- **流式事件信封（⚠️ 已退役，08b）**：原为自研 SSE 事件契约，类型含 `token` / `question` / `safety_refusal` / `done` / `error`（ADR-0015 旧描述）；**08b 已删除**，前端改 `package:genkit/client.dart` 走原生 Genkit 流式协议，见 `Genkit flow` 词条。
- **Genkit（Python 版）**：`genkit` + `genkit-fastapi` 可在 FastAPI 进程内运行 flow，挂载 `serve_flow` 路由，`Accept: text/event-stream` 即走原生 SSE，支持 `chunk_type` 字段级结构化流式（题卡逐字段浮现）；**与本项目 Python/FastAPI 栈兼容**（无 Node 依赖）。**v1 已采纳为流式编排引擎**（ADR-0015 决策 3），**08b 纯单栈后统一接管流式与非流式**：`genkit` 仅 `import` 于 `app/ai/`，`LangChainProvider` 已于 08b 退役，框架 import 隔离延续 ADR-003。
  - **Genkit flow**：`@ai.flow` 装饰的命名 AI 工作单元（如 `tutorAsk` / `tasksGenerate` / `generateQuestion`），输入/输出为 Pydantic schema；是「安全可观测单元」（输入安全在薄路由前置、输出安全在 flow 内整体校验），DevTools 可追踪、版本化。
  - **`defineRemoteAction`**：`package:genkit/client.dart` 导出的 Dart 函数，声明前端对后端 Genkit action 的远程调用（`url` + `fromResponse` / `fromStreamChunk` 映射），`.stream()` 消费原生块、`.call()` 取一次性结果。
  - **`serve_flow`**：`genkit-fastapi` 暴露的端点构造器，把 flow 挂为 `POST /<action>` 路由，兼容 Genkit 原生线协议（请求体 `{"data": {...}}`、流式 `text/event-stream`）。
- **模型选择器（model picker）**：家长端选择/管理模型的 UI；娃娃继承家长默认模型，不在娃娃端暴露下拉。

## 出题与题库同步（ADR-0016）
- **出题（Unified Generate）**：合并后的家长端单一动作，先按规格流式产出题卡预览，再由家长手动选择去向（存为任务 / 加入题库）。取代原「生成任务」「预览出题」两个并列入口。
- **题卡预览（Question Preview）**：流式逐张浮现的 `QuestionPreview` 卡片，仅展示、未落库；生成后家长可勾选决定去向。
- **题库同步（Bank Sync）**：把已生成题卡写入题库（`Question`）的动作，粒度**逐题多选**（ADR-0016）——只把勾选的题入题库。
- **关联引用（Linked Reference）**：任务题 `TaskQuestion.question_id` 指向题库 `Question`，题库为唯一真源；与"独立副本"相对（ADR-0016）。
- **`POST /tasks/from-generated`**：流式题卡 → draft 任务的落库端点；被「存为任务」动作复用（ADR-0016 决策 6）。
- **`POST /questions/bank/bulk`**：批量把勾选流式题卡建为题库 `Question` 的端点；需过 `check_output` 安全闸门（ADR-0016，待实现）。

## 出题推理通道（ADR-0017）
- **出题推理过程（Reasoning）**：模型「怎么设计这道题」的文字说明（情境选取、干扰项思路、难度控制）。合并自原 think+typing 概念——`thinking` 是内容、`typing` 是前端打字机动画（呈现方式，非数据类型）。
- **REASONING chunk**：SSE 中承载出题推理增量的 chunk 类型（`type:"REASONING"`，含 `q_index` 与 `delta`）；与 `CARD`、`STEP` 并列，靠 `type` 字段多态分发（对齐 AG-UI `BaseEvent`）。
- **STEP chunk**：每题进度锚点（`type:"STEP"`，`label` 如"正在为《数学》三年级「分数」出选择题"），对应 AG-UI `STEP_STARTED`。
- **CARD chunk**：成品题卡 chunk（`type:"CARD"`，`question` 为 `QuestionOut`），与 ADR-0015/0016 题卡数据一致。
- **信封（Envelope）**：SSE chunk 的统一封装——JSON 对象含 `type` 判别字段；取代原「裸 QuestionOut」chunk，传输帧（`message`/`result`/`error`）不变。
- **supports_reasoning**：`EngineResolution` 新增布尔位，标记所选模型是否具备原生思维链（DeepSeek-R1 / o-series 等）；为真时后端实时读取思维链 token 发 `REASONING` 增量，否则走单次调用 + 客户端打字机打底。
- **打字机揭示（Typewriter Reveal）**：前端把 `REASONING.delta` 逐字动画展示的效果；打底路径下整段推理到客户端后再动画揭示（零额外成本），reasoning 模型下与真·token 流同步。
- **推理折叠（Reasoning Collapse）**：某题 `CARD` 到达后，该题内联推理区**默认隐藏**，推理文本随 `QuestionOut.reasoning` 落于卡片；卡片右上角常驻 **info icon**，点按以 popover / bottom-sheet 展开「AI 出题思路」面板，便于多题紧凑矩阵排布、按需查看单题推理（纯前端交互，不新增 SSE 字段）。

## 外部框架（已明确不作为运行时）
- **Pi（pi.dev）**：终端编码代理（coding agent），用作开发期编码助手。
- **Eve（eve.dev）**：TypeScript durable agent 框架，因与 Python 后端割裂，不作为运行时。
- **LangChain（已退役，08b）**：原 v1 前的 Python AI 编排运行时（含 `LangChainProvider` / `MockProvider` 双栈）；08b 统一为 Genkit 单栈后整体退役，**不再出现在运行时依赖中**。

## Agent Runtime（悬浮 AI 助手 / 多 Agent 编排，ADR-0024~0026）
- **AgentRuntime（代理运行时）**：后端新增编排层（`app/ai/runtime/`），负责发现并加载文件夹化 subagent、按意图路由、运行工具循环、产出 AG-UI 事件帧。是悬浮助手的服务端大脑（ADR-0024）。
- **SubAgent（文件夹化业务代理）**：一个业务能力单元，以统一目录 `app/ai/subagents/<business>/` 组织（`agent.py` + `manifest.yaml` + `tools/` + `skills/`），由 AgentRuntime 统一加载；business 键（如 question/tutor）是其注册索引（ADR-0024）。
- **manifest（subagent 清单）**：`manifest.yaml`，声明 business 键、name、description、`triggers`（意图关键词/示例）、`roles`（可见角色）、依赖的 tools/skills。runtime 据此发现与路由（ADR-0024/0026）。
- **tool（可执行工具）**：subagent 运行时可调用的结构化 IO 函数（如 `generate_question`/`list_tasks`/`search_knowledge`）；runtime 工具循环调用（ADR-0024）。
- **skill（技能资产）**：提示词/方法论资产（注入 system prompt，不可执行），如「出题 SOP」（ADR-0024）。
- **shared_tool（共享工具）**：跨 subagent 复用的 tool，抽公共文件 `app/ai/tools/`，各 manifest 声明依赖引用（ADR-0024）。
- **IntentRouter（意图路由）**：混合路由——manifest `triggers` 先规则匹配，未命中走轻量 LLM 分类输出 business key；是「识别用户意图并路由」的实装（ADR-0024）。
- **AG-UI 统一事件信封**：助手与前端间的流式协议，`{"type": <EventType>}` 判别字段；事件含 `USER_MESSAGE` / `ASSISTANT_MESSAGE` / `THINKING` / `TOOL_CALL` / `TOOL_RESULT` / `STEP` / `CARD` / `ERROR` / `DONE`（ADR-0025；`STEP`/`CARD`/`THINKING` 复用 ADR-0017）。
- **角色感知派发（role-aware dispatch）**：IntentRouter 按 `role` 过滤可见 subagent，孩子端仅暴露伴学答疑（ADR-0026，强化 ADR-008）。
- **AssistantSession（助手会话）**：持久化聊天 + 调试会话（id/role/parent_id/child_id/model/status）；其 `AssistantEvent` 既是对话步骤也是调试轨迹，废除原 `debug_log`（ADR-0026，supersede ADR-0022）。
- **AssistantEvent（助手会话步骤）**：session 内带 role/type/step 的一步（content + payload + 安全/延迟/usage 标记），沿用 ADR-0022 口径（ADR-0026）。
- **悬浮 AI 助手（Floating Assistant）**：前端全局悬浮按钮 + 对话框入口，双端通用，调 `POST /api/v1/assistant/chat` 经 AgentRuntime 完成「意图识别 → 路由 → subagent 执行 → 事件流」全流程（前端 ADR-0006）。

## Agent 框架（agent_core，ADR-0031）
> 本 ADR-0031 把 ADR-0024~0026 的 AgentRuntime 从「教育专属」升级为「通用框架」；下列术语取代/泛化原「Agent Runtime」节中的教育特定描述。

- **agent_core**：从 `app/ai` 抽出的**独立可安装 Python 包**（内部 PyPI 发布），提供业务无关的 agent 抽象层——协议、subagent 注册、subagent 路由、真实 tool loop、统一事件流；各业务工程 `pip install agent_core` 后实现自己的 subagent 接入（ADR-0031）。
- **seam（抽象接缝）**：`agent_core` 仅定义、不实现的抽象接口，由业务工程注入具体实现；含 `LLMProvider`（消息级）、`Retriever`、`Safety`、`Tool`。业务代码只依赖 seam，不依赖具体引擎。
- **LLMProvider（消息级 seam）**：`stream(system, prompt, schema, history) -> AsyncIterator[TextDelta | StructuredDone]`；不再认识学科/年级等业务语义（取代原 `generate_question_stream(...)`）。
- **ToolSpec（工具声明）**：`(name, description, schema, handler)`，subagent 声明后由 `AgentRuntime` 在 tool loop 中执行；`handler` 是普通可执行函数，区别于 ADR-0024 时代「仅声明、无调度器」的 `manifest.tools`。
- **tool loop（工具循环）**：模型选型 → runtime 执行 `ToolSpec.handler` → 回灌 `tool_result` → 循环直到 `done`；subagent 通过是否声明 `tools` 决定走 loop（opt-in），一次性生成流可不声明。
- **BaseSubAgent（通用基类）**：`handle(intent, ctx)` + `run(message, ctx)` 统一契约；`SubAgentContext` 去掉教育专属字段（subject/grade/knowledge_point 等），仅保留 role/history/skills/extra 等通用字段。
- **manifest（subagent 清单，沿用 ADR-0024）**：`manifest.py` 的 `MANIFEST` 字典声明 business 键、name、roles、triggers、hints、priority、tools、skills；runtime 据其发现与路由。
- **registry（注册表）**：文件夹发现 `discover_subagent_manifests()`，扫到 `manifest.py` 同时用 `inspect` 取 `BaseSubAgent` 子类写入清单（发现即注册，ADR-0030）。
- **router（路由）**：规则（`triggers`）+ 启发式（`hints`）默认实现，按 `priority` 降序匹配、priority 最低者兜底；暴露可插拔 `classify` 钩子（弱意图领域可接 LLM，约 5 行）。
- **统一事件流 / AssistantEvent（信封，沿用 ADR-0025）**：`agent_core` 拥有的 AG-UI 式信封（RUN_STARTED / USER_MESSAGE / THINKING / ASSISTANT_MESSAGE / TOOL_CALL / TOOL_RESULT / STEP / DATA / ERROR / DONE / RUN_FINISHED）；`DATA.type`、`blocked` 等教育字段改为 `extra` 扩展。
