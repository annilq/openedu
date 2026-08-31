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
  3. **响应式断点（Breakpoints）**：`compact < 700` / `medium 700–1023` / `expanded ≥ 1024`。compact 收起侧栏为底部导航（娃娃）/抽屉（家长）；medium 侧栏可收起；expanded 展开侧栏 + 内容区。
  4. **适度趣味动效（Moderate Delight）**：保留 120/200/300ms 三级；新增 `celebrate` 级（~450ms）用于徽章解锁 / 连击 / 打卡成功，仅 Child Mode 启用；做题反馈清晰不喧宾。
- **备选**：维持 ADR-0003 单一专业系统 / 全设备响应式（手机优先）/ 丰富游戏化（多邻国式）。
- **后果**：正式承认代码里已存在的双轨（child_home 横幅本就更活泼）；需扩充令牌（Child Mode 字号阶梯、学科色、断点、celebrate 动效）并新增双模式切换与响应式壳；需一轮「规范一致性审计」修掉既有 `withValues(alpha:)` 与缺描边违反。**本 ADR 修订 ADR-0003 中『娃娃共用单一密排系统』的判定，改为双模式。**

## ADR-0015 多模型接入（Ollama / 自定义）+ 流式响应 + 轻量 GenUI

> 来源：`/grill-with-docs` 访谈收敛（模型优化 / 本地 Ollama / 流式 UI / GenUI / 前端模型选择器）。配套实现票据见 `wayfinder/tickets/08-多模型流式genui.md`。

### 背景
一期~三期已用 `MockProvider`（默认）+ `LangChainProvider`（真实模型）跑通全闭环，但存在三点诉求：①家用以**本地 Ollama** 跑模型可零云成本、零外网延迟、数据不出户；②答疑/出题希望**流式输出**改善体感（打字机 / 逐张题卡）；③前端要能**选择后端支持的模型**、出题时**自选或自定义模型**。用户要求参考 CopilotKit 式 GenUI，但前端是 Flutter，而 CopilotKit 无 Flutter SDK；候选官方方案为 Flutter `genui`（alpha，A2UI 原生走 WebSocket）与 Genkit（Flutter 端 `genkit/client.dart` 需接 Genkit flow 后端，而 **Genkit 的 Python 版 `genkit` + `genkit-fastapi` 可在 FastAPI 进程内直接挂 flow、`Accept: text/event-stream` 即 SSE、并支持 `chunk_type` 字段级结构化流式**，故与本项目 Python/FastAPI 栈**兼容**；已采纳为 v1 流式编排引擎（见决策 3 与备选）。

### 决策（六条，均经访谈锁定）
1. **后端统一代理（守安全）**：Flutter 一律只连 `/api/v1` 的 SSE 端点；Ollama 与自定义模型由后端调用。服务端始终注入 `_SYSTEM` 年龄锁并对娃娃可输入字段跑 `check_input`、对输出跑 `check_output`，**安全层永不绕过**（忠诚 ADR-008）。禁止前端直连任何模型。
2. **轻量流式渲染（非真·catalog GenUI）**：SSE 推 `token` 文本块 + 结构化事件（`question` 等），前端边收边渲染（答疑气泡打字机、出题逐张题卡）。不引入 `genui` 的 CatalogItem/工具调用式生成式 UI——因其处 alpha、A2UI 原生 WebSocket 与本项目 SSE 偏好冲突、且需改造提示词与 schema 工程。保留未来对个别高价值场景（如"给个例题卡"）试点 catalog GenUI 的扩展点。
3. **改用 Genkit Python 编排流式 flow（替代原「LangChainProvider 扩展」方案）**：流式 AI 输出（答疑逐字 + 出题逐张题卡）由 Genkit flow 编排，新增 `app/ai/`（**唯一允许 `import genkit` 的边界**，类比原 `LangChainProvider` 作为 langchain 适配层）承载：`Genkit` 实例、`serve_flow`/SSE 挂载、模型解析（Ollama / OpenAI-compat / 内置，按 `ModelConfig` + settings 把 `provider/model_name` 解析为 `ollama/{m}` / `openai/{m}`）与工具调用（T11 知识库检索作接地工具）。**ADR-003 延续**：业务/domain 代码仍只依赖 `LLMProvider` ABC 与非流式路径（`MockProvider` 供测试、`LangChainProvider` 供非流式真实调用），`genkit` 不被业务代码直接 import；流式端点由 API 层调用 `app/ai` 的 flow。
4. **模型注册 = 配置驱动 + 家长自定义**：内置模型由 settings/env 声明并暴露 `GET /api/v1/models`（parent 可见）；家长自定义模型落 `ModelConfig` 表（仿 `TutorQuota`，按 `parent_id` 持久化：`label / provider('ollama'|'openai_compat') / base_url / model_name / api_key(加密)`）。**模型选择器仅家长可用**；娃娃继承家长默认模型，娃娃端不暴露下拉（避免娃娃自选未授权/不安全模型）。请求参数 `model`（id 或内置 id）可选，缺省走家长默认或全局 `DEFAULT_MODEL`。
5. **流式安全 = 缓冲 + 整体校验后放行**：`/tutor/ask/stream` 先 `check_input` 拦越狱（命中即发 `safety_refusal` 不再调模型）；通过后后端**缓冲全量 token、跑整体 `check_output`**，通过才向娃娃放量，违规则整段替换为 `SAFE_REFUSAL`。儿童端绝不闪现违规片段。v1 接受"首字延迟=整段生成耗时"的代价；后续可叠加 chunk 级软过滤作增强层。
6. **v1 流式端点范围**：`POST /api/v1/tutor/ask/stream`（答疑逐字）+ `POST /api/v1/tasks/generate/stream`（出题逐张题卡）。两处均前置现有 `require_role` + `check_quota` + `check_input`；`/tasks/generate/stream` 每生成一题经安全检查后再发 `question` 事件。

### SSE 事件信封（契约）
```
event: token        data: {"text": "…"}          # 答疑文本增量
event: question      data: {<QuestionModel JSON>}  # 一题完成（出题流）
event: safety_refusal data: {"reason": "…"}       # 越狱/敏感被拦
event: done          data: {"usage": {"seconds": N}}  # 流结束 + 用量（供 quota 累计）
event: error         data: {"message": "…"}        # 500/502 友好文案
```
前端用 Dio/HttpClient 解析 SSE，`Riverpod` notifier 追加 token → 气泡打字机；`question` 事件入列表 → 题卡逐张浮现。

### 备选
- **前端直连 Ollama**：延迟更低，但绕过 ADR-008 安全层，否决。
- **Genkit（Python 版）— 已采纳为流式编排引擎**：经用户复核，Genkit 的 Python 版 `genkit`+`genkit-fastapi` 可在 FastAPI 进程内跑 flow（无 Node 依赖）、内置 SSE、`chunk_type` 字段级结构化流式，与本项目栈兼容，故 v1 改由它编排流式 flow；为避免"引入第二套框架破坏 ADR-003"，**非流式**真实调用仍走既有 `LangChainProvider`，二者通过 `LLMProvider` ABC 统一，框架 import 各自隔离（`langchain` 仅在 `LangChainProvider`、`genkit` 仅在 `app/ai/`）。
- **`genui` catalog 真·GenUI**：最贴近 CopilotKit，但 alpha + WebSocket 协议 + 提示词/schema 工程重，v1 否决、留作扩展点。
- **新增直连 HTTP provider 绕过 LangChain**：流式性能略好，但偏离 ADR-003 框架抽象，否决。

### 后果
- 本地 Ollama 可零云成本/零外网跑模型；流式首字即显（答疑）与逐张题卡（出题）显著提升低龄体感（即用户所言"模型优化"的体感收益）。
- 流式编排改由 Genkit 承担：`chunk_type` 字段级结构化流式天然适配"出题逐张题卡"，工具调用一等公民使 T11 知识库检索可作接地工具，且自带 Dev UI 追踪；`serve_flow` 直接挂 FastAPI 路由、原生 SSE。
- 框架 import 隔离延续 ADR-003：`genkit` 仅存在于 `app/ai/`，业务/domain 仍只依赖 `LLMProvider` ABC 与非流式路径（`MockProvider`/`LangChainProvider`）；模型可插拔（ADR-003/004）延续。
- 安全防线在流式下仍由后端独占，儿童内容防护不降级。
- 代价：①v1 答疑首字有整段生成延迟（本地 Ollama 通常可接受）；②需新增 `ModelConfig` 表与加密存储（api_key 用 Fernet，密钥取 settings）；③`genui` 真·GenUI 暂未采用，若后续要 CopilotKit 式交互需另立票；④需引入 SSE 客户端与事件解析（前端新增 ~1 个网络层 + notifier 改造）。
- 默认 Ollama 地址 `OLLAMA_BASE_URL`（默认 `http://localhost:11434`）；provider 调用失败返回 502 友好文案，**不静默回退 MockProvider**（除非显式 `MODEL_FALLBACK=mock`）。
