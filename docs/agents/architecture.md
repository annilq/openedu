# 架构详解（Architecture）

> 本文件是 `AGENTS.md` 中「架构」条的钻取文档。改动任何跨层代码前先读本节。
> 领域术语以仓库根 `CONTEXT.md` 为准；已落地决策见 `docs/adr/`。
> 本文件依据实际代码（`backend/app`、`backend/agent_core`、`frontend/lib`）核对，非 README 旧图。

## 0. 一句话分层

```
Flutter 平板 App（家长 / 儿童双模式）
   │  HTTP/JSON（/api/v1）+ SSE 流式（/api/v1/assistant/chat）
   ▼
FastAPI 后端（单 wheel 含两个包）
   ├─ agent_core/   框架无关 agent 内核（零 app 依赖、零三方依赖，仅 adapters/ 接 genkit）
   └─ app/          FastAPI 集成层（features / domain / core / db / ai）
   │
   ▼
SQLite（默认零依赖）/ PostgreSQL（Docker / 云）
```

后端打包约定见 `backend/pyproject.toml` 的 `[tool.hatch.build.targets.wheel]`：`app` 与 `agent_core` 同发一个 wheel，不单独发布（ADR-0032）。

---

## 1. 后端：`agent_core`（agent 内核）

定位：与业务、与 FastAPI、与具体 LLM SDK 解耦的纯 Python 内核。**不变量（被 CI 静态扫描守住）：内核除 `adapters/` 外不得 import `app.*`、不得 import 任何三方库。**

| 文件 | 职责 | 关键不变量 |
|------|------|-----------|
| `ports.py` | 抽象端口：`LLMProvider` / `Retriever` / `Safety` / `RuntimeDeps` | 业务只认抽象，可独立发包 |
| `runtime.py` | `AgentRuntime`：agent loop、角色可见性（唯一真相源）、消息折叠 | `runtime.py:63-91` 角色判定 |
| `subagent.py` | `run_with_tools`：真实 tool loop，`max_turns` 默认 3 防死循环，`ToolUnsupportedError` 硬失败 | `subagent.py:116-213` |
| `protocol.py` | `AssistantEvent`（AG-UI 式事件信封）+ `to_sse()` | 前端按 `eventType` 分发 |
| `tools.py` | 工具抽象与注册基类 | — |
| `registry.py` | `discover_subagent_manifests`：扫目录自动注册 SubAgent（**新增 agent = 丢一个文件夹**） | 发现即注册，免手工登记 |
| `router.py` | 路由：规则优先 + 启发式兜底 + 可选 LLM 分类 | 路由确定性是儿童产品硬要求 |
| `runtime_singleton.py` | `AgentRuntime` 单例装配点 | — |
| `adapters/genkit.py` | **全工程唯一** `import genkit` 落点，且全部函数体内延迟导入 | 未装 genkit 也能 import 内核 |

分层不变量由 `backend/tests/ai/test_layering_invariants.py` 以 **AST 静态扫描**固化为 9 条测试（内核无 app 依赖、无三方依赖、genkit 唯一落点、service 不反向依赖 router/fastapi、query 工具只经 service 取数、归属判定只经 `core.guard`）。越界在 CI 直接红。

---

## 2. 后端：`app`（FastAPI 集成层）

### 2.1 包布局

```
app/
├── main.py              # FastAPI 入口（app.main:app）；CORS、统一错误体、请求访问日志中间件
├── api/main.py          # 聚合所有 feature router（见下）
├── core/               # config(env) / db / security / guard / errors / deps / crypto / async_bridge / ai_plumbing
├── domain/             # grader · review_scheduler · mastery · safety · retriever · provider · prompts · structured · subjects · tutor · genkit_provider
├── features/           # 按业务切分：每个含 router/service/repository/schemas
├── ai/                 # engine.py（resolve_engine）/ model_catalog.py / subagents/{query,question,tutor}/
└── db/models/          # user · task · question · task_question · conversation · message · progress · tutor · model_config
```

`app/api/main.py` 注册的 feature router（顺序即挂载顺序）：`auth → children → tasks → review → mastery → tutor → questions → model_management → ai → assistant → health`。全部挂在 `settings.API_V1_STR`（即 `/api/v1`）前缀下。

### 2.2 `core/guard.py` — 归属与可见性单一真相源

亲子家庭隔离、娃娃端可见性（仅 `assigned`/`done` 态任务）的判定**只经 `core.guard`**。任何取数代码不得自行判断归属——这是分层不变量测试强制的一条。

### 2.3 `domain/` — 纯业务逻辑

- `review_scheduler.py`：间隔重复阶段制 0..4，间隔 1/2/4/7/15 天，末位阶段答对即毕业（ADR-0005）。
- `grader.py`：作答自动批改。
- `safety.py`：伴学内容安全闸门。
- `retriever.py` / `provider.py`：RAG 与 LLM provider 抽象（端口在 `agent_core`）。

### 2.4 `ai/subagents/` — 业务 SubAgent

业务维度 = SubAgent（出题 `question` / 伴学 `tutor` / 查询 `query`），学科维度 = Persona，在调用方正交组合（ADR-0021）。每个 SubAgent 一个文件夹，含 `agent.py` + `manifest.py`；`subject_personas.py` 归一化学科人格统一注入。

- `question/`：`pipeline.py`（流式出题，内核只消费不持有 RAG/Persona）+ `parsers.py` + `translate.py`（THINKING 攒批降帧）。
- `query/`：唯一真正跑 `run_with_tools` 的多步取数 agent（`agent.py:48-51`），工具按 `tools/` 分层注册。
- `tutor/`：走 `TutorService` 单调用，非 tool loop（ADR-0033 opt-in）。

### 2.5 AI 能力收敛点

**所有 AI 功能经单一 SSE 入口 `POST /api/v1/assistant/chat`**（`app/features/assistant/router.py:29`，ADR-0024/0025/0026/0031）。该端点只做 HTTP 适配（鉴权 + 包 `StreamingResponse` + `X-Accel-Buffering: no`），全部编排在 `assistant/service.py`。

事件帧（AG-UI 式，前端按 `eventType` 分发）：`USER_MESSAGE / THINKING / TOOL_CALL / TOOL_RESULT / DATA / ASSISTANT_MESSAGE / DONE`。

> ⚠️ 废弃端点：`/ai/tutor/ask`、`/ai/tasks/generate`、`/tutor/ask` 已收敛到 assistant 入口，README 旧 API 表中的这些流式项以 assistant 为准。

---

## 3. 前端：Flutter（tablet-first）

```
frontend/lib/
├── main/            # 入口 + AdaptiveShell（三档断点响应式壳，AppUserMode 作用域）
├── configs/         # AppConfig：apiBase 经 --dart-define=API_BASE 注入，默认 127.0.0.1:8000
├── features/        # assistant / authentication / children / home / model_management / practice / profile / review / tutor（Riverpod）
├── services/        # auth_session（token 持久化）
├── shared/          # data / domain / exceptions / presentation / theme / utils / widgets
└── dev/             # theme_preview.dart（设计系统自检，CI 外本地跑）
```

- **分层与依赖方向（ADR-0037）**：`main/ → features/* → shared/*` 单向。`shared/` 是跨 feature 基础层，**不得 import `features/`**；feature 之间不得横向互引，唯一豁免是 `features/home/presentation/`（展示层组合根，装配各 feature 页面）。feature 与后端 `app/features/*` 一一对应。`App*` 前缀保留给 `shared/widgets/` 的通用设计系统组件——组件一旦订阅某 feature 的 provider 就必须落回该 feature（如 `model_management` 的 `ModelSelector`）。

- **状态/网络**：Riverpod + Dio。`AppConfig.apiBaseUrl` = `API_BASE + /api/v1`。
- **双模式**：`AppUserMode`（家长/儿童）持久化于 `storage_service`，在根 `AdaptiveShell` 作用域生效（ADR-0002）。Child Mode 整体放大一档字号，文案第一人称切换，消费学科 accent 令牌。
- **设计系统单一事实源**：`AppColors` / `AppSpacing` / `AppText._typeScale` 推导所有颜色、间距、字号、转场时长；组件禁止硬编码 `Colors.*` 与魔法十六进制（`analysis_options.yaml` 已声明硬约束，待 `custom_lint` 启用静态强制）。
- **AI 消费**：`features/assistant/` 按 SSE 事件帧即时 `setState`，`shared/widgets/stream_reasoning_panel.dart` 打字机揭示推理文本（ADR-0017；也是「生成任务闪现」缺陷的约束来源）。工具查到的数据以**类型化卡片**呈现（ADR-0042）：`DATA.data.type` 是种类判别键、`data.result` 是结构化载荷，由 `presentation/widgets/assistant_cards.dart` 分派渲染（题目卡 / 列表卡 / 指标卡 / 降级卡），卡片落在气泡外侧。

---

## 4. 数据模型要点（领域事实源 `CONTEXT.md`）

- **题库即 `Question` 表**：题目跨 `Task` 复用，按 `parent_id` 做家庭隔离（ADR-0001）。
- **派发快照 `TaskQuestion`**：题目派发到任务时落快照，作答/错题归集用 `TaskQuestion.id` + 源 `Question.id`；娃娃端 `answer` 恒为 null 防作弊。
- **任务生命周期**：`draft → ready`（家长确认成卷）→ `assigned`（绑 child_id）→ `done`。
- **会话持久化**：`Conversation` / `Message` 表（DB-backed 多用户），替代 CLI 式 JSONL 分支树（产品形态取舍，见评审文档 §5）。

---

## 5. 历史评审结论（已闭环）

早期 `agent_core` 架构评审提出的偏差均已落地，结论不代表当前状态，仅作追溯：

- 被引用的 ADR（0003/0021/0031/0032/0033 等）现已全部落地于 `docs/adr/`，无引用悬空。
- 缺 context compaction → 由 manifest SOP 注入 + 摘要注入覆盖。
- 缺后台扩展钩子 → ADR-0035 补齐 `Hooks` seam。
- 前端 SSE 逐帧渲染 → ADR-0048 会话历史形态约束。

当前架构以 §1–4 为准。

---

## 6. 关键文件索引（改对应层先读这些）

- 端口与事件内核：`backend/agent_core/{ports,runtime,subagent,protocol,tools,registry,router}.py`
- 唯一 genkit 落点：`backend/agent_core/adapters/genkit.py`
- 引擎与模型目录：`backend/app/ai/engine.py`、`backend/app/ai/model_catalog.py`
- SubAgent：`backend/app/ai/subagents/{query,question,tutor}/{agent,manifest}.py`
- SSE 入口与编排：`backend/app/features/assistant/{router,service}.py`
- 归属/可见性：`backend/app/core/guard.py`
- 分层不变量测试：后端 `backend/tests/ai/test_layering_invariants.py`；前端 `frontend/test/feature_boundaries_test.dart`
- 设计令牌：`frontend/lib/shared/theme/app_theme.dart`；双模式壳：`frontend/lib/main/adaptive_shell.dart`
