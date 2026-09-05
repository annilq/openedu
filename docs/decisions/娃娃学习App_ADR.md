# 架构决策记录（ADR）· 娃娃学习应用

> 记录关键架构决策：背景、决策、备选、后果。状态统一为「已采纳」。

---

## ADR-001 前端技术选型：Flutter 原生 App
- **背景**：目标用户为低龄娃娃，主力设备是平板；需跨 iOS/Android。
- **决策**：采用 Flutter 开发原生 App，平板优先。
- **备选**：PWA 网页（跨设备、免上架）、微信小程序（国内管控友好但 AI 受限）。
- **后果**：一套代码出双端；UI 表现力足；需自行上架/分发；AI 调用必须经后端（前端不藏 key）。

## ADR-002 后端语言：Python
- **背景**：AI 编排需成熟生态；LangChain 主力为 Python。
- **决策**：后端用 Python。
- **备选**：TypeScript/Node（与 Eve/Pi 同生态）、Python+TS 混合。
- **后果**：与 LangChain 深度契合；Pi/Eve（TS）不作为运行时，留作开发助手。

## ADR-003 AI 编排框架：LangChain + 自封领域接口
- **背景**：希望"适配大部分大模型厂商的 provider"，且未来可换框架。
- **决策**：运行时用 LangChain 做 agent 编排；**不在 LangChain 的 LLM provider 抽象之上重复封装**，改为在"agent 框架层"之上自封一层**领域服务接口**（QuestionGenerator / Grader / KnowledgeRetriever / IntentRouter）+ 框架 adapter。
- **备选**：直接用 Eve（TS，Vercel AI SDK）、Pi（TS coding agent）、自写 BaseProvider。
- **后果**：厂商适配交给框架（已支持 100+ 厂商），框架切换由 adapter 隔离；业务代码不绑定具体框架。避免重复造 provider 轮子，同时实现可插拔。

## ADR-004 LLM 模型：暂不定，provider 抽象可插拔
- **背景**：国内平板直连、儿童内容合规、长期成本均需评估。
- **决策**：模型先不绑定；通过 LangChain provider 抽象接入，国产模型走 OpenAI 兼容端点即可。
- **备选**：固定腾讯混元 / 智谱 GLM（国内稳定便宜合规）。
- **后果**：一期可用免费/低成本模型验证；后期按质量与成本选型，无迁移成本。

## ADR-005 数据库：PostgreSQL
- **背景**：多账号、任务、题目、作答记录需持久化与查询。
- **决策**：PostgreSQL。
- **备选**：SQLite（起步更轻）、BaaS（Supabase 等）。
- **后果**：关系模型清晰、易扩展；本地 Docker 起步，架构预留云；SQLite 可作一期最简替代。

## ADR-006 部署：本地 Docker 起步，架构按云设计
- **背景**：家庭自用，不想立即承担云成本与运维。
- **决策**：本地 Docker 容器跑 Python 后端 + PostgreSQL；架构（无状态服务 + 外部数据库）按云部署设计，未来可搬轻量云。
- **备选**：直接上云、纯本地无容器。
- **后果**：零月费起步；外网访问需后续内网穿透或上云；容器化保证可搬运。

## ADR-007 账号模型：家长管理员 + 娃娃独立账号
- **背景**：需家长布置任务、查看进度，且两个娃娃进度隔离。
- **决策**：家长管理员账号 + 每个娃娃独立账号（二年级、四年级各一）；进度与数据按娃娃隔离。
- **备选**：无账号单机、仅娃娃端。
- **后果**：支持"班主任"式管控与跨设备；需实现多角色鉴权。

## ADR-008 内容安全：双层防护 + 家长可见
- **背景**：三期娃娃可自由向 AI 提问，须防不当内容与越狱。
- **决策**：①系统层 prompt 约束（仅适合 X 岁、纯学习）；②输出后校验（敏感词/越狱检测，异常拦截转家长）；③家长可查全部 AI 交互日志；④家长设每日时长上限与内容范围。
- **备选**：仅 prompt 约束、家长全审核。
- **后果**：一期风险低但框架先搭；三期直接启用；保护娃娃且家长可控。

## ADR-009 内容来源：AI 生成 + 对齐教材（前期检索 / 后期 RAG）
- **背景**：需持续产出对齐学校进度的练习。
- **决策**：一期 AI 出题；前期 agent 联网检索教材知识点，后期建教材知识库（向量库）+ 意图识别路由（RAG）。
- **备选**：纯现成题库人工录入、纯 AI 无教材对齐。
- **后果**：贴合课标且灵活；依赖检索/知识库质量；需内容校验流程。

## ADR-010 激励：轻量激励
- **背景**：低龄学习需维持日常使用习惯。
- **决策**：每日打卡 streak、学科积分、知识徽章、家长表扬。纯前端状态，不依赖 AI。
- **备选**：强游戏化（闯关/排行榜）、无激励。
- **后果**：足够形成习惯且不喧宾夺主；排行榜等留待初中阶段。

## ADR-011 Pi / Eve 不作为运行时引擎
- **背景**：用户曾提及 Pi、Eve 等 agent 框架。
- **决策**：Pi（终端 coding agent）与 Eve（TS agent 框架）与 Python 后端割裂，不作为应用运行时；Pi 可作开发期编码助手。运行时统一 LangChain。
- **后果**：技术栈统一在一个 Python 服务内；减少异构运维。

## ADR-012 教材版权合规约束
- **背景**：人教版等教材受版权保护。
- **决策**：开发/自用阶段可使用；凡做成对外分发产品，**上线前必须取得教材版权授权或改用公版/自编内容**。
- **备选**：忽略版权（不可行）、仅用公版内容。
- **后果**：自用无碍；对外产品上线前的硬门槛，需提前规划。

## ADR-013 后端工程基线：基于 fastapi/full-stack-fastapi-template 二次开发
- **背景**：早期方案手写 FastAPI（SQLAlchemy async + bcrypt 直连 + 独立 pydantic schemas）。用户要求后端架构基于官方全栈模板做二次开发，以获得成熟的分层、认证、测试与部署基线。
- **决策**：后端以 `fastapi/full-stack-fastapi-template` 为基线，裁剪后保留其核心约定并移植我们的业务：
  - **ORM 改用 SQLModel**（原手写方案为 SQLAlchemy async + 独立 Pydantic schemas）。这是与早期 spec「async」表述的**有意偏离**——为忠实「基于模板二次开发」，跟随模板走**同步** SQLModel（`create_engine` + `Session`）。
  - **认证改用 `pwdlib[argon2,bcrypt]` + `pyjwt`**（模板默认），取代早期手写的「bcrypt 直连」。这正好规避了 `passlib` 与新版 `bcrypt` 的冲突（早期踩过的坑）。
  - **丢弃模板的 React 前端**（我们前端是独立 Flutter App）、**丢弃邮箱体系**（无 SMTP/EMAIL/FIRST_SUPERUSER）、**丢弃 Traefik**（家用不需公网 HTTPS）。
  - **保留并采用**：`core/`（config/db/security/deps）、`api/`（deps/main/routes）、`crud.py`、`models.py`、`tests/conftest` 的 db 覆盖模式、pytest、`pyproject`（ruff/hatchling）、Dockerfile、docker-compose。
  - **API 统一前缀 `/api/v1`**；路由：`auth`(register/login, JSON) / `children` / `tasks`(generate/today/answer/checkin/progress) / `health`。
  - **Python 锁定 3.14**（跟随模板；2026 年中模板已升 3.14，LangChain 等生态应已跟上）。
- **备选**：仍用手写 async SQLAlchemy 方案；或仅「文档对齐」而不实际脚手架。
- **后果**：获得生产级认证/测试/部署基线，二次开发收益大；代价是 ORM 由 async 变 sync（本期功能无影响，未来若有高并发实时需求再评估 async）；领域层（`domain/`）仍以「LLMProvider 抽象 + 工厂」保持可插拔，不破坏 ADR-003。

## ADR-0014 设计重定向：双模式 + 学科色 + 响应式断点 + 适度趣味
- **背景**：现有设计系统（Linear/Notion 风、中性+靛蓝、15sp 密排、1px 描边无阴影）方向清晰，但有四类问题经 `/grill-with-docs` 访谈确认：
  1. **受众矛盾**：ADR-0003 将家长与娃娃合并为「单一密排专业系统、娃娃共用 15sp」，但产品方案明确娃娃为低龄（1–3 年级）、「学习动力难维持」——单一密排系统与之冲突。
  2. **规范未落地**：`.impeccable.md` 明令「禁止手动 `withValues(alpha:)` 透明度变体」，全库仍搜到 13+ 处违反；部分卡片（`parent_overview_view._StatCard`）用裸 `Container` 缺 1px 描边，破坏「描边分层」原则。
  3. **无响应式断点**：侧栏固定 240/64，无 `BottomNavigationBar`/`NavigationRail`，无断点逻辑；手机/竖屏窄屏不可用。
  4. **色彩偏冷**：中性+单一靛蓝对家长端成立，但娃娃端缺激励；现有「复习=紫灰 / AI=琥珀」为临时映射，无系统。
- **决策**：
  1. **双模式（Dual-Mode）**：家长工作台（Parent Mode）沿用密排专业系统（15sp 基线、中性+靛蓝、1px 描边、克制动效）；娃娃学习台（Child Mode）独立密度与语气——更大字号基线（~17sp）、更圆角、学科色凸显、暖容器、适度趣味动效。两者共用同一套 surface/spacing/radius 令牌，仅在「字号阶梯 + 语气 + 学科色权重」上分化。
  2. **学科色扩展（Subject Accents）**：在中性+靛蓝基底上新增受控的多色强调——数学=蓝、语文=玫瑰、英语=翠绿，预留扩展槽。中饱和、**仅用于学科标识/进度条/图标容器，不用于大面积背景**；家长端在数据可视化中低调使用，娃娃端凸显。
  3. **响应式断点（Breakpoints）**：`compact < 700` / `medium 700–1023` / `expanded ≥ 1024`。compact 收起侧栏为底部导航（娃娃）/抽屉（家长）；medium 与 expanded 侧栏均可收起（240 ↔ 64，收起状态经 [StorageService] 持久化，三档共用同一收起偏好）。
  4. **适度趣味动效（Moderate Delight）**：保留 120/200/300ms 三级；新增 `celebrate` 级（~450ms）用于徽章解锁 / 连击 / 打卡成功，仅 Child Mode 启用；做题反馈清晰不喧宾。
- **备选**：维持 ADR-0003 单一专业系统 / 全设备响应式（手机优先）/ 丰富游戏化（多邻国式）。
- **后果**：正式承认代码里已存在的双轨（child_home 横幅本就更活泼）；需扩充令牌（Child Mode 字号阶梯、学科色、断点、celebrate 动效）并新增双模式切换与响应式壳；需一轮「规范一致性审计」修掉既有 `withValues(alpha:)` 与缺描边违反。**本 ADR 修订 ADR-0003 中『娃娃共用单一密排系统』的判定，改为双模式。**

## ADR-0015 多模型接入（Ollama / 自定义）+ 流式响应 + 轻量 GenUI

> 来源：`/grill-with-docs` 访谈收敛（模型优化 / 本地 Ollama / 流式 UI / GenUI / 前端模型选择器）。配套实现票据见 `../../wayfinder/tickets/08-多模型流式genui.md`。

### 背景
一期~三期已用 `MockProvider`（默认）+ `LangChainProvider`（真实模型）跑通全闭环，但存在三点诉求：①家用以**本地 Ollama** 跑模型可零云成本、零外网延迟、数据不出户；②答疑/出题希望**流式输出**改善体感（打字机 / 逐张题卡）；③前端要能**选择后端支持的模型**、出题时**自选或自定义模型**。用户要求参考 CopilotKit 式 GenUI，但前端是 Flutter，而 CopilotKit 无 Flutter SDK；候选官方方案为 Flutter `genui`（alpha，A2UI 原生走 WebSocket）与 Genkit（Flutter 端 `genkit/client.dart` 需接 Genkit flow 后端，而 **Genkit 的 Python 版 `genkit` + `genkit-fastapi` 可在 FastAPI 进程内直接挂 flow、`Accept: text/event-stream` 即 SSE、并支持 `chunk_type` 字段级结构化流式**，故与本项目 Python/FastAPI 栈**兼容**；已采纳为 v1 流式编排引擎（见决策 3 与备选）。

### 决策（六条，均经访谈锁定）
1. **后端统一代理（守安全）**：Flutter 一律只连 `/api/v1` 的 SSE 端点；Ollama 与自定义模型由后端调用。服务端始终注入 `_SYSTEM` 年龄锁并对娃娃可输入字段跑 `check_input`、对输出跑 `check_output`，**安全层永不绕过**（忠诚 ADR-008）。禁止前端直连任何模型。
2. **端到端 Genkit 协议（前后端统一，单栈）**：后端把 AI 能力暴露为原生 Genkit flow（经 `genkit-fastapi` 的 `serve_flow`，返回 Genkit 原生 typed structured streaming SSE）；前端改用官方 `package:genkit/client.dart` 的 `defineRemoteAction` 直连这些 flow，**不再维护自定义 SSE 信封**。单一技术栈（后端 flow + 前端 genkit client）避免双协议/双客户端/双测试的长期维护成本（见迁移文档 `../../wayfinder/migration-08b-genkit-fullstack.md`）。GenUI catalog 仍作为按需扩展点保留，本决策仅确定「协议统一」，不强制 catalog 式生成式 UI。
3. **改用 Genkit Python 编排流式 flow（替代原「LangChainProvider 扩展」方案）**：流式 AI 输出（答疑逐字 + 出题逐张题卡）由 Genkit flow 编排，新增 `app/ai/`（**唯一允许 `import genkit` 的边界**，类比原 `LangChainProvider` 作为 langchain 适配层）承载：`Genkit` 实例、`serve_flow`/SSE 挂载、模型解析（Ollama / OpenAI-compat / 内置，按 `ModelConfig` + settings 把 `provider/model_name` 解析为 `ollama/{m}` / `openai/{m}`）与工具调用（T11 知识库检索作接地工具）。**ADR-003 延续**：业务/domain 代码仍只依赖 `LLMProvider` ABC 与非流式路径（`MockProvider` 供测试、`LangChainProvider` 供非流式真实调用），`genkit` 不被业务代码直接 import；流式端点由 API 层调用 `app/ai` 的 flow。
4. **模型注册 = 配置驱动 + 家长自定义**：内置模型由 settings/env 声明并暴露 `GET /api/v1/models`（parent 可见）；家长自定义模型落 `ModelConfig` 表（仿 `TutorQuota`，按 `parent_id` 持久化：`label / provider('ollama'|'openai_compat') / base_url / model_name / api_key(加密)`）。**模型选择器仅家长可用**；娃娃继承家长默认模型，娃娃端不暴露下拉（避免娃娃自选未授权/不安全模型）。请求参数 `model`（id 或内置 id）可选，缺省走家长默认或全局 `DEFAULT_MODEL`。
5. **流式安全 = 缓冲 + 整体校验后放行**：`/tutor/ask/stream` 先 `check_input` 拦越狱（命中即发 `safety_refusal` 不再调模型）；通过后后端**缓冲全量 token、跑整体 `check_output`**，通过才向娃娃放量，违规则整段替换为 `SAFE_REFUSAL`。儿童端绝不闪现违规片段。v1 接受"首字延迟=整段生成耗时"的代价；后续可叠加 chunk 级软过滤作增强层。
6. **v1 流式端点范围**：`POST /api/v1/tutor/ask/stream`（答疑逐字）+ `POST /api/v1/tasks/generate/stream`（出题逐张题卡）。两处均前置现有 `require_role` + `check_quota` + `check_input`；`/tasks/generate/stream` 每生成一题经安全检查后再发 `question` 事件。

### SSE 事件信封（契约）【退役中 → 见迁移文档 `../../wayfinder/migration-08b-genkit-fullstack.md`】
> 2026-09-01 决策：前后端统一 Genkit 协议，前端改用 `package:genkit/client.dart` 的 `defineRemoteAction` 直连后端原生 flow，本自定义信封将随 `app/api/routes/stream.py` 退役。下方仅作迁移期对照。
```
event: token        data: {"text": "…"}          # 答疑文本增量
event: question      data: {<QuestionModel JSON>}  # 一题完成（出题流）
event: safety_refusal data: {"reason": "…"}       # 越狱/敏感被拦
event: done          data: {"usage": {"seconds": N}}  # 流结束 + 用量（供 quota 累计）
event: error         data: {"message": "…"}        # 500/502 友好文案
```
（历史实现）前端用 Dio/HttpClient 解析 SSE，`Riverpod` notifier 追加 token → 气泡打字机；`question` 事件入列表 → 题卡逐张浮现。迁移后改为 Genkit 原生 typed structured streaming。

### 备选
- **前端直连 Ollama**：延迟更低，但绕过 ADR-008 安全层，否决。
- **Genkit（Python 版）— 已采纳为统一 AI 栈**：经用户复核并 2026-09-01 拍板「前后端统一 Genkit 协议」，Genkit 的 Python 版 `genkit`+`genkit-fastapi` 在 FastAPI 进程内跑 flow（无 Node 依赖）、内置 SSE、`chunk_type` 字段级结构化流式，与本项目栈兼容；**前端同步采用 `package:genkit/client.dart` 的 `defineRemoteAction` 直连后端 flow**，前后端单一 Genkit 协议。原「非流式真实调用走 LangChainProvider 以避免第二套框架」的折中已被推翻——统一后 `LangChainProvider` 退役，非流式真实调用也走 Genkit OpenAI 插件，彻底单栈（详见迁移文档 `../../wayfinder/migration-08b-genkit-fullstack.md`）。
- **`genui` catalog 真·GenUI**：最贴近 CopilotKit，但 alpha + WebSocket 协议 + 提示词/schema 工程重，v1 否决、留作扩展点。
- **新增直连 HTTP provider 绕过 LangChain**：流式性能略好，但偏离 ADR-003 框架抽象，否决。

### 后果
- 本地 Ollama 可零云成本/零外网跑模型；流式首字即显（答疑）与逐张题卡（出题）显著提升低龄体感（即用户所言"模型优化"的体感收益）。
- 流式编排改由 Genkit 承担：`chunk_type` 字段级结构化流式天然适配"出题逐张题卡"，工具调用一等公民使 T11 知识库检索可作接地工具，且自带 Dev UI 追踪；`serve_flow` 直接挂 FastAPI 路由、原生 SSE。
- 框架 import 隔离延续 ADR-003：`genkit` 仅存在于 `app/ai/`（flow 层），业务/domain 仍只依赖 `LLMProvider` ABC；前端改依赖 `genkit` Dart 客户端（`package:genkit/client.dart`）直连 flow，**前后端单一 Genkit 协议**。`MockProvider` 独立类退役、改为 flow 内 mock 分支；`LangChainProvider` 退役、非流式真实调用并入 Genkit。模型可插拔（ADR-003/004）延续。安全防线在流式下仍由后端 flow 独占（ADR-008 不降级）。
- 安全防线在流式下仍由后端独占，儿童内容防护不降级。
- 代价：①v1 答疑首字有整段生成延迟（本地 Ollama 通常可接受）；②需新增 `ModelConfig` 表与加密存储（api_key 用 Fernet，密钥取 settings）；③`genui` 真·GenUI 暂未采用，若后续要 CopilotKit 式交互需另立票；④需引入 SSE 客户端与事件解析（前端新增 ~1 个网络层 + notifier 改造）。
- 默认 Ollama 地址 `OLLAMA_BASE_URL`（默认 `http://localhost:11434`）；provider 调用失败返回 502 友好文案，**不静默回退 MockProvider**（除非显式 `MODEL_FALLBACK=mock`）。

## ADR-0016 合并「生成任务」与「预览出题」为统一「出题」流程（先出题 → 手动同步到任务/题库）

> 来源：`/grill-with-docs` 访谈收敛（合并入口 / 先出题后同步 / 题库同步粒度 / 任务落库态 / 题任务关系）。配套实现票据见 `../../wayfinder/tickets/`（待立）。

### 背景
家长端当前有两个并列入口，底层却共用同一套能力：
- **「生成任务」**：流式渲染题卡后立即 `POST /tasks/from-generated` 自动落库为 `draft` 任务（延续 R3）。
- **「预览出题」**：流式渲染题卡但**不落库**，需手动点「保存为任务」才落库。

两者都是同一个 Genkit flow `tasksGenerate`（`POST /api/v1/ai/tasks/generate`，ADR-0015）的流式消费 + 同一个落库端点 `POST /tasks/from-generated`，仅"流结束后是否自动落库"不同。这造成两套心智——一个静默建草稿、一个不建——与家长的真实心理（"先看 AI 出什么题，再决定拿去派发还是留着好题"）一致性差；且「生成任务」会误产家长并不想要的草稿。

另一处缺口：当前草稿题 `TaskQuestion.question_id = None`（R-Q1=c），**不入题库**，AI 生成的好题在任务用完即弃，无法沉淀为可复用题源；家长期望的"挑好题留存"尚非主流程。

### 决策（六条，经 /grill-with-docs 访谈锁定）
1. **统一入口为单一「出题」按钮**：删除「生成任务」「预览出题」两个并列按钮，合并为「出题」。点击后按规格（学科/年级/知识点/题型/数量、兴趣聚焦、模型）流式产出题卡预览（逐张浮现，沿用 ADR-0015 协议）。
2. **先出题、后显式同步（手动）**：预览态**不自动落库**。题卡下方提供两个独立动作——「存为任务」「加入题库」——均由家长主动触发，可独立或同时执行。消除"自动建草稿"的隐性行为。
3. **题库同步粒度 = 逐题多选**：预览页每张题卡可勾选；「加入题库」只把勾选的题写入题库（新建 `Question` 行），未勾选的不入。实现"挑好题留存"。
4. **任务落库态 = draft**：「存为任务」仍落库为 `draft`（延续 R3），进入草稿审核页再派发，不直派。
5. **题任务关系 = 关联引用**：同一题既存任务又入题库时，任务题 `TaskQuestion.question_id` 指向刚建的题库 `Question`（DRY，题库为唯一真源）；仅存任务不入题库时维持 `question_id = None` 的快照（现有行为）。
6. **复用既有端点、不新增出题编排**：「存为任务」复用 `POST /tasks/from-generated`（流式题卡 → draft 任务）；「加入题库」新增 `POST /questions/bank/bulk`（批量把勾选题卡建为 `Question`，需经 `check_output` 安全闸门，延续 ADR-008）。两动作均消费同一批已流式题卡，避免二次生成。

### 备选
- **整卷一次性入题库**：实现最简，但会混入不理想题 → 否决（选逐题多选）。
- **「生成任务」改 ready/assigned 直派**：跳过审核，失去 R3 把关 → 否决（维持 draft）。
- **任务题独立副本**（入题库时再拷一份）：简单但题库与任务双真源会漂移 → 否决（选关联引用）。
- **两按钮改名保留**：改动小但入口仍两个、心智仍分裂 → 否决（选单一「出题」）。

### 后果
- 家长心智统一：先出题、后决定去向（派发 or 留存），符合自然决策顺序；消除「生成任务」误产草稿。
- 题库首次成为一等公民：好题可沉淀复用，后续「从题库建任务」`from-bank` 直接消费。
- 关联引用使题库为唯一真源，编辑题库可联动任务；级联删除需显式处理（被引用题库题禁止删，或任务题 `question_id` 置 NULL）。
- 实现影响：前端入口合并（删两按钮、加「出题」+ 预览多选 + 两动作）、`home_notifier` 状态机微调（预览态新增 `selectedForBank` 集合）；后端新增 `POST /questions/bank/bulk`、复用 `from-generated`；**流式渲染代码（Genkit flow、SSE 协议）不变**。
- 安全：入题库题仍过 `check_output`（生成时已校验，落库前再确认），不降低 ADR-008 防线。
- 向后兼容：`from-bank`、`from-generated` 端点保留；仅前端入口重排，旧草稿任务数据不受影响。

## ADR-0017 出题推理过程流式通道（合并 thinking+typing 为 REASONING chunk，参考 AG-UI）

> 来源：`/grill-with-docs` 访谈收敛（R6 后续）。修订 ADR-0016 中「流式渲染代码（Genkit flow、SSE 协议）不变」一句——本 ADR 正是 SSE chunk 信封的演进。

### 背景
R6 分析指出：当前 `tasks_generate` 走 `engine.genkit.generate_stream(..., output_schema=QuestionSchema)` 结构化输出，**后端每题只发 1 个 chunk（成品题卡）+ 末帧 result**，中间无任何 token 流。体验上「每生成一题都要干等，题卡整张弹出」，割裂感来自此处。用户期望在客户端**持续看到 AI 的出题推理过程**，并消除等待的空窗。

访谈澄清并锁定两个概念（此前方案误拆为 think/typing/card 三个类型，已纠正）：
- **`card`（题卡）** = 最终结构化题目（stem/options/answer/explanation），是数据，不变。
- **`thinking`（出题推理）** = 模型「怎么设计这道题」的文字说明；**`typing`（打字机）** = 前端把这段推理文字**逐字揭示的动画效果**——它**不是数据类型**，而是 `reasoning` 通道的呈现方式。

⇒ 合并后的产物 = **单一 `REASONING` 通道**，承载模型出题思路文字，前端用打字机动画渲染；`card` 仍是独立题卡数据。原 think+typing 二合一即指此。

### 决策（八条）
1. **单一推理通道 `REASONING`**：废弃「think / typing / card 三类型」拆法，SSE 只新增一种 chunk 类型 `REASONING`（增量 `delta`），与既有 `CARD` 并列；`typing` 是 `REASONING` 的客户端打字机动画，不进入协议。
2. **信封沿用 AG-UI 多态 `type` 判别**：每个 chunk 是一个 JSON 对象，靠 `type` 字段分发（`REASONING` / `STEP` / `CARD`），对齐 AG-UI 的 `BaseEvent.type` 多态约定（见映射表）。这是对我们现有 Genkit `chunk_type=dict` 帧（`data: {"message": <chunk>}`）的最小扩展——chunk 由「裸 QuestionOut」变为「带 `type` 的信封」，传输层不变。
3. **发射顺序（每道题）**：`STEP`（进度提示）→ `REASONING`×(0..N)（推理增量）→ `CARD`（成品题卡）。`STEP` 对应 AG-UI `STEP_STARTED`，给家长"正在为《数学》三年级「分数」出选择题"的进度锚点。`REASONING` 仅在**该题 CARD 到达前**作为题卡上方的内联流式区逐字揭示；CARD 到达后该内联区折叠（见决策 9），避免占据纵向空间。
4. **末帧 `result` 不变**：流式结束帧仍为 `List[QuestionOut]`（题卡列表），与 ADR-0015/0016 契约一致；`REASONING` 纯属流式 UX，**不进 result 帧**，避免 `fromResponse`/`onResult` 改动面。
5. **推理来源 = 混合**（访谈选定）：
   - **打底（所有模型，含 mock）**：`QuestionSchema` 增 `reasoning: str` 字段，单次结构化调用即拿到整段推理；后端发**一个 `REASONING` chunk**（整段为 `delta`），**客户端打字机动画揭示**（零额外成本、模型无关）。
   - **升级（reasoning 模型）**：当所选模型被 `resolve_engine` 标记为 `supports_reasoning`（如 DeepSeek-R1 / o-series，`engine.py` 新增布尔位），后端在结构化调用期间**实时读取提供方的思维链 token**（Genkit chunk 的 `reasoning`/provider 专用字段），边到边发 `REASONING` 增量——这才是真·服务端持续推流，填满等待空窗。
6. **推理仅预览态、不落库**：`REASONING` 是生成期 UX artifact，**不入题库/任务表**，零 DB 迁移；刷新或落库后消失（符合「出题过程」的瞬时性质）。`QuestionPreview` 上的 `reasoning` 字段仅用于流结束后在预览态内存中兜底展示，不写入 `Question`/`TaskQuestion` ORM。
7. **粒度 = 逐题**：每段推理用 `q_index` 与题卡关联；出题循环内每题重置 `REASONING` 缓冲，UI 在对应题卡上方展示「AI 怎么想的」。
8. **mock 确定性推理**：`_mock_question` 增确定性 `reasoning` 文本（如"围绕知识点 X 设计 Y 题，难度 Z，干扰项按常见误区设置"），保证零 key 也演示流式推理。
9. **CARD 到达后默认折叠 REASONING + 卡片 info icon 展开**：多题并排/矩阵排布时，内联推理区会让每张卡片纵向过长、难以一览。约定——某题 `CARD` 到达后，该题的实时推理区**默认折叠隐藏**，`REASONING` 文本以 `question.reasoning` 形式随题卡落于预览态内存；**每张题卡右上角常驻一个 info icon**，点击以 popover / bottom-sheet 展开「AI 出题思路」面板展示该题 `reasoning`（仅展示、不编辑、不落库）。这样多题以紧凑卡片矩阵呈现（生成时持续可见推理、成稿后一览无压），按需点开单题推理。info icon 是**纯前端交互**，不新增任何 SSE 字段（`reasoning` 已随 `CARD` 的 `QuestionOut` 下发，见决策 6）。

### 数据结构

**后端（Pydantic，`app/ai/flows.py` / `models.py`）**
```python
# 信封：靠 type 多态分发（对齐 AG-UI BaseEvent）
class TaskGenReasoningChunk(BaseModel):
    type: Literal["REASONING"] = "REASONING"
    q_index: int
    delta: str                      # 推理增量；打底路径整段一次性下发，客户端打字机揭示

class TaskGenStepChunk(BaseModel):
    type: Literal["STEP"] = "STEP"
    q_index: int
    label: str                      # "正在为《数学》三年级「分数」出选择题…"

class TaskGenCardChunk(BaseModel):
    type: Literal["CARD"] = "CARD"
    q_index: int
    question: dict                  # QuestionOut.model_dump()

TaskGenChunk = TaskGenReasoningChunk | TaskGenStepChunk | TaskGenCardChunk

# QuestionSchema / QuestionOut 增字段（打底路径承载整段推理）
class QuestionOut(BaseModel):
    ...
    reasoning: str = ""             # 出题推理过程（仅预览展示，不落库）
```
发射：`ctx.send_chunk(chunk.model_dump())`（chunk_type=dict 不变）；`generate_questions_stream` 内部改为 yield 标记项 `(kind, payload)`，flow 映射为信封 chunk。

**前端（Dart，`models.dart` / `genkit_ai_client.dart` / `home_notifier.dart`）**
```dart
sealed class TaskGenChunk {
  const TaskGenChunk();
  factory TaskGenChunk.fromJson(Map<String, dynamic> json) => switch (json['type']) {
    'REASONING' => ReasoningChunk(json['q_index'] as int, json['delta'] as String),
    'STEP'      => StepChunk(json['q_index'] as int, json['label'] as String),
    'CARD'      => CardChunk(json['q_index'] as int,
                             QuestionPreview.fromJson(json['question'] as Map<String, dynamic>)),
    _ => throw FormatException('unknown chunk type: ${json['type']}'),
  };
}
class ReasoningChunk extends TaskGenChunk { final int qIndex; final String delta; }
class StepChunk extends TaskGenChunk { final int qIndex; final String label; }
class CardChunk extends TaskGenChunk { final int qIndex; final QuestionPreview question; }

// QuestionPreview 增可选字段（流结束兜底展示，向后兼容旧服务端）
class QuestionPreview {
  final String reasoning; // 默认 ''，旧 chunk 不含时忽略
  ...
}
```
客户端接线：`_tasksGenerate` 的 chunk 泛型由 `QuestionPreview` 改为 `TaskGenChunk`；`fromStreamChunk: (d) => TaskGenChunk.fromJson(d)`；`onResult` 仍为 `List<QuestionPreview>`（不变）。`home_notifier` 循环按 `q_index` 累积 `reasoningBuffers`：
- **生成中**：`ReasoningTypewriterWidget` 在题卡上方内联区逐字揭示该题 `REASONING` 流（打字机）。
- **CARD 到达后**：内联区折叠隐藏，`question.reasoning` 随卡落下；卡片右上角渲染 `CardReasoningInfoButton`（info icon），`onTap` 以 popover / `showModalBottomSheet` 展开「AI 出题思路」面板（只读 `question.reasoning`，不编辑、不落库）。多题以紧凑卡片矩阵排布，按需点开单题推理。
```dart
// 卡片右上角 info icon → 展开 question.reasoning（默认折叠，按需查看）
class CardReasoningInfoButton extends StatelessWidget {
  final QuestionPreview question;
  // onTap: showModalBottomSheet / popover 展示 question.reasoning（标题 "AI 出题思路"）
}
```

### AG-UI 事件映射（参考而非照搬）
| 本方案 | AG-UI 事件 | 说明 |
|---|---|---|
| `STEP` chunk | `STEP_STARTED` | 每题进度锚点（AG-UI 用 `step_name`，我们用 `label`） |
| `REASONING` 增量 | `REASONING_MESSAGE_CONTENT` / `REASONING_MESSAGE_CHUNK` | 出题思路逐片；AG-UI 另有 `REASONING_START`/`END` 我们用「CARD 到来即结束」隐含，不显式发 |
| `CARD` chunk | `TEXT_MESSAGE_CONTENT`（结构化变体） | 成品题卡；AG-UI 此处是自由文本，我们替换为结构化题卡 |
| 末帧 `result` | `RUN_FINISHED.result` | 题卡列表 |
| 错误帧 | `RUN_ERROR` | 沿用现有 `error: {"message":...}` 帧（main.py monkeypatch） |

> 不引入 AG-UI 的 `STATE_SNAPSHOT`/`TOOL_CALL_*`（出题流无共享状态机/工具调用），保持信封最小。

### 发射时序（单题）
```
后端                                  前端
STEP{q_index:0,label}  ────────▶  进度条："正在出题第1题"
REASONING{delta:"围绕…"} ──────▶  题卡上方「AI 出题思路」内联区逐字揭示（生成中可见；
                                  reasoning模型：token 边到边；
                                  打底：整段到客户端后打字机动画）
CARD{q_index:0,question} ──────▶  题卡浮现 → 上方推理区折叠隐藏(默认)；
                                  卡片右上角出现 info icon，
                                  点按 popover 展开 question.reasoning
（下一道 q_index:1 重复；多题以紧凑卡片矩阵并排，每卡右上角常驻 info icon）
… 全部完成 ─────────────────▶  result: [card0, card1, …]  → onResult(List<QuestionPreview>)
```

### 备选
- **保留 think/typing 两个独立类型**：区分"思考内容"与"打字效果"。否决——typing 是动画非数据，拆出徒增协议复杂度（访谈已纠正）。
- **每题 2 次调用真·流式（两阶段）**：推理真逐字。否决为默认——2x 成本/延迟；仅当 reasoning 模型原生支持时走升级路径（决策 5 已覆盖真流式诉求）。
- **推理入库为题元数据**：否决（选决策 6 仅预览态），避免 DB 迁移与版权/安全复核面扩大。
- **整次连续推理不按题切分**：否决（选决策 7 逐题），保留推理与题卡的对应关系。

### 后果 / 实现影响
- 体验：出题过程持续可见、等待空窗被推理流填补（reasoning 模型下为真流式），割裂感消除。
- 协议：SSE chunk 由裸 `QuestionOut` 升级为带 `type` 的信封；**传输帧格式（`message`/`result`/`error`）、`chunk_type=dict`、末帧 result 形状均不变**，向后兼容旧前端（旧 `fromStreamChunk` 仅解析 `QuestionOut`，升级前不读 `type`）。
- 代码改动面：`flows.py`（`generate_questions_stream` 改 yield 标记项 + `tasks_generate` 发信封）、`engine.py`（`EngineResolution.supports_reasoning`）、`models.py`/`QuestionOut`（`reasoning` 字段）、`models.dart`（`TaskGenChunk` 密封类 + `QuestionPreview.reasoning`）、`genkit_ai_client.dart`（chunk 泛型 + `fromStreamChunk`）、`home_notifier.dart`（按 `q_index` 累积推理 + 打字机态 + CARD 到达折叠）、预览 UI 新增 `ReasoningTypewriterWidget`（生成中内联揭示）与 `CardReasoningInfoButton`（卡片右上角 info icon，点按弹出该题 `reasoning`）。
- 安全：推理文本不落库、不进 `check_output` 复核链（仅成品题卡过 ADR-008 闸门），不降低现有防线。
- **实现状态：✅ 已落地（2026-09-01）**。后端 `flows.py`/`engine.py` 发信封 chunk（`STEP`/`REASONING`/`CARD`）+ `supports_reasoning`；`QuestionOut`/`QuestionSchema` 增 `reasoning`；前端 `models.dart` 增 `TaskGenChunk` 密封类与 `QuestionPreview.reasoning`，`genkit_ai_client.dart` 改 chunk 泛型，`home_notifier.dart` 按 `q_index` 累积推理并在 CARD 到达后折叠，`parent_task_form_view.dart` 新增 `_PreviewGenerating`（内联打字机推理）+ `_PreviewCard` 右上角 info icon（`_showReasoningSheet` 弹出 `reasoning`）+ 共享 `ReasoningTypewriterWidget`。流式回归测试 `test_generate_stream.py::test_generate_stream_emits_envelope` 断言每题 `STEP`/`REASONING`/`CARD` 齐全且 reasoning 非空；后端 pytest 全绿（133 passed/3 skipped），前端 `lib/` 改动 `flutter analyze` 零警告。
- 工作量：后端流式回归测试已随实现补齐（mock 推理 chunk 断言）。

## ADR-0018 文档目录结构对齐 ai.md（根目录散落文档归一化）

> 来源：`/grill-with-docs` 访谈收敛（依据 `ai.md` 的 AI-Native 项目结构）。分类映射见下方。

### 背景
项目根目录散落 15 个 `.md`（产品方案 / PRD / spec / T08~T13 任务文档 / 技术架构 / 实施文档 / ADR / 术语表），与 `ai.md` 推荐的 `docs/` 六类结构（product / requirements / ux / architecture / database / decisions）不符；`AGENTS.md` 作为项目协议入口，文档应按类型归类以提升跨 Agent 可读性。同时 `design/`、`wayfinder/`、`docs/agents/` 已有独立定位且被 `AGENTS.md` 大量引用。

### 决策（五条，经访谈锁定）
1. **仅迁移根目录散落文档**，归入 `docs/` 下 4 个有内容的英文分类目录：`product/`（3：产品方案 / PRD / spec）、`requirements/`（5：T08~T13 任务文档）、`architecture/`（5：技术架构_Flutter / 技术架构_后端 / 项目分析_架构规范与业务功能 / 实施文档_题库复用闭环_前端 / 实施文档_题库复用闭环_后端）、`decisions/`（2：ADR 合集 + 术语表/glossary）。
2. **`design/`、`wayfinder/`、`docs/agents/` 保留不动**（异常内容保留独立文件夹，Q3 确认）；它们分别承担设计稿 / 工单流转 / 代理指引角色，强行拆并需重写 `AGENTS.md` 大量链接，成本与风险高。
3. **`ux/`、`database/` 本次不创建**：设计稿（landing / 原型 / mockup）仍在 `design/`（承担 ux 角色），数据库建模规范在 `docs/agents/backend.md` 与 `wayfinder/02-数据建模与迁移.md`（承担 database 角色）；待出现专属内容再建目录。
4. **目录用英文命名**（`product/requirements/...`）以对齐 `ai.md`；文档文件名保持中文原样，避免额外链接断裂。
5. **迁移用 `git mv` 保留历史**，并用脚本按各文件所在目录重算相对路径，**同步修正所有引用链接**（`AGENTS.md`、`README.md`、`docs/agents/*`、`frontend/docs/adr/0004`、被迁文档之间的互相引用、`wayfinder/` 迁移文档），确保无死链。

### 备选
- **全量重组**（连 `docs/agents/`、`design/`、`wayfinder/` 一并拆并到六类）：否决，因 `AGENTS.md` 大量引用 `docs/agents/`，全量重写成本高、易引入死链；分阶段更稳。
- **根目录文档重命名为英文**：否决，偏离中文文档习惯且制造更多链接改动。

### 后果
- 根目录文档收敛，只剩 `AGENTS.md` / `README.md` / `ai.md`（方法论输入）与代码目录。
- `docs/` 分类清晰、跨 Agent 可读；本 ADR 锁定的归类成为新增文档的归位约定。
- 全部相对链接有效（脚本校验 + 人工复核 `wayfinder/` 路径）。
- 后续若有 ux / database 专属内容，直接新建对应目录并补 `AGENTS.md` 索引。

## ADR-0019 教材版权合规落地方案（上线前内容来源与检测）

> 来源：ADR-0012（版权硬门槛）的**操作化落地**。ADR-0012 只声明「上线前必须解决」，本 ADR 给出具体怎么做。配套实现票据见 `.scratch/wawa-learning/issues/11`（仅检索能力）。

### 背景
- ADR-0012 已锁定：开发/自用阶段可使用教材内容；凡做成对外分发产品，**上线前必须取得教材版权授权或改用公版/自编内容**。当前 T11 `KnowledgeRetriever` 已能检索教材知识点对齐出题，但**检索 ≠ 授权**——检索能力本身不解决版权。
- 现状风险：AI 出题/讲解若直接复制人教版等现行教材的例题原文、章节结构、题干表述，对外分发即构成侵权；家长端「对齐教材」诉求与版权硬门槛存在张力。
- 项目即将进入「上线准备期」（见阶段盘点），版权合规是**对外分发前的唯一不可绕过的硬门槛**（P0）。

### 决策（六条）
1. **内容来源分层（Source Tiers）**：按分发范围分级——
   - **自用/内测（Tier-0）**：允许 AI 生成或内部对齐教材，不对外发布即可；
   - **对外分发（Tier-1）**：内容必须来自 **公版（CC0 / 公有领域）/ 自编**，或已获**书面授权**的教材；严禁在对外产物中直接复制受版权保护教材的实质性内容（例题原文、章节结构、题干表述）。
2. **公版优先（Public-Domain First）**：默认走公版/自编内容源——民国老课本（公有领域）、统编前公版教材、团队自编习题与知识点。建立 `content/public-domain/` 受控内容库，出题/讲解优先命中此库。
3. **授权路径（Licensing Path）**：确需对标现行人教版/北师大版等时，走正规版权方商务授权（出版社/版权代理），**在立项前完成成本与可行性评估并留痕**；未获授权前对应「对标教材」功能不对外部用户开放。
4. **检索/知识库隔离（Retriever Sandbox）**：`KnowledgeRetriever` 命中教材原文片段**仅作内部对齐信号**，不向娃娃/家长直接展示原文大段；RAG 知识库入库内容限定为**自采/公版/已授权**素材，**禁止整页入库受版权保护的教材扫描件或电子书**。
5. **合规检测门禁（CI Gate）**：发布流水线（或发布前脚本）扫描生成内容/题库是否含受版权保护教材的**实质性复制**（章节结构雷同、例题原文重合度超阈值）；命中即**阻断发布**并告警，须人工复核放行。
6. **声明与免责（Notice）**：App 内标注内容版权归属与「非官方教材、仅供参考」声明；家长端模型/内容来源可见，外部分发版本默认不暴露具体教材对标文案。

### 备选
- **忽略版权直接分发**：法律风险不可承受，否决。
- **仅用公版、完全不自采授权内容**：最安全但丧失「对标现行教材」卖点，部分采纳（作为 Tier-1 默认）。
- **全自编习题库**：版权最干净但内容生产/校验成本高，作为长期演进方向，v1 不强制。

### 后果
- 上线前硬门槛有可执行路径：公版/自编为默认，授权为可选增强；检索能力（T11）不受影响但受隔离约束。
- 需建立：①`content/public-domain/` 公版内容库；②授权台账（若走授权路径）；③CI 合规检测脚本；④App 内声明文案。
- `KnowledgeRetriever` 实现需加「入库内容来源白名单」校验，避免误入库受保护素材。
- 与 ADR-0012 一致：自用无碍，对外分发前必须完成本 ADR 的 1/2/5/6 项方可发布。

## ADR-0020 云部署生产化（从本地 Docker 到可上线）

> 来源：ADR-006（本地 Docker 起步、架构按云设计）的演进。当前进入「上线准备期」，需把本地验证过的架构搬到可对外服务的生产环境。

### 背景
- ADR-006 选择本地 Docker 起步、架构按云设计；当前后端已无状态（DB 外置）、前端为独立 Flutter App，具备上云基础。
- 但现状仅满足「家庭自用 / 局域网联调」：Postgres 走 docker-compose、密钥写本地 `.env`、前端默认 `http://127.0.0.1:8000`、无 TLS、无 CI/CD、无监控。
- 对外分发需要：可公网访问的 HTTPS 后端、托管数据库、密钥外置、构建/部署自动化、基础可观测性。

### 决策（八条）
1. **后端无状态容器化（Stateless Image）**：沿用 FastAPI 镜像，多阶段构建、非 root 运行、内置 `/health`（`/api/v1/health`）作探针；不落本地状态（SQLite 仅本地/Tier-0，生产用托管 PG）。
2. **数据库上云（Managed Postgres）**：生产用托管 PostgreSQL（云厂商 RDS / 轻量云 PG）；连接串经**密钥服务**注入，禁止明文写仓库/镜像；迁移沿用 `app/core/db.py:run_migrations` 手写 ALTER（兼容 sqlite/PG，幂等）。
3. **配置与密钥管理（Secrets）**：`SECRET_KEY` / `LLM_API_KEY` / `ModelConfig.api_key`（Fernet 密钥取 settings）一律外置到密钥服务（Vault / 云 KMS / 托管 Secrets）；`.env` 仅本地开发用，生产环境不挂载。
4. **反向代理与 TLS（Edge TLS）**：前置 Caddy/Nginx 终止 TLS（对外 HTTPS）；前端 `API_BASE` 改 `https://` 域名；本地 Ollama 仅 Tier-0 家用，云端答疑走托管模型（ADR-0015 的 `ModelConfig` 已支持）。
5. **前端分发（App Distribution）**：Flutter 产物经 App Store / 应用市场 / 企业分发（TestFlight / 蒲公英）发布；`--dart-define=API_BASE=https://...` 固化生产地址；桌面端另走对应商店/直分。
6. **CI/CD（Quality Gate）**：GitHub Actions 串联 `uv run pytest`（后端全绿）+ `flutter analyze`（零警告）+ 镜像构建 + 部署；**测试全绿 + analyze 零警告为合并/发布门禁**（当前 `analyze` 全量仍有 13 个 pre-existing 错误，须先清零）。
7. **可观测性（Observability）**：结构化日志 + 基础监控（错误率/延迟/配额用量）；`tutor_log` 已存在，扩展为生产日志管道；不引入重运维 APM，v1 够用即可。
8. **跨设备同步（Sync，方向性）**：在云后端之上规划同步层（账号与按娃数据隔离已由 ADR-007 就绪）；v1 先支持「同账号多端读取最新状态」，离线编辑合并留作后续 ADR 细化，本期仅列方向不实现。

### 备选
- **继续纯本地 / 局域网**：无法对外分发，否决（与上线目标冲突）。
- **Serverless（如云函数跑 FastAPI）**：冷启动 + Genkit 长流式适配成本高，v1 否决，留作演进。
- **BaaS（Supabase 等）替换自研后端**：与现有 SQLModel/FastAPI 栈重复，否决。
- **前端直连托管模型**：绕过 ADR-008 安全层，否决（须始终经后端 `/api/v1`）。

### 后果
- 具备对外分发能力：HTTPS 后端 + 托管 PG + 密钥外置 + 自动构建部署。
- 引入运维成本（监控/密钥轮换/证书续期）；需先清零 `flutter analyze` 既有错误以满足 CI 门禁。
- 本地 Ollama 零云成本体验保留给 Tier-0 家用；对外版本默认走托管模型（数据出户需告知家长）。
- 与既有决策一致：ADR-003（框架隔离）、ADR-008（安全不降级）、ADR-0015（Genkit 单栈）在云端不变。

## ADR-0021 多 Agent 架构：业务 SubAgent + 学科 Persona 参数

> 来源：三期 MVP 闭环已落地（出题 / 伴学 / 批改 / 复习 / 掌握度），进入「打磨完善」期。原 `LLMProvider` 仅 3 个扁平方法（出题/批改/伴学），无 orchestrator；`KnowledgeRetriever` 已实现但全代码库零调用（死代码）；`subject/grade` 已落在 `TaskSpec/Question/Task` 等模型却未用于 agent 选路。

### 背景
- 业务将不止「出题」一项：错题诊断归因、知识点讲解、个性化复习规划、家长学情报告等都可基于现有领域模型（WrongQuestion / review_scheduler / Mastery / TutorService / AI 日志）拓展为独立业务能力。
- 若把「学科」当顶层路由键、为每个业务硬编码学科系统提示词，业务数 × 学科数 的 prompt 组合不可维护。
- 用户诉求：需要「主 Agent 负责规划/派发 + 多个 SubAgent 各管具体业务」，而非单一大 prompt。
- `tutor.py` 伴学已半接 RAG（命中知识库拼上下文）；出题仍是纯自由生成未接 RAG。

### 决策（六条）
1. **业务维度 = SubAgent（多 agent 在业务层）**：每个业务（出题 / 伴学 / 批改 / 诊断 / 规划 / 报告…）是一个独立 subagent，拥有自己的 system prompt + 工具 + 可选 RAG + 输出 schema，通过注册表按业务键派发。
2. **学科维度 = Persona 参数（非顶层路由键）**：`SubjectPersona` 配置表按学科归一化（数学/语文/英语/科学…），产出「语气 / 适龄 / 学科约定」，作为**统一参数注入每个 subagent** 的 prompt，不单独成 agent。
3. **轻主管（Light Orchestrator）**：业务意图由前端路由已知（出题页 / 伴学页本就分离），学科作 persona 参数注入；主管 Agent 只在需多步编排的业务内做规划（如伴学：诊断错因 → 讲知识点 → 顺手出巩固题 → 排进复习），不做每次 LLM 意图分类。
4. **SubjectPersona 代码内静态配置**：落在 `app/ai/subject_personas.py`（枚举键字典），分层清晰、可单测、零 CRUD；改学科 = 改代码；接口预留未来迁 DB 表（家长/运营可编辑）。
5. **首轮双 SubAgent 验证 seam**：第一轮同时落地「出题 SubAgent（接 RAG）+ 伴学 SubAgent（接 SubjectPersona）」，确立 subagent 注册表 + persona 注入范式，后续诊断/批改/规划直接套模板。
6. **接口预留升级为完整 Supervisor**：每个 subagent 暴露统一契约 `handle(intent, ctx) -> result`；当前路由显式派发，未来若接「统一 AI 助手」对话入口，可在不改动 subagent 的前提下插入 LLM 意图分类层升级为完整 supervisor。

### 备选
- **单 Agent + 学科条件化（早前选项 A）**：业务少时省成本，但业务变多即退化为学科×业务 prompt 组合，否决（本次架构升级的核心动机）。
- **学科即 SubAgent（每学科一个 agent）**：隔离强、可挂学科专属工具（数学公式求解器），但路由一致性 / token 成本 / 维护显著更高；K12 学科差异主要是 prompt 与知识库而非推理能力，否决（仅在出现结构性分歧时再拆）。
- **完整 LLM Supervisor（每次意图分类）**：支持未来统一对话入口，但多一次 LLM 调用、需意图分类数据与评测、路由一致性更难；当前前端已分离业务意图，否决（已预留升级路径）。

### 术语（Glossary）
- **Orchestrator（主管 Agent）**：接收请求、做多步规划、派发到 subagent；本 ADR 中为「轻」形态（业务由路由已知，不做意图分类）。
- **Business SubAgent（业务子代理）**：单一业务能力的 agent（出题 / 伴学 / 批改 / 诊断 / 规划 / 报告），独占 prompt + 工具 + 可选 RAG。
- **SubjectPersona（学科人格）**：按学科归一化的「语气/适龄/学科约定」配置，作为参数注入所有 subagent，使同一业务跨学科表现一致且可控。
- **Seam（接缝）**：subagent 注册表 + persona 注入的统一范式；「加业务 = 加一个 subagent，加学科 = 加一条配置」即此 seam 的体现。

### 后果
- **零组合爆炸**：加业务与加学科正交解耦；新增业务只写新 subagent，新增学科只加一行 persona 配置。
- **出题接 RAG**：把死代码 `KnowledgeRetriever` 接进出题流，解决「纯自由生成、未对齐教材」痛点（呼应 ADR-009）。
- **伴学按学科适配**：复用 `tutor.py` 已有 RAG，叠加 SubjectPersona 切换语气/深度/学科约定，统一为 subagent 形态。
- **复用底座**：subagent 共用 `LLMProvider` / `resolve_engine` / `quota` / `safety` / `retriever`，不重复造轮子（与 ADR-003 框架隔离一致）。
- **预留演进**：接口契约支持未来无痛升级为完整 LLM supervisor，不锁定当前轻形态。
- **成本**：伴学多步规划会增加一次到数次 LLM 调用，须受 `quota` 约束（ADR-008）；其余业务单次调用，无额外开销。

## ADR-0022 AI 运行可观测：conversation + message 调试库

> 来源：三期 MVP 闭环已落地（出题 / 伴学 / 批改 / 复习 / 掌握度），进入「打磨完善」期。需在不出生产环境的前提下，完整回放一次 Agent 运行（系统提示 → 检索 → 推理 → 题卡/答案 → 工具调用），用于调试模型输出与定位 bad case。

### 背景
- 现有 `TutorLog` 只存「一问一答」（question + answer + 安全标记），且服务**家长可见合规**（ADR-008）：驱动家长端答疑日志页（`parent_tutor_logs_view.dart`）与每日提问次数上限（`count_tutor_today`）。它是扁平单行，无法还原 Agent 运行的多步结构。
- 一次出题/批改本质是**多步 Agent 运行**：系统提示 → 学科 Persona 注入 → 知识库检索（RAG）→ 出题推理（reasoning）→ 结构化题卡/批改结果 → 可能的工具调用。调试要能按步骤回放，而不是只看首尾。
- 用户诉求：新建 `message` 表记录 AI 返回的数据，且明确「本意是方便调试 Agent 输出」。
- 主流对话存储范式（OpenAI Chat / Anthropic / LangChain chat memory）均为 `conversation`（一次会话/运行）+ `message`（带 `role` 的一步），本项目在此范式上补充业务关系。

### 决策（六条）
1. **两张表，不合并**：`conversation` = 一次 Agent 运行（运行类型 `kind`、归属 `parent_id`、触发者 `child_id`、所用模型、状态）；`message` = 运行内带 `role`+`step` 的一步。一张扁平表压扁中间过程，否决。
2. **message 用 `role` + `step` 两列**：`role ∈ {system, user, assistant, tool}`（谁产生），`step ∈ {input, retrieval, reasoning, generation, tool_call, output, error}`（运行到哪一步）。调试可按 `step` 过滤还原全过程；`tool` 角色覆盖工具调用（参数/结果存 `payload`）。
3. **content（TEXT）+ payload（JSON）双列**：`content` 存人类可读文本（家长/调试可读），`payload` 存结构化原始数据（题卡 dict / 模型原始响应 / 检索块 / 工具参数），兼顾可读与回放/复现。
4. **与 `TutorLog` 边界清晰、不重复**：`TutorLog` 继续管答疑合规（家长可见 + 每日上限，已上线接 UI），`conversation/message` 只做 **Agent 运行调试库**（出题 / 批改 / 通用 agent 流）。答疑不写入调试库，避免双份存储。
5. **业务关系补在 conversation 上**：`parent_id`（owner 隔离，呼应题库闭环）、`child_id`（触发者，出题可为 null=家长）、`model`（模型引用，内置 id / ModelConfig id）、`ref_task_id`（关联生成的 Task，便于追溯「这卷题为啥长这样」）、`status`（running/done/error/blocked）。`message` 经 `conversation_id` 归属，自身只带 `model`/`input_safe`/`output_safe`/`blocked`/`latency_ms`/`usage`（token）。
6. **`kind` 用开放 str**：初始值 `question`(出题) / `grade`(批改) / `agent`(通用 agent 运行，含 subagent 流)；未来加 `summarize`/`explain` 直接加字符串值，无需迁移。不引数据库 ENUM（sqlite 无原生枚举、postgres ENUM 需迁移）。

### 备选
- **单一扁平 message 表（早期方案）**：实现快，但压扁多步过程，调试价值低，否决。
- **conversation/message 取代 TutorLog（统一）**：单一数据源，但要改写家长答疑日志页 + 每日上限计数 + 落库路径，且答疑相对简单不值得进调试库；保留 TutorLog 更低风险，否决统一。
- **数据库 ENUM 约束 kind/role/step**：类型安全，但加值需迁移、sqlite 体验差；开放 str 更灵活，否决。

### 术语（Glossary）
- **Conversation（AI 运行）**：一次 Agent 运行的容器；聚合其所有 message，携带运行类型/归属/模型/状态。
- **Message（运行步骤）**：conversation 内带 `role` 与 `step` 的一步记录；`content` 可读文本 + `payload` 结构化原始数据。
- **role（消息角色）**：`system`（系统提示）/ `user`（用户/前端输入）/ `assistant`（模型输出）/ `tool`（工具调用）。
- **step（运行阶段）**：`input`（请求）/ `retrieval`（检索）/ `reasoning`（推理）/ `generation`（生成中）/ `tool_call`（工具调用）/ `output`（最终输出）/ `error`（异常）。
- **Agent 运行调试库**：`conversation`+`message` 组成的、与 `TutorLog` 职责分离的 AI 可观测存储，用于回放与定位 bad case。

### 后果
- **可完整回放**：出题/批改一次运行的全过程可逐步还原，调试 Agent 输出从「盲猜」变「可查」。
- **零重复**：答疑仍走 `TutorLog`，调试库只覆盖多步 Agent 运行，职责正交。
- **低风险落地**：新建表由 `SQLModel.metadata.create_all` + `run_migrations` 的 `CREATE TABLE IF NOT EXISTS` 自动建表；落库用 try/except 包裹，调试日志失败绝不阻断主流程（同 `_log_tutor`）。
- **可观测性**：`status`/`latency_ms`/`usage`(token)/`blocked` 使「哪步慢 / 哪个被安全拦截 / 花多少 token」可量化。
- **成本**：每条 AI 运行多写若干 message 行；调试库建议后续接保留期/TTL（不在本期范围），避免无限膨胀。
