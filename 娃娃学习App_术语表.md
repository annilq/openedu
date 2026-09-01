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

## 外部框架（已明确不作为运行时）
- **Pi（pi.dev）**：终端编码代理（coding agent），用作开发期编码助手。
- **Eve（eve.dev）**：TypeScript durable agent 框架，因与 Python 后端割裂，不作为运行时。
- **LangChain（已退役，08b）**：原 v1 前的 Python AI 编排运行时（含 `LangChainProvider` / `MockProvider` 双栈）；08b 统一为 Genkit 单栈后整体退役，**不再出现在运行时依赖中**。
