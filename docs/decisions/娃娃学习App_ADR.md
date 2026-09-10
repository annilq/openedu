# 架构决策记录（ADR）· 娃娃学习应用

> 记录关键架构决策：背景、决策、备选、后果。状态统一为「已采纳」。

---

## ADR-001 前端技术选型：Flutter 原生 App
- **背景**：目标用户为低龄娃娃，主力设备是平板；需跨 iOS/Android。
- **决策**：采用 Flutter 开发原生 App，平板优先。
- **备选**：PWA 网页（跨设备、免上架）、微信小程序（国内管控友好但 AI 受限）。
- **后果**：一套代码出双端；UI 表现力足；需自行上架/分发；AI 调用必须经后端（前端不藏 key）。

## ADR-002 后端语言：Python
- **背景**：AI 编排需成熟 Python 生态，且后端须与前端（Flutter）解耦、独立部署。
- **决策**：后端用 Python（FastAPI）。
- **备选**：TypeScript/Node、Python+TS 混合。
- **后果**：Python 生态成熟、与 Genkit 等 AI 框架契合（ADR-0015）；前端一律经后端 `/api/v1` 调用，不藏 key（ADR-001）。

## ADR-003 AI 编排：框架隔离 + 自封领域接口（Genkit 为底座）
- **背景**：希望"适配大部分大模型厂商"且未来可换框架；业务代码不应绑定具体 AI 框架。
- **决策**：运行时 AI 编排底座采用 **`LLMProvider` 抽象 + 可插拔引擎**；底层 LLM 引擎当前为 Genkit Python 版，但**仅经 `app/ai/engine.py`（`engine.genkit`）作为内部引擎调用，不再使用 `genkit-fastapi` 暴露原生 action 端点**（传输 / 编排层已迁至 `AgentRuntime` + 自建 SSE，见 ADR-0024/0025），详见 ADR-0015。在"agent 框架层"之上自封一层**领域服务接口**（`LLMProvider` ABC + 业务 SubAgent/flow）+ 框架 adapter。**业务/domain 代码只依赖 `LLMProvider` 抽象，绝不直接 `import genkit`**（唯一允许边界为 `app/ai/engine.py`）。
- **备选**：直接把框架对象透传给业务层、为每个厂商手写 BaseProvider。
- **后果**：厂商适配由框架/解析层隔离（`resolve_engine` 解析真实引擎，解析不到走 flow 内 mock 分支）；业务代码不绑定具体框架，换底座只需改 `app/ai/` adapter；模型可插拔延续（ADR-004）。
- **历史注**：本 ADR 初版以 LangChain 为底座，后于 ADR-0015 评估并切换为 Genkit 单栈，LangChain 整体退役；抽象隔离原则不变。（**现状**：Genkit 已非「编排单栈」，自 2026-09-08 清理后仅余底层 LLM 引擎角色，`genkit-fastapi` 与原生 action 端点已移除，见 ADR-0024「Genkit 现状」。）

## ADR-004 LLM 模型：暂不定，provider 抽象可插拔
- **背景**：国内平板直连、儿童内容合规、长期成本均需评估。
- **决策**：模型先不绑定；通过 `LLMProvider` 抽象 + `resolve_engine` 接入（内置 `BUILTIN_MODELS` / 家长 `ModelConfig` 表 / 全局 `LLM_PROVIDER`），国产模型走 OpenAI 兼容端点即可。
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
  - **Python 锁定 3.14**（跟随模板）。
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

> **状态（2026-09-08 更新）**：本 ADR 已被 **ADR-0024 / ADR-0025 取代**——AI 传输层不再是 Genkit 单栈，而是自建 SSE 端点 `POST /api/v1/assistant/chat` + AG-UI 事件信封（见 ADR-0024/0025）；Genkit 仅余底层 LLM 引擎（`app/ai/engine.py`）。本 ADR 中仍成立的**意图**已并入下列现行 ADR，原 Genkit 协议细节全部作废：
> - 后端统一代理、安全不降级 → ADR-008
> - 模型可插拔 / 家长自定义 → ADR-004 / ADR-0024
> - 流式安全缓冲校验 → ADR-008 + ADR-0025
> - 流式端点范围 → ADR-0024（`/assistant/chat` 统一入口）

- **背景（要点）**：家用以本地 Ollama 零云成本跑模型；答疑/出题要流式改善体感；前端要能选模型。用户曾参考 CopilotKit 式 GenUI，但终因 Flutter 端无 SDK 且 Genkit 单栈方案已被取代，本 ADR 不再作为实现依据。
- **决策（仅存意图，实现见上述 ADR）**：
  1. 后端统一代理守安全（Ollama/自定义模型由后端调用，前端不直连任何模型）。
  2. 模型注册配置驱动 + 家长自定义（`ModelConfig` 表）；模型选择器仅家长可用。
  3. 流式安全 = 缓冲全量 token + 整体 `check_output` 后放行，儿童端绝不闪现违规片段。
  4. 统一流式端点 `POST /api/v1/assistant/chat`（取代原 `/tutor/ask/stream`、`/tasks/generate/stream`）。
- **备选**：前端直连 Ollama（否决，绕过 ADR-008）；`genui` catalog 真·GenUI（v1 否决，留扩展点）。
- **后果**：本地 Ollama 可零云成本跑模型；模型选择器仅家长可用；安全防线在流式下仍由后端独占（ADR-008）；`ModelConfig` 表与加密存储（Fernet）落地。

## ADR-0016 合并「生成任务」与「预览出题」为统一「出题」流程（先出题 → 手动同步到任务/题库）

> 来源：`/grill-with-docs` 访谈收敛（合并入口 / 先出题后同步 / 题库同步粒度 / 任务落库态 / 题任务关系）。配套实现票据见 `../../wayfinder/tickets/`（待立）。

### 背景
家长端当前有两个并列入口，底层却共用同一套能力：
- **「生成任务」**：流式渲染题卡后立即 `POST /tasks/from-generated` 自动落库为 `draft` 任务（延续 R3）。
- **「预览出题」**：流式渲染题卡但**不落库**，需手动点「保存为任务」才落库。

两者都消费同一套「出题流式预览 → `POST /tasks/from-generated` 落库 draft」能力（ADR-0015 已并入 ADR-0024/0025 的统一端点），仅"流结束后是否自动落库"不同。这造成两套心智——一个静默建草稿、一个不建——与家长的真实心理（"先看 AI 出什么题，再决定拿去派发还是留着好题"）一致性差；且「生成任务」会误产家长并不想要的草稿。

另一处缺口：当前草稿题 `TaskQuestion.question_id = None`（R-Q1=c），**不入题库**，AI 生成的好题在任务用完即弃，无法沉淀为可复用题源；家长期望的"挑好题留存"尚非主流程。

### 决策（六条，经 /grill-with-docs 访谈锁定）
1. **统一入口为单一「出题」按钮**：删除「生成任务」「预览出题」两个并列按钮，合并为「出题」。点击后按规格（学科/年级/知识点/题型/数量、兴趣聚焦、模型）流式产出题卡预览（逐张浮现，经 ADR-0024/0025 统一端点）。
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
- 实现影响：前端入口合并（删两按钮、加「出题」+ 预览多选 + 两动作）、`home_notifier` 状态机微调（预览态新增 `selectedForBank` 集合）；后端新增 `POST /questions/bank/bulk`、复用 `from-generated`；**流式渲染经 ADR-0025 统一 AG-UI 事件信封**（见 ADR-0024/0025）。
- 安全：入题库题仍过 `check_output`（生成时已校验，落库前再确认），不降低 ADR-008 防线。
- 向后兼容：`from-bank`、`from-generated` 端点保留；仅前端入口重排，旧草稿任务数据不受影响。

## ADR-0017 出题推理过程流式通道（合并 thinking+typing 为推理流，参考 AG-UI）

> **状态（2026-09-08 更新）**：本 ADR 的 `REASONING`/`STEP`/`CARD` 信封已被 **ADR-0025 的 AG-UI 事件信封**（`THINKING`/`STEP`/`DATA` 等）广义化取代；传输层统一收敛到 `POST /api/v1/assistant/chat`（ADR-0024/0025）。出题实现现由 `app/ai/subagents/question` 编排，推理流经 AG-UI `THINKING`/`DATA` 事件下发。原信封协议细节（数据结构 / AG-UI 映射表 / 时序图）已作废。

### 背景
R6 分析：原出题流每题仅发 1 个成品题卡 chunk，无中间推理 token 流，体验割裂。用户希望客户端**持续看到 AI 出题推理过程**、消除等待空窗。

### 决策（核心 UX 意图，协议见 ADR-0025）
1. **单一推理通道**：模型「怎么设计这道题」的文字说明（reasoning）与「题卡」（最终结构化题目，数据）分离；前端将推理文字以打字机动画揭示——typing 是呈现方式，非数据类型。
2. **逐题粒度**：每段推理与题卡按题关联，UI 在对应题卡上方展示「AI 怎么想的」。
3. **CARD 到达后默认折叠推理 + 卡片 info icon 展开**：多题并排时内联推理区过长；约定题卡到达后内联区折叠，题卡右上角常驻 info icon，点按以弹层展开「AI 出题思路」（只读、不编辑、不落库）。
4. **推理仅预览态、不落库**：推理是生成期 UX artifact，不入题库/任务表，零 DB 迁移。
5. **混合推理来源**：打底（所有模型）= 结构化调用即拿整段推理，客户端打字机揭示；升级（reasoning 模型，如 DeepSeek-R1 / o-series）= 实时读取思维链 token 边到边推流。
6. **mock 确定性推理**：零 key 也演示流式推理。

### 备选
- 保留 think/typing 两个独立类型（否决，typing 是动画非数据）。
- 每题 2 次调用真·流式（否决为默认，2x 成本；reasoning 模型原生支持时走升级路径）。
- 推理入库为题元数据（否决，避免 DB 迁移与复核面扩大）。

### 后果 / 实现影响
- 体验：出题过程持续可见、等待空窗被推理流填补（reasoning 模型下为真流式）。
- 协议：经 ADR-0025 AG-UI 信封（`THINKING`/`STEP`/`DATA`）下发，向后兼容现行前端。
- 安全：推理文本不落库、不进 `check_output` 复核链（仅成品题卡过 ADR-008 闸门）。
- **实现状态：✅ 已落地**，推理流经 `app/ai/subagents/question` + `assistant_api_client.dart`（AG-UI SSE 客户端）消费 `THINKING`/`DATA` 事件。

## ADR-0018 文档目录结构对齐 ai.md（根目录散落文档归一化）

> 来源：`/grill-with-docs` 访谈收敛（依据 `ai.md` 的 AI-Native 项目结构）。分类映射见下方。

### 背景
项目根目录散落 15 个 `.md`（产品方案 / PRD / spec / T08~T13 任务文档 / 技术架构 / 实施文档 / ADR / 术语表），与 `ai.md` 推荐的 `docs/` 六类结构（product / requirements / ux / architecture / database / decisions）不符；`AGENTS.md` 作为项目协议入口，文档应按类型归类以提升跨 Agent 可读性。同时 `design/`、`wayfinder/`、`docs/agents/` 已有独立定位且被 `AGENTS.md` 大量引用。

### 决策（五条，经访谈锁定）
1. **仅迁移根目录散落文档**，归入 `docs/` 下 4 个有内容的英文分类目录：`product/`（3：产品方案 / PRD / spec）、`requirements/`（5：T08~T13 任务文档）、`architecture/`（4：技术架构_Flutter / 技术架构_后端 / 实施文档_题库复用闭环_前端 / 实施文档_题库复用闭环_后端；原《项目分析_架构规范与业务功能》已于 2026-09-09 并入《技术架构_后端》）、`decisions/`（2：ADR 合集 + 术语表/glossary）。
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
- **Serverless（如云函数跑 FastAPI）**：冷启动 + 长流式 SSE 适配成本高，v1 否决，留作演进。
- **BaaS（Supabase 等）替换自研后端**：与现有 SQLModel/FastAPI 栈重复，否决。
- **前端直连托管模型**：绕过 ADR-008 安全层，否决（须始终经后端 `/api/v1`）。

### 后果
- 具备对外分发能力：HTTPS 后端 + 托管 PG + 密钥外置 + 自动构建部署。
- 引入运维成本（监控/密钥轮换/证书续期）；需先清零 `flutter analyze` 既有错误以满足 CI 门禁。
- 本地 Ollama 零云成本体验保留给 Tier-0 家用；对外版本默认走托管模型（数据出户需告知家长）。
- 与既有决策一致：ADR-003（框架隔离）、ADR-008（安全不降级）、ADR-0024/0025（统一助手端点）在云端不变。

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

## ADR-0022 AI 运行可观测：conversation + message 调试库（已废弃 → 见 ADR-0026）
> **状态：已废弃**。本 ADR 的 `conversation`/`message` 调试库已被 **ADR-0026** 的 `AssistantSession`/`AssistantEvent` 取代（表重命名 + 会话持久化 + 废除 `debug_log`）。原文（背景 / 决策 / 术语 / 后果）已失效，决策理由见 ADR-0026。

## ADR-0023 出题数据流单流收口（删 batch-generate 分叉 + 生成核心收敛 + debug_log 终态化）

> 来源：`/codebase-design` 设计复盘 + 用户「数据流单一、不分叉」诉求。直接执行 **ADR-0016 决策 6**（"两动作均消费同一批已流式题卡，避免二次生成"）。

### 背景
ADR-0016 已确立单流出题：点击出题 → `POST /ai/tasks/generate`（SSE 只读流）→ 前端实时预览 → 家长确认后 `POST /tasks/from-generated` 落库为 `draft`。**有且仅有 `from-generated` 一个业务写库点**。

但后续回归出两条分叉，破坏单流：

1. **`POST /tasks/batch-generate` 老分叉**：该端点走 `_generate_task_questions_for_specs` → `_gen_question`，**自己重新生成题 + 自己写 `TaskQuestion`**，完全绕过 SSE 预览与 `from-generated`。前端生成按钮虽已改用 `from-generated`，该路径仍是"用另一套调用链生成、落另一批题"的僵尸分叉；且被 6 个测试当作建草稿任务入口，掩盖了分叉。
2. **`debug_log` 生成期并行写库**：ADR-0022 的 `debug_log` 在 出题生成流中逐条 `INSERT` `conversation`/`message`。这等于"agent 输出 → DB"出现了**第二个写入点**，与"数据流单一、不分叉"正面冲突（尽管它 fire-and-forget、不阻断主流程，属观察侧）。
3. **两套出题实现漂移**：SSE 用 `flows.generate_questions_stream` + `_mock_question`；非流式/regenerate 经 `provider.generate_question` → `flows.generate_question`。两套 prompt 构建（`_build_stream_prompt` vs `_build_question_prompt`）与装配/安全逻辑各自一份，长期必漂移。

### 决策（四条）
1. **删除 `batch-generate` 分叉（含 `create_single_subject_task` 兼容端点）**：生成算法本就共享（`_gen_question` 内部也调 `provider.generate_question`），分叉只在"自生成 + 自写库"。删除后，业务写库点只剩 `from-generated`，单流闭合。
2. **regenerate 路径接到共享生成核心**：`_gen_question` 重写为对 `app.ai.generate_question` 的薄封装（真实引擎走 `resolve_engine` 解析结果；产出不安全时回退确定性 mock，保证题量完整）。整卷/单题重生成与 SSE 共用同一算法，根除漂移。
3. **`debug_log` 终态化（消息完整后落库）**：`start_agent_run` 仅在内存开缓冲区并返回 `conv_id`；`log_agent_message` 累积到内存；**`finish_agent_run` 一次性把 `conversation` + 全部 `message` 落库**。生成/流式期间零 DB 写，"agent 输出 → DB"不再有并行分叉，仅作为运行结束后的观察侧终端 sink。函数名不变，`flows.py` 调用点零改动。
4. **抽取共享装配/安全 `_assemble_question`**：`generate_question`（一次性）与 `generate_questions_stream`（流式）共用同一"解析 dict → `check_output` → 类型化题"逻辑，mock 分支共用 `_mock_question`。两 adapter（流式 / 一次性）共存于单一核心之上，符合"两 adapter 即真实 seam"原则。

### 备选
- **保留 batch-generate 作薄适配层**：仍并行存在写库路径，与单流诉求冲突 → 否决。
- **debug_log 完全移除**：失去回放能力 → 否决（保留为终态观察侧）。
- **debug_log 仅留日志不写库**：最纯但 `/debug` 回放 UI 失效 → 否决（用户选终态落库，保留回放）。

### 后果
- **数据流单一闭合**：生成（只读 SSE）→ 确认（`from-generated` 唯一写库）→ 状态翻转（`/confirm`），无并行写库分叉。
- **零漂移**：regenerate 与 SSE 共用 `generate_question` 核心；装配/安全逻辑单点。
- **观察侧不污染主链**：debug 落库只在运行结束后发生，生成/流式性能与正确性不受其影响。
- **测试迁移**：6 个依赖 `batch-generate` 建任务的测试改为经 `from-generated`（预置题卡）建草稿；`test_batch_generate_model` 改写为针对 `/regenerate` 走共享核心（选模型 → 经 `resolve_engine` 解析引擎）的回归测试，原意图保留。
- **风险**：删除 `batch-generate` 是公开端点变更；前端已不使用，仅需清理 `models.dart`/`question_bank_remote_data_source.dart` 中残留的 `batch-generate` 注释。

## ADR-0024 Agent Runtime 架构：文件夹化 SubAgent + 统一发现/加载 + 混合意图路由

> 来源：用户需求「前端悬浮 AI 助手 + 后端 agent runtime（定义协议/事件类型、默认文件化加载 subagent、识别意图并路由）」+ grill-with-docs 设计拷问（2026-09-08）。承接 ADR-0021 的 seam，不推翻 `BaseSubAgent` 契约。

### 背景
- ADR-0021 已立 seam：`BaseSubAgent`（ABC，`handle(intent, ctx)`）+ `SubAgentRegistry`（business key → 类）+ 两个活体 subagent（question/tutor）+ 学科 Persona。但 subagent 是**纯 Python 类**，新增业务需改 registry 注册代码；缺「文件化组织 / tool / skill / 意图识别」层。
- 悬浮助手要「一句话办多件事」：出题 / 查任务 / 伴学答疑 / 诊断。调用方不再预先知道 business，需 runtime 从自由文本识别意图并路由。
- 用户明确：subagent 以**统一目录结构**组织（含 tool/skill/shared_tool），由主 agent **统一加载**；且要保留出题/伴学那 ~250 行重逻辑（不强行纯 YAML）。

### 决策（六条）
1. **SubAgent = 统一文件夹**：`app/ai/subagents/<business>/`，固定结构 = `agent.py`（BaseSubAgent 子类或 handler 入口）+ `manifest.yaml`（business 键、name、description、`triggers`、`roles`、依赖的 tools/skills）+ `tools/`（本 subagent 专用可执行函数）+ `skills/`（提示词/方法论资产）。现有扁平文件（question_agent.py / tutor_agent.py）折叠进对应文件夹（迁移）。
2. **AgentRuntime 统一发现/加载**：新增 `app/ai/runtime/`，含 `discover_subagents()`（扫描 `subagents/` 目录 → 读 manifest → 实例化 handler → 注册进 `SubAgentRegistry`）；进程启动（或首请求）惰性加载。新增 subagent = 丢文件夹，零改 registry 代码。
3. **tool / skill / shared_tool 三方语义**：tool=可执行函数（结构化 IO，runtime 工具循环调用，如 `generate_question`/`list_tasks`/`search_knowledge`）；skill=提示词/方法论资产（注入 system prompt，不可执行，如「出题 SOP」）；shared_tool=跨 subagent 复用 tool，抽公共文件 `app/ai/tools/`，各 manifest 声明依赖引用（用户确认：shared_tool 只是代码组织方式，非独立目录概念）。
4. **混合意图路由（IntentRouter）**：manifest 声明 `triggers`（关键词/示例/正则）；runtime 先规则匹配（零延迟零成本，命中即路由），未命中走一次轻量 LLM 分类（把全部 subagent 的 name+description+triggers 作候选喂入，输出 business key + 抽取参数）。分类失败兜底 → 默认 `tutor`（伴学答疑）或安全拒答。
5. **SSE 传输端点**：新增 `POST /api/v1/assistant/chat`（StreamingResponse, `text/event-stream`）。前端发一条 user message（含 role/session_id），后端 `AgentRuntime.run()` 异步产出 AG-UI 事件帧推送（见 ADR-0025）。不复用 genkit_fastapi（其 action 帧格式与自有信封不符，且意图路由+工具循环不在 genkit action 模型内）。
6. **保持 ADR-0021 契约不动**：`BaseSubAgent.handle(intent, ctx)` 仍是执行契约；出题/伴学那 ~250 行逻辑留在各自 `agent.py` 的 handler 内，runtime 只负责发现、路由、工具循环、事件吐出，不吞算法。学科 Persona 退化为 question subagent 的 skill 资产或 runtime 共享注入。

### 备选
- **纯声明式（subagent=YAML，runtime 解释执行，无 Python 类）**：最文件化，但出题 ~250 行（JSON 分块解析/安全闸门/mock 回退/RAG）无法纯声明，安全闸门难嵌 → 否决（用户初选后澄清为「统一目录 + 统一加载」，非纯 YAML）。
- **维持代码类 + 仅补工具目录**：改动最小，但「文件化组织」只是软约定，runtime 无法自动发现 → 否决。
- **复用 genkit flow 做助手**：genkit action 帧与 AG-UI 信封需再适配，意图路由塞进 flow 绕 → 否决。（现状：该备选已落定为「不采用」——2026-09-08 清理中 Genkit flow 与原生 action 端点已从 `app/ai/flows.py` / `main.py` 彻底移除，Genkit 仅余底层 LLM 引擎角色，见下「Genkit 现状」。）

### 后果
- 新增 subagent 零代码注册（丢文件夹 + manifest）。
- 意图识别泛化（自然语言「帮我出几道三年级分数的题」→ 路由 question）。
- 与 ADR-0021 seam 兼容，出题/伴学零重写。
- 成本：混合路由每轮最坏多一次 LLM 分类调用（规则命中则零）。
- 迁移：扁平 `subagents/*.py` 折叠为 `subagents/<business>/` 文件夹；`subject_personas.py` 归位为共享 skill 或 runtime 注入。

### 实现备注（2026-09-08 落地）
- **端点收敛已完成（用户指令「所有 AI 功能统一经 `/api/v1/assistant/chat`」）**：
  - 废除的生成类端点：`POST /api/v1/ai/tutor/ask`（原 Genkit flow）、`POST /api/v1/ai/tasks/generate`（原 Genkit flow）、`POST /api/v1/tutor/ask`（legacy subagent 路径）。三者的 Genkit flow 实现已从 `app/ai/flows.py` 删除；`app/features/ai/router.py` 现仅保留家长回放端点（见下），`app/features/tutor/router.py` 不再挂任何 AI 生成路由（仅 `/logs` `/quota` `/usage` 治理接口）；前端相关调用已全部改走统一端点。
  - 统一入口实现于 `app/features/assistant/router.py`：`POST /api/v1/assistant/chat`（SSE），`AgentRuntime` 负责发现 / 路由 / 事件吐出 / 会话落库（复用 `Conversation`/`Message`，ADR-0026）。
- **Genkit 现状（2026-09-08 清理后）**：Genkit 已从「编排 / 传输层」**完全退役**——`genkit_fastapi` 已移除，项目不再暴露任何 Genkit 原生 action 端点；意图路由与工具循环由 `AgentRuntime` 自管，不再依赖 genkit 的 action 模型。Genkit **仅**作为底层 LLM 引擎，经 `app/ai/engine.py`（`engine.genkit.generate[_stream]`）被各 SubAgent 间接调用；业务代码只依赖 `LLMProvider` 抽象，不直接 `import genkit`（唯一边界为 `app/ai/engine.py`）。ADR-0024 决策 5「不复用 genkit_fastapi」与备选「复用 genkit flow」均已落定为「不采用」。
- **保留的端点（非 AI 生成，属治理 / 可观测，不并入生成流）**：
  - `GET /api/v1/ai/debug/conversations[/id]`：家长回放自家 Agent 运行（读同一张 `Conversation`/`Message` 表）。
  - `GET/PUT /api/v1/tutor/quota`、`GET /api/v1/tutor/logs`、`GET /api/v1/tutor/usage`：T10 家长管控 + ADR-008 家长可见日志（与 `AssistantSession` 职责正交，ADR-0026 决策 5）。
- **实现偏差**：manifest 用 `manifest.py`（`MANIFEST` dict）替代原决策的 `manifest.yaml`——项目未引入 PyYAML 依赖，folder discovery 直接读 `manifest.py` 的 `MANIFEST`，零新增依赖。

## ADR-0025 助手交互协议：AG-UI 式统一事件信封

> 来源：同上。扩展 ADR-0017 的出题专用信封为通用聊天协议。

### 背景
- ADR-0017 定义出题流式信封 `STEP`/`REASONING`/`CARD`（AG-UI `type` 多态约定）。悬浮助手是通用对话，还需 user/assistant 文本、thinking、工具调用可视化、错误、结束。复用 `type` 判别字段，避免前端维护两套解析。

### 决策（四条）
1. **统一信封**：`{"eventType": <EventType>, ...payload}`。事件类型集合 = `USER_MESSAGE`(回显用户输入) / `ASSISTANT_MESSAGE`(文本 delta) / `THINKING`(推理 delta，ADR-0017 `REASONING` 的通用化) / `TOOL_CALL`(工具名+参数) / `TOOL_RESULT`(工具输出) / `STEP`(进度锚点，复用 ADR-0017) / `DATA`(已收集到的结构化数据如题卡，复用 ADR-0017) / `ERROR` / `DONE`。
2. `STEP`/`DATA`/`THINKING` 与 ADR-0017 语义/字段一致，前端已有分发器可复用扩展。
3. 前端单一 `fromChunk(eventType, payload)` 分发器；SSE 帧 `data: {eventType, ...}`（与现有 `message`/`result` 传输帧兼容，信封在 payload 内）。
4. **安全**：输出经 `check_output` 通过后才发 `ASSISTANT_MESSAGE`/`DATA`；违规 → `ERROR`(或安全兜底文本) + `DONE`，不向娃娃暴露拒绝原因（ADR-008）。

### 备选
- **双协议并存**（聊天简单 SSE + 出题 ADR-0017 信封）：前端两套解析，对话内出题混流难 → 否决。
- **纯文本流 + 末帧产物**：丢 thinking/工具可视化 → 否决。

### 后果
- 前端一个分发器覆盖所有 AI 交互（答疑/出题/助手）。
- 与 ADR-0017 兼容，题卡浮现逻辑复用。

## ADR-0026 双端角色感知派发 + 助手会话持久化（废除 debug_log，supersede ADR-0022）

> 来源：用户决策「悬浮助手双端通用 + 角色感知」「保留会话并废除 debug_log，统一按助手会话 debug」。supersede ADR-0022。

### 背景
- ADR-008：娃娃端永远拿不到标准答案；双层防护。悬浮助手双端显示，必须按角色过滤可见 subagent（孩子端不暴露出题/查任务答案，只暴露伴学答疑）。
- ADR-0022 建 `conversation`/`message` 调试库 + `debug_log` 模块（genkit flow 内调用）；ADR-0023 已将其「终态化」（`finish_agent_run` 一次性落库）。用户现要求废除 `debug_log`，统一以「助手会话」做 debug——一次会话既是对话记录，也是家长可见调试轨迹。

### 决策（五条）
1. **角色感知派发**：IntentRouter 按当前 `role`（parent/child）过滤 subagent 清单——child 仅可见 `tutor`（伴学答疑），parent 可见全部（question/tutor/查询任务/诊断等）。manifest 加 `roles: [parent, child]` 字段作过滤器。
2. **AssistantSession 持久化**：新建 `AssistantSession`（id, role, parent_id, child_id, model, status, created_at）+ `AssistantEvent`（session_id, role, type/step, content, payload, input_safe, output_safe, blocked, latency_ms, usage, created_at）。聊天跨会话保留（家长可回看）。
3. **废除 `debug_log`**：移除 `app/ai/debug_log.py` 及 `start_agent_run`/`log_agent_message`/`finish_agent_run` 全部调用点；调试记录改由 `AssistantSession`/`AssistantEvent` 承担——一次助手运行 = 一条 session + 其 events（含 input/retrieval/reasoning/generation/tool_call/output/error 步骤，沿用 ADR-0022 的 role/step 口径）。ADR-0022 的 `conversation`/`message` 表重命名为 `AssistantSession`/`AssistantEvent`（复用其 schema，不新建平行表）。
4. **多轮上下文**：session 落库后后端直接按 `session_id` 读历史维持多轮；前端只需带 `session_id`，无需全量回传 history。
5. **TutorLog 不动**：答疑合规计数（每日上限 + 家长日志页）仍走 `TutorLog`（已上线接 UI）；`AssistantSession` 仅做统一对话/调试记录，二者职责正交（同 ADR-0022 边界）。

### 备选
- **纯无状态（不保留会话）**：「再出两道类似的」丢上下文 → 否决。
- **保留 debug_log 并行**：与「统一会话 debug」诉求冲突、双份存储 → 否决（用户明确废除）。
- **助手会话取代 TutorLog**：需改写合规页 + 计数，范围大 → 否决（保持正交）。

### 后果
- 双端安全：孩子端不暴露出题/答案（ADR-008 强化）。
- 单一调试面：助手运行回放 = 读 `AssistantSession` events，废除 `debug_log` 模块。
- 跨会话对话：家长可回看助手历史。
- 迁移：删 `debug_log` 调用点（flows.py 等）；新建/重命名 `AssistantSession`/`AssistantEvent` 表（SQLModel metadata + `run_migrations` `CREATE TABLE IF NOT EXISTS` 幂等）。

## ADR-0027 后端包结构：Feature-First（模块化单体）

> 来源：用户决策「将该项目 backend 改成 feature first 架构」。目标——每个业务能力自包含（路由 + schema + 仓储 + 服务同目录），消除分层巨型文件跨目录跳跃。

### 背景
- 原 backend 是「分层 + 半 feature」混合体：`app/api/routes/` 路由已按 feature 命名（auth/children/tasks/review/mastery/tutor/questions/models/assistant/ai/health），但 `app/models.py`（659 行 ORM + Pydantic 混杂）、`app/crud.py`（1274 行集中仓储）、`app/domain/`（10 个业务文件）是**集中单体**。`api/` 与 `domain/` 两层割裂，改一个能力要在 3+ 目录间跳。
- `crud.py` 自身 `import app.domain.mastery / app.domain.review_scheduler`，`app/ai` 依赖 `app/domain`（provider/safety/retriever/quota + grader/tutor）——`domain/` 实质是**跨 feature 共享内核**，不能无脑拆散。
- children 是 `User` 行（`role="child"`），无独立 `Child` 表；`Task→Child→User` 靠外键跨 feature 互引。

### 决策（五条）
1. **Feature 包自包含**：每个业务能力拥有 `app/features/<name>/`（`router.py` + `schemas.py` + `repository.py` + `service.py` 按需）。11 个 feature：`health / auth / children / questions / model_management / tasks / review / mastery / tutor / ai / assistant`。
2. **ORM 表集中**：SQLModel 表统一在 `app/db/models/`（按表拆文件：`user/task/question/model_config/progress/tutor/conversation` + `base`）。模块化单体标准做法——避免 feature 间循环导入（跨 feature 外键只指向 `app.db.models`，不指向具体 feature）。
3. **共享内核保留**：`app/domain/`（provider/safety/retriever/quota 等 AI 基础设施，被 4+ feature 与 `app/ai` 共用）与 `app/core/`（config/security/errors/db/deps）不拆；`app/ai`（Genkit 仅作底层 LLM 引擎，经 `engine.genkit` 调用）+ `app/ai/subagents`（ADR-0024/0021 编排）是跨 feature 的 AI runtime，留在 `app/ai` 不在 feature 包内。
4. **依赖收敛**：所有 feature router 从 `app.core.deps` 取 `CurrentUser / CurrentParent / CurrentChild / CallerDep / SessionDep`；原 `app.api.deps` 删除，升格为 `app/core/deps`。`app/api/main.py` 仅 `include_router` 各 feature router，不再有 `app/api/routes/`。
5. **删除集中文件**：删 `app/models.py`、`app/crud.py`；其 ORM 落 `app/db/models`、Pydantic schema 落各 feature `schemas.py`、仓储落各 feature `repository.py`。

### 备选
- **ORM 按 feature 拆表**：否决——`Task→Child→User` 跨 feature 外键会逼出延迟导入/字符串外键，循环依赖风险高。
- **domain 完全拆进 feature service**：部分采纳——feature 专属逻辑随 feature 走；但被多 feature 共用的 AI 内核（provider/safety/retriever/quota）留 `app/domain`，否则要造重复定义或破坏 `app/ai`。
- **一次性全量 vs 增量试点**：执行采用「保留共享内核的前提下逐 feature 包落地」——既非全量重写也非单点试点，靠 `pytest` 全程绿作安全网。

### 后果
- feature 自包含：新增/修改某能力主要动一个目录；两个巨型文件（models.py/crud.py）消除。
- 跨 feature 唯一真理源收敛为 `app/db/models`（ORM）+ `app/domain`（共享业务/AI 内核）+ `app/core`（横切）。
- 迁移落点：11 个 feature 包；tests + `app/ai` 的 import 全部 repoint 到 `app.db.models` / `app.features.*`；`pytest` 120 passed / 3 skipped。
- 日志归属澄清：`TutorLog`/`TutorUsage` 落库**只由悬浮助手端点**（`app/features/assistant/router.py` 的 `event_stream` finally，带真实 `grade`）负责，SubAgent/`tutor_ask` flow 不重复落——避免双写导致 `count_tutor_today` 偏多（每日上限误判）。
- 风险：feature 间复用（如 `review` 调 `tasks` 的 `create_answer_record`、`assistant` 调 `tutor`/`ai` repository）需显式跨包 import，依赖方向要单向（子 feature 不反向依赖父 feature 的 router）。

## ADR-0028 出题改为单调用真流式（推理增量 + 题卡）

> 来源：用户反馈「点生成任务时客户端没有实时渲染 LLM 返回的 stream text，只渲染了题目卡片」。

### 背景
- 出题链路此前是**假流式**：`QuestionSubAgent.run()` 每题 `await provider.generate_question()`（底层 `genkit.generate` + `output_schema` 结构化输出，一次性等完整 JSON），全部生成完才 `yield data_event(...)`。整题生成期间**零帧**下发，前端只能干等。
- 全项目 `thinking()` 只在 `runtime.py` 的路由阶段 yield 两次，`step()` 与 `_step_label()` 定义了却零调用 → 前端 `liveReasoning` 恒空、`liveIndex` 恒 -1，`_PreviewGenerating` 的渲染条件 `liveIndex >= 0` 永不成立。
- 传输层是清白的：`DioNetworkService.streamPost` 用 `ResponseType.stream` + `Options.compose` 拼 baseUrl，SSE 确实逐帧到达。
- 历史包袱：ADR-0017 设想的 `generate_questions_stream`（STEP/REASONING/CARD 增量）从未接进 subagent，作为零调用死代码被清理；清理消除了「两种实现」假象，但真流式能力从未落地。

### 决策（四条）
1. **单调用流式出题**：新增 `app/ai/generation.py:generate_question_stream`，一次模型调用内先用 `<reasoning>…</reasoning>` 写思路、再输出 JSON 题卡。成本较「推理 + 出题」两阶段减半，且共用 `_build_question_clause` 保证口径一致（ADR-0023 单一生成核心）。
2. **引擎层语义 schema，不新增传输协议**：`app/domain/provider.py` 定义 `ReasoningDelta` / `QuestionCard` / `QuestionStreamEvent`（`AsyncIterator[QuestionStreamEvent]`）。SSE 侧**继续复用 ADR-0025 的 AG-UI 信封**——SubAgent 负责把引擎事件翻译成 `STEP / THINKING / DATA` 帧。加新语义只需加一个类型，不动 SSE 协议。
3. **原生思维链优先**：Genkit 0.10 Python 的 chunk 是 `content: list[Part]`，`ReasoningPart(reasoning=…)` 与 `TextPart(text=…)` 由类型区分；`genkit_openai` 已把 OpenAI 兼容的 `reasoning_content`（DeepSeek-R1 / o-series）映射为 `ReasoningPart`。所以**不需要**解析文本猜「这段是不是思考」——原生思维链直接下发，普通模型走 `<reasoning>` 标签兜底，不写标签时 `{` 之前的文本也当推理。
4. **前端修死条件**：`home_notifier` 在 `STEP` 帧到达时把 `liveIndex` 置为下一题序号（并清空上一题推理）、`DATA` 帧到达时归 -1（推理随卡落到题卡 info icon），`TaskGenPreview` 首次真正带上 `liveIndex`。

### 备选
- **新增一层「固定 SSE 协议」封装（chunk_type 思路）**：否决——Genkit 的 `chunk_type` / `ctx.send_chunk` 是 **Genkit flow over genkit-fastapi** 的机制，而本项目 Genkit 已从编排/传输层退役（ADR-0024），传输协议由 AG-UI 信封承担。再套一层只会多一个协议要维护。
- **两阶段（先流式出思路，再结构化出题）**：否决——两次模型调用、成本翻倍，且需要把第一阶段推理回灌第二阶段（`_build_question_prompt.reasoning_hint` 就是为此留的口子，已不再需要）。
- **最小修（只发 STEP 进度，不出推理）**：否决——`ReasoningTypewriterWidget` 与 ADR-0017 的推理面板已存在，只发进度等于让它们继续当摆设。

### 后果
- 出题首帧到达时间从「整题生成完（10s+）」降到亚秒级；实测真实 deepseek：472 个非路由 THINKING 增量帧、2 个 STEP、2 张题卡。
- 题卡 `DATA.result` 新增 `reasoning` 字段（此前为 `GeneratedQuestion` 直出，无此字段）→ 题卡右上角 info icon 可展开「AI 出题思路」。
- 路由帧污染修复：`runtime.py` 首帧 thinking 补 `extra={"routing": True}`，前端同时按 `extra.business` / `extra.routing` 过滤，避免「正在理解你的需求…」被拼进出题思路。
- `LLMProvider` 新增非抽象 `generate_question_stream`，默认退化为「一次性生成 → 单张题卡」，使不支持流式的实现也能接上同一条调用链；`GenkitProvider` 覆写为真流式，无引擎时空迭代（0 题，无 mock 兜底）。
- 单测：`tests/ai/test_generate_question_stream.py`（9 例，含 `<reasoning>` 标签 / 原生 ReasoningPart / 不写标签 / 安全闸门 / 任意切分点鲁棒性）、`tests/ai/test_question_subagent_stream.py`（4 例，断言 STEP→THINKING→DATA 顺序与帧数）。

## ADR-0029 出题解析与转换层四管分层（Decode → Demux → Parse → Translate）

> 来源：ADR-0028 落地「真流式」后，下一步「解析器只判定、不猜测；语义层与传输层彻底分离」的重构。

### 背景
ADR-0028 让出题真流式落地（472 个非路由 THINKING 帧、2 个 STEP、2 张题卡），但落地时发现 `generate_question_stream` 一个 async generator 同时干了 4 件事，且严重耦合 prompt 协议：
- 构造 prompt（隐含约定模型按 `<reasoning>…</reasoning>` 输出）
- 解码 genkit chunk
- 跑字符串状态机（6 个可变局部变量）
- 解析 JSON、过安全闸门
- 翻译成 AG-UI 帧（`isinstance` 内联 dispatch）

更严重的两条隐患：
- **协议分散两端**：prompt 在 `_build_stream_prompt`（142 行）、解析器在 200 行外的手写状态机（379 行）。改 prompt 忘了改解析 → 静默失效。
- **解析层为 prompt 兜底**：3 条猜测分支（模型不写标签 → `{` 之前的当推理；标签未闭合 → 中途切 JSON；尾部可能截断的 `<` → `buf.rfind("<", emitted)` 留一手）全部写在了「解码层」补偿「模型不听话」。该问题是 prompt 规范的锅，不是协议层的责任。

### 决策（四层管道，每层一个职责）
1. **Decode（第 1 层，`app/ai/segment.py`）**：genkit chunk → `Segment(kind, text)`。全项目**唯一** `import genkit` 的地方。换 LLM 框架只改这一个文件。
2. **Demux（第 2 层）**：根据 `Segment.kind` 分流。`REASONING` 通道（原生思维链）**直通**，不进状态机；`TEXT` 通道交给 Parse。这层只几行，分流逻辑与 Decode 合一。
3. **Parse（第 3 层，`app/ai/parsers/question.py`）**：文本流 → `QuestionStreamEvent`。契约（`QuestionSchema` 即 `output_schema`）与解析器（`SchemaQuestionParser`）在**同一个文件**，改 schema 必看见解析器，杜绝漂移。解析器是**同步 push 状态机**（`feed(seg)` / `finish(output)`），无 async、无引擎依赖，可直接用字符串喂入单测；新增解析策略（增量 JSON 抽取等）实现同一 `QuestionStreamParser` Protocol 即可替换。
4. **Translate（第 4 层，`app/ai/runtime/translate.py`）**：语义事件 → AG-UI 帧。SubAgent 不再内联 `isinstance` 分发，只写 `async for frame in translate_stream(stream): yield frame`。此处同时做**思维链帧聚合**（每 16 字符攒批），帧数降一个量级而打字机观感不变。

### 失败显式化
解析失败 / 安全闸门未过 / 模型无结构化产出 → 统一发 `QuestionFailed(reason=…)` 显式事件，由 Translate 层转 `status=error` 的 STEP 帧，前端可见「这题为什么没出来」。**解析层不做任何宽容兜底**——容错是 prompt 规范的职责，不是协议层的。

### 安全闸门扩展
`assemble_question` 拆成两层判定：题面（`stem/answer/explanation`）未过闸 → 整题作废（返回 `QuestionFailed`）；推理单独过闸 → 不安全时**只丢推理**，题卡照发（推理是可选的透明度信息，不该因为它的措辞而丢掉一道好题）。此前所有 THINKING 帧裸发到孩子屏幕，**绕过任何安全校验**——这是 ADR-0028 之前最该修的洞。

### 备选
- **保留 `<reasoning>` 标签流 + 2 状态机解析器**：被 ADR-0029 否决。状态多、未闭合分支、尾部 `<` hack 都对应 prompt 规范，靠解析层 hack 是治标。要换格式就换个干净的协议。
- **注册表式 Translate**：被否决。事件类型 5 个以内，`match` 够用，抽象多一层反而模糊。
- **解析层做宽容兜底**：被否决。从历史 ADR-0023 教训——容错放在解析层会导致行为漂移、测试变重；显式失败事件让上层（runtime/UI）能区分「是该重试还是该给提示」。

### 后果
- `flows.py` 内的 prompt 协议与解析器在同一个文件（`parsers/question.py`），改 schema 必看见解析器；不再有「改了 prompt 忘了改解析」的漂移空间。
- 解析器是同步 push 状态机，单测从「起假引擎喂完整流」降级到「字符串 `feed(s[:i]) for i in range(len(s))`」级别的单元测试——任意切分点鲁棒性可以参数化验证（见 `test_reasoning_deltas_robust_to_any_chunk_boundary[1, 3, 17, 1000]`）。
- 帧聚合：实测 deepseek-v4-flash 端到端从 472 个 THINKING 帧降到 53 个（每 16 字符攒批），帧数-1 量级、观感不变。
- `QuestionCard.reasoning` 字段稳定下发（也走安全闸门，不安全则被丢弃），前端 `parent_task_form_view` 的题卡 info icon 始终能拿到推理。
- `LLMProvider.generate_question_stream` 默认退化为「一次性生成 → 单张题卡」（无推理增量），使不支持流式的实现也能接上同一调用链；`GenkitProvider` 覆写为真流式，无引擎时空迭代（0 题，无 mock 兜底）。

### 在线格式选「原生思维链 + `output_schema`」的代价
线上模型 `deepseek-v4-flash`（`config.py:46`）不在 `engine.py:_REASONING_HINTS` 列出的支持列表里，因此**实测中所有推理帧都来自 TEXT 通道经 `output_schema` 的 `reasoning` 字段一次性到达**，原生思维链通道（`ReasoningPart`）在本环境是死代码。换模型到 `deepseek-reasoner / qwq / o-series` 后，原生通道会自动启用——`genkit_openai/models/model.py:339` 已把 OpenAI 兼容的 `reasoning_content` 映射为 `ReasoningPart`，这一侧无需任何代码改动。

### 验证
- `ruff check app/ai app/domain app/features/tasks` 全过
- `tests/ai` 38 例全过（含流式原语、解析器鲁棒性、SubAgent 帧类型统计、Translate 帧聚合与未知类型报错、落库路径回归）
- e2e：路由 THINKING 2 帧、非路由 THINKING 53 帧、STEP 2 帧、DATA 2 帧、首个推理帧 1.99s（重构前整题生成完才下发 10s+）

## ADR-0030 助手运行时抽象收口：引擎单一解析链 / SubAgent 零配置发现 / Skills 真消费 / 删除 LLM 分类插槽

> 来源：ADR-0024（统一入口）落地后的一次架构体检，修掉「声明了但没接线」的四条抽象裂缝。

### 背景
ADR-0024 / 0025 / 0026 把 AI 入口收敛到 `POST /api/v1/assistant/chat` 后，运行时骨架（Runtime 发现 → 路由 → SubAgent → Domain）已经成立，但体检发现四处「看起来有、实际没有」的抽象：

1. **引擎注入是死链（功能缺陷）**：`AgentRuntime.run` 用 `resolve_engine(model, parent_id, session)` 解析出引擎，经 `build_subagent(engine=)` 存进 `BaseSubAgent.self.engine`，但全仓**零处消费**——`GenkitProvider` 内部一律 `resolve_engine()` 无参。后果：家长 `ModelConfig` 自定义模型与前端 `model` 字段在助手链路上**完全不生效**，永远走全局 `LLM_PROVIDER`。
2. **「新增 SubAgent = 丢一个文件夹」不成立**：`discover_subagent_manifests()` 只发现 `manifest.py`，agent 类仍要在 `registry.py` 手工登记一行；`intent_router._PRIORITY` 与 `_QUESTION_HINTS` / `_TASK_HINTS` 还硬编码了 `tasks` / `question` / `tutor` 三个业务名。新增一个业务要改三处。
3. **`manifest.skills` 是死元数据**：`question_sop.md` / `tutor_sop.md` 已写好，但没有任何代码读取它们注入 prompt；声明的 SOP 一条都没进模型上下文。
4. **LLM 分类插槽空着**：`classify(llm_classify=...)` 从未被传参，所谓「混合路由」实际只有规则 + 启发式两级。

### 决策
1. **引擎解析单一链**：引擎只在 `AgentRuntime` 里解析一次，经 `build_provider(engine=...)` 注入 `GenkitProvider`；`GenkitProvider` 持有引擎，无显式引擎时才回退 `resolve_engine()`。**删除 `BaseSubAgent.engine` 与 `build_subagent(engine=)` 这两个死参数**——SubAgent 一律经 `provider` 取引擎，不再有第二条并行通道。
2. **发现即注册**：`discover_subagent_manifests()` 扫到 `manifest.py` 的同时，用 `inspect` 从同目录 `agent.py` 取出 `BaseSubAgent` 子类写入清单（`agent_cls`）；`registry.py` 的手工登记表删除。`SubAgentManifest` 增两个可选字段：`priority: int`（路由优先级，默认 0）与 `hints: list[str]`（启发式兜底词）；`intent_router` 删掉硬编码的 `_PRIORITY` 与业务提示词表，改为按 `priority` 降序做通用匹配，priority 最低者作兜底。
3. **Skills 真消费**：发现阶段读取 `skills/*.md` 全文存入清单，Runtime 装配时经 `SubAgentContext.skills` 下传；出题 SubAgent 把 SOP 拼入 `persona_hint`、伴学拼入 `context`。声明了但文件缺失 → 发现时打印告警（此前静默）。`manifest.tools` 保留为**声明式清单**，字段注释明确「tool 事件由 `agent._tool()` 产出，当前无运行时调度器」——不假装存在调度器。
4. **删除 LLM 分类插槽**：移除 `classify` 的 `llm_classify` 参数与相关分支。理由：业务只有三个、儿童产品要求路由确定性、规则 + 启发式已覆盖现有语料，而引入 LLM 分类会让每条请求多一次完整模型往返（首字节延迟翻倍）去换一个三选一。保留该插槽的代价（一个永远为 `None` 的参数 + 一段永不执行的分支）大于收益。

### 备选
- **引擎双通道保留（SubAgent 直连 engine）**：否决。两条解析链必然漂移，且 `resolve_engine` 的入参（`parent_id` / `session` / `model`）只有 Runtime 拿得全。
- **保留 registry 手工登记 + 发现只管 manifest**：否决。这正是「声明与实现两处真相」的源头，新增业务漏登记会静默回退到 `tutor`。
- **实现真正的 tool 调度器**：否决。三个 SubAgent 的「工具」就是各自执行体本身，抽调度器是为抽象而抽象；等出现第二个复用同一 tool 的业务再说。
- **LLM 分类默认关闭、用配置开关接线**：否决。默认关闭的开关等于死代码，还额外引入配置项与测试矩阵。真需要时在 `classify` 加回一个 callable 参数即可，成本约 5 行。

### 后果
- 家长 `ModelConfig` 与前端 `model` 在 `/assistant/chat` 上真正生效；无显式引擎时行为不变（回退全局 `LLM_PROVIDER`）。
- 新增业务只需在 `app/ai/subagents/<business>/` 放 `manifest.py` + `agent.py`，`priority` / `hints` 写在 manifest 里，零处登记。
- SOP 文本进入模型上下文，出题 / 伴学的口径由 `skills/*.md` 与 prompt 共同决定，不再各写各的。
- `intent_router` 不再知道任何具体业务名，可独立单测（喂 manifest 即可）。

### 验证
- `uv run ruff check .` 全过
- `uv run pytest` 全过，新增：引擎透传断言、发现即注册断言、skills 注入断言
- 手工：家长自定义模型 id 经 `model` 字段传入后，出题 / 伴学应命中该模型

## ADR-0031 Agent 抽象层抽取为通用框架 `agent_core`（ADR-0003 升级）

> 来源：用户需求——把 `app/ai` 从「教育业务专属管线」升级为「业务无关的通用 agent 框架」，作为内部协议规范接入各业务子项目。配套分析见 `docs/architecture/AI_Agent分层抽象对比分析.md`。

### 背景
1. 当前 `backend/app/ai` 是一条教育业务专属的 agent 管线：协议信封、文件夹发现注册、manifest 驱动路由、统一 SSE 流形这**四件骨架已通用且可复用**，但整层被教育业务焊死、「工具调用」是装饰性的（无真实 tool loop）。
2. 需求方要求把 agent 层提升为**业务无关的抽象层**（协议 + subagent 注册 + subagent 路由 + 工具调用 + 统一事件流），作为内部通用协议规范，接入各个业务子项目；每个子项目实现自己的 subagent 处理自身业务。
3. 逐层分析确认三处硬伤：① 真实 tool loop 缺失；② `app/ai` 重度反向依赖 `app.domain`/`app.features`/`app.db`/`app.core`，无法被其它工程复用；③ `LLMProvider` 泄漏教育语义（`generate_question_stream(subject, grade, knowledge_point, qtype, difficulty, interests, focus_interest, rag_context, persona_hint, history)`）。
4. ADR-0003 已定「框架隔离 + 自封领域接口」，本 ADR 是对它的**升级**：把"领域接口"从"教育后端内的一层"升级为"独立可分发框架"。

### 决策
1. **抽为独立可安装 Python 包 `agent_core`**（内部 PyPI 发布；各业务工程 `pip install agent_core` 后实现自己的 subagent 接入），不再嵌在 `app/ai` 内。
2. **`agent_core` 只定义抽象 seam，零业务依赖**：
   - `LLMProvider`：收窄到消息级 `stream(system, prompt, schema, history) -> AsyncIterator[TextDelta | StructuredDone]`；业务 prompt 组装由 subagent 负责，provider 只认消息。
   - `Retriever`：可选知识库检索（`retrieve(query) -> list[Chunk]`）。
   - `Safety`：输入/输出安全闸门（抽象；具体实现由业务注入，如儿童双层防护）。
   - `Tool`：`ToolSpec(name, description, schema, handler)` + 运行时执行器。
3. **真实 tool loop**：`AgentRuntime` 在 subagent 声明 `tools` 时，把 tool schema 随首轮请求发给模型；收到 `tool_call` → 解析并执行注册的 `handler` → 回灌 `tool_result` → 循环直到 `done`。**subagent 自行决定是否声明 tools（opt-in）**；教育现有出题/答疑可保持一次性生成，不强依赖 loop。
4. **协议信封 `AssistantEvent` 冻结为 `agent_core` 拥有**（AG-UI 式 11 种 eventType）。`DATA.type`、`blocked` 等教育特定字段改为 `extra` 扩展，core 不再认识业务词。
5. **翻译/解析层下沉**：原 `translate.py`/`parsers/*` 的教育语义移到各 subagent 自身模块；`agent_core` 领域无关，只负责信封 ↔ 传输（SSE）的通用转换。
6. **路由暴露可插拔 `classify` 钩子**：规则 + 启发式为默认实现（沿用 ADR-0030 确定性），弱意图领域可传入 LLM classifier（`classify(llm_classify=...)`，约 5 行接线）。
7. **一步到位大重写**：内核与所有 subagent 一次性迁出（非增量），结构最干净。

### 备选
- 增量抽取（先抽内核、端点与 subagent 暂留教育仓适配）：风险低，但双源真相窗口长、过渡期两套并存。否决（用户选大重写）。
- 本仓内共享子包 / 独立子仓 + monorepo：隔离不如独立包彻底。否决（用户选独立可安装包）。
- 强制所有 subagent 走 loop：框架最纯粹但破坏现有一次性生成流。否决（用户选 opt-in）。

### 后果
- 正向：任何业务工程可 `pip install agent_core` 实现 subagent 接入；框架与具体 LLM/业务彻底解耦；真实 tool loop 到位，"工具调用"不再是谎言；`LLMProvider` 收窄后加业务不改 provider、换 provider 不懂教育。
- 负向/风险：
  - 大重写中途教育管线不可运行、回归面大。配套：**抽前冻结教育端接口契约**（SSE 帧结构、业务 subagent 的 `handle/run` 签名），以契约测试守护；抽完一次性切换并全量回归 `uv run pytest` + 真机验证。
  - `agent_core` 需建独立测试与发布流程（内部 PyPI / 语义化版本 / CHANGELOG），治理成本上升。
  - 真实 tool loop 引入多轮模型往返，需内置超时/重试/熔断（沿用儿童产品确定性前提，tool 执行保持同步可预期，异常转 `ERROR` 帧）。

### 目标包结构（agent_core）
```
agent_core/
  protocol.py     # AssistantEvent 信封 + 便捷构造器
  registry.py     # 文件夹发现 + 业务键→类 查询
  router.py       # 规则+启发式 默认路由 + 可插拔 classify
  runtime.py      # AgentRuntime：发现/路由/tool loop/统一事件流
  tools.py        # ToolSpec + 执行器
  seams.py        # LLMProvider / Retriever / Safety 抽象基类
  subagent.py     # BaseSubAgent + SubAgentContext（去掉教育字段）
```
业务工程侧：
```
my_biz_backend/
  agent/
    question/manifest.py + agent.py + tools/ + skills/
  provider_impl.py   # 实现 agent_core.seams.LLMProvider（消息级）
```

### 执行计划（大重写）
1. 建 `agent_core` 包骨架 + 抽象 seam + `AssistantEvent` 信封（从 `app/ai/runtime/protocol.py` 原样搬）。
2. 迁 `registry`/`router`/`runtime`：去掉对 `app.domain`/`app.features`/`app.db` 的 import，改为依赖注入抽象 seam。
3. 实现真实 tool loop（runtime 内），`BaseSubAgent` 暴露 `tools: list[ToolSpec]`（默认空 = 不走 loop）。
4. 收窄 `LLMProvider` 到消息级；把 `app/ai/generation.py` 的 prompt 组装整体搬进对应 subagent。
5. 把 `translate.py`/`parsers/*` 教育语义下沉到教育仓的 subagent 模块；`agent_core` 只留通用信封↔SSE。
6. 教育仓改为 `pip install agent_core`，把现有 `question/tutor/tasks` 三个 subagent 作为"首个接入方"重写适配；端点层（鉴权/配额/落库）保留在教育仓，调用 `agent_core.AgentRuntime`。
7. 发布 `agent_core` 到内部 PyPI；补契约测试 + 全量回归。

### 关联
- ADR-0003（框架隔离 + 自封领域接口，本 ADR 升级之）
- ADR-0024 / 0025 / 0026（统一入口 / 事件信封 / 角色感知）
- ADR-0030（发现即注册 / 去硬编码 / 删 LLM 分类插槽）

## ADR-0032 `agent_core` 分层边界与命名收敛（ports-and-adapters 落位）

> 来源：用户在 ADR-0031 落地后追问四个边界问题（Q1 subagents 位置 / Q2 `ai` 下通用方法能否上提 /
> Q3 `generation.py`·`parsers/question.py` 业务耦合 / Q4 是否把 genkit 集成进 `agent_core`），
> 并追问文件组织与命名的业内共识。配套详文：`docs/architecture/agent_core_结构与命名规范.md`。

### 背景
1. ADR-0031 抽出独立包 `agent_core`（内核 + 协议 + 端口 + 编排）后，`app/ai` 的职责边界在代码里**未被明文表达**：
   哪些属内核、哪些属引擎适配、哪些属业务集成，只能靠读码推断。
2. 四个待澄清点：
   - **Q1**：`subagents` 是应用层业务 agent，是否该与 `app` 同层（提到 `backend/`）？
   - **Q2**：`app/ai` 下的通用方法（`segment` / `debug_log` / `model_catalog` / `engine`）能否上提 `agent_core`？
   - **Q3**：`app/ai/generation.py` 与 `app/ai/parsers/question.py` 与业务模型深度耦合，能否抽象？
   - **Q4**：把 genkit 集成进 `agent_core`，是否就能把 `ai` 的通用功能上提、让抽象层更简单清晰、基座更稳定？
3. 另需统一命名口径：`seams`、`contrib` 等词对使用者不够直观，需对齐业内共识（六边形架构）。
4. 查证事实（推翻若干初判）：
   - `app/ai/segment.py` **不 import genkit**（duck-typing 读 chunk 字段），已引擎无关，可直接上提；
   - `app/ai/generation.py` 不只服务出题——其 `GradeSchema` 同时被**批改**（`domain/genkit_provider.py`）消费；
   - `app/ai/debug_log.py` 的写入函数**全后端零调用方**（其 docstring 引用的 `flows.py` 已删），是死代码。

### 决策
1. **名称口径对齐六边形架构（ports-and-adapters）**：
   - `agent_core/seams.py` → **`agent_core/ports.py`**（「端口」；与 `adapters` 成对；"seam" 是测试词汇，非框架词汇）。
   - 第一方引擎集成命名为 **`agent_core/adapters/`**（六边形「适配器」），弃用早前的 `contrib` 提法（`contrib` 只表达"附带"，不表达角色）。
   - 保留（已符共识）：`protocol` / `runtime` / `router` / `registry` / `tools` / `errors` / `subagents/`。
2. **Q1（落点）**：`subagents` 是**本应用专属**业务 agent（重度 `import app.domain/features/core`），
   **不提为 `backend/subagents/`**——那会误发"与 `agent_core` 一般可复用"的信号，且仍反向依赖 `app.*`，纯改名不省事。
   正确粒度为 `app/ai/subagents/`（仍在 `app` 内、与 `ai` 同级）。命名**保持 `subagents`**：它们 subclass
   `agent_core.subagent.BaseSubAgent`，是内核的 subagent，不是独立 agent。
3. **Q2（不上提）**：`app/ai` 在 ADR-0031 后已是**教育集成层**，无真正可上提的通用件：
   - `segment.py` 已引擎无关 → **上提**到 `agent_core/adapters/genkit.py`（它服务适配器，属适配层）；
   - `debug_log.py` 是 DB 实现（绑 `app.core.db` + 本应用 schema）→ **删除**（见 5.）；
   - `model_catalog.py` 是产品配置（支持哪些厂商）→ 留 app；
   - `engine.py` 最 app 耦合（读 ModelConfig 表、解密密钥）→ 留 app，只把 SDK 构造委托适配器。
   **原则：`agent_core` 只放端口抽象，实现留 app；不搬文件。**
4. **Q3（按归属拆分，非整搬）**：`generation.py` / `parsers/question.py` 拆为：
   - 出题专属 → `app/ai/subagents/question/{pipeline.py, parsers.py}`；
   - `GradeSchema` → `app/domain/grader.py`（批改契约，非出题）；
   - 跨业务共享件 → `app/domain/prompts.py`（`EDU_SYSTEM_PROMPT`）+ `app/domain/structured.py`（`schema_field`/`coerce_dict`）；
   - 废弃 engine 版 `_generate_question(_stream)`，出题统一走 `LLMProvider`；删除 `app/ai/generation.py` 与 `app/ai/parsers/`。
5. **Q4（否决 genkit 进内核）**：genkit **不进 `agent_core`**。理由：
   - 它解锁不了"通用功能上提"（真正通用的 `segment.py` 本就引擎无关）；
   - 会让引擎易变性搬进基座——切引擎 = 改基座，违背"基座稳定"；
   - 会强制所有外部方案吃 genkit，与"外部拓展稳定"方向相反。
   正确机制：**内核保持引擎无关，genkit 作为挂在端口上的适配器**（`agent_core/adapters/genkit.py`，
   genkit SDK 的**唯一落点**，工厂内延迟导入 → 未装 genkit 仍可导入内核与适配器）。
6. **删除死代码 `app/ai/debug_log.py`**（原计划仅是改名 `observability.py`）：
   三个写入函数零调用方、职责已由 `app.features.assistant` 承担（ADR-0026 废除 `debug_log`）；
   对死代码改名无收益，故删除。`app/ai/__init__.py` docstring 同步清理。
7. **固化两条分层不变量**（须持续守护）：
   - `agent_core` 内**零 `app.*` 依赖**；
   - 全后端 `import genkit` **仅出现在 `agent_core/adapters/genkit.py` 的工厂函数体内**（延迟导入）。
8. **打包关系定为「`agent_core` 随 app wheel 一起打包」**（不单独发布）：
   `backend/pyproject.toml` 的 `[tool.hatch.build.targets.wheel]` → `packages = ["app", "agent_core"]`；
   同时**删除 `backend/agent_core/pyproject.toml`**（一个产物只留一份构建定义，避免"看起来是独立可发布包"的误导）。
   **本决策取代 ADR-0031 执行计划第 7 步的「发布 `agent_core` 到内部 PyPI」**——内核与集成层同发一个 wheel。
9. **清理 `app/features/ai/repository.py` 的写入侧死代码**：删除 `create_conversation` / `add_message` / `finish_conversation`
   （唯一调用方是已删的 `debug_log.py`），保留只读的 `list_conversations` / `get_conversation_messages`（`/ai/debug/conversations` 在用）。

### 落地结果（五阶段，全部完成）
1. `seams.py` → `ports.py`（纯改名，13 处 import；含 `__init__` 再导出同步）。
2. 建 `agent_core/adapters/genkit.py`：迁入 `segment.py` 的 `Segment`/`SegmentKind`/`decode_stream`，
   并把 `GenkitProvider.stream` 的纯 genkit 分支提为 `GenkitLLMProvider`；`app/domain/genkit_provider.py` 改为委托（教育扩展 `tutor`/`grade_open` 留 app）。
3. 适配器新增工厂 `build_genkit_engine`（构造 `Genkit(plugins=[...])` + provider 前缀归一 + 实例缓存）；
   `app/ai/engine.py` 瘦身为纯配置解析（删 `from genkit import ...` 三行），`EngineResolution` 形状不变。
4. Q3 拆分落地（见决策 4）；`app/ai` 顶层不再含任何教育出题内容。
5. 删除 `debug_log.py`（见决策 6）。
6. `agent_core` 随 app wheel 打包（见决策 8）+ 清理 `features/ai/repository.py` 写入侧死代码（见决策 9）。

### 备选（已否决）
- **genkit 集成进 `agent_core`**：把引擎易变性烤进基座、强制外部方案吃 genkit。否决（见决策 5）。
- **`subagents` 提到 `backend/` 层**：误导性 + 无实际解耦收益。否决。
- **`contrib` 命名**：语义弱于 `adapters`。否决。
- **`debug_log.py` 改名保命**：对零调用方死代码无收益。否决（改为删除）。
- **Q3 整文件搬入 `subagents`**：会把批改契约（`GradeSchema`）错带到出题侧。否决（按归属拆）。

### 后果
- 正向：三层职责（内核 / 适配器 / 集成）命名与目录一一对应，外部工程师可只凭目录读懂依赖方向；
  切引擎仍只动适配器一处、内核纹丝不动；外部方案可自由实现 `LLMProvider` 接入；死代码清零。
- 负向/风险：
  - 拆分面较大（涉 `generation.py` 删除、`parsers` 迁移、多个调用方与测试改签名）；配套：分五阶段小步落地，
    每阶段 `ruff check .` + 全量 `pytest` 把关（最终 **166 passed / 2 skipped**）。
  - 两类不变量是"靠纪律"而非"靠机制"守护，须补 AST/结构级断言测试防漂移（当前已覆盖 engine 无 genkit import、
    适配器仅函数内 import）。

### 验证
- `uv run ruff check .` 全过；`uv run pytest` → **166 passed / 2 skipped / 0 failed**。
- 结构不变量（grep/AST 实证）：`agent_core` 零 `app.*`；全后端 `import genkit` 仅适配器工厂内 3 行；
  无 `app.ai.generation` / `app.ai.parsers` / `app.ai.segment` / `app.ai.debug_log` 残留引用。
- 打包实证：`uv build --wheel` → `app-0.1.0-py3-none-any.whl` 内含 `agent_core/` **11 个文件**（`app/` 97 个），
  **未误带 `pyproject.toml`**；隔离 venv `pip install --no-deps <wheel>` 后
  `import agent_core` / `agent_core.ports` / `agent_core.adapters.genkit` 均成功，且 `--no-deps` 下未引入
  genkit 等第三方（印证内核零依赖 + 适配器延迟导入的不变量在打包产物中依然成立）。

### 遗留（另议，非阻断）
- 若日后需将 `agent_core` **独立分发**（供其它业务子项目 `pip install`），需另建独立仓 / pyproject + 版本策略；
  本 ADR 决定不单独发布（见决策 8），**以本 ADR 为准**（取代 ADR-0031 执行计划第 7 步）。
- （前端，属 ADR-0031 遗留）`frontend/lib/features/assistant/domain/assistant_event.dart` 加 `extra` 扩展位（协议已留 `extra`）——未动。

### 关联
- ADR-0003（框架隔离 + 自封领域接口）/ ADR-0031（抽 `agent_core`，本 ADR 收敛其边界与命名）
- ADR-0021 / 0024 / 0025 / 0026 / 0027 / 0029 / 0030（SubAgent 契约 / 统一入口 / 信封 / 会话 / Feature-First / 解析分层 / 收口）

