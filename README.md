# 娃娃日常学习应用 · 最小可跑原型

家长给娃娃布置 AI 生成的日常练习，娃娃在平板上做题、自动批改、打卡、错题复习与 AI 伴学答疑。
技术栈：**Flutter 平板 App（Riverpod + Dio + Cupertino + shadcn_ui，tablet-first）+ Python/FastAPI/SQLModel 后端（单 wheel 含 `agent_core` 内核）+ SQLite（默认）/ PostgreSQL**。
AI 模型在客户端「模型管理」里手动添加（家长 `ModelConfig`，api_key 经 Fernet 加密落库），**无内置模型、无本地 mock 兜底**：未添加模型时出题/答疑/批改返回「未配置模型」提示。

---

## 架构

```
Flutter 平板 App（娃娃端 / 家长端，Riverpod + Dio + Cupertino + shadcn_ui，tablet-first）
        │  HTTP/JSON（/api/v1）+ SSE 流式（/api/v1/assistant/chat）
        ▼
FastAPI 后端（单 wheel 含两个包）
  ├─ agent_core/   框架无关 agent 内核（零 app 依赖、零三方依赖；仅 adapters/genkit.py 接 genkit）
  │     └─ ports / runtime / subagent / protocol / registry / router / tools：AgentRuntime + AG-UI 事件信封 + tool loop
  └─ app/         FastAPI 集成层
        ├─ api/main.py       聚合 features/* router（auth/children/tasks/review/mastery/tutor/questions/model_management/ai/assistant/health）
        ├─ core/             config / db / security / guard(归属·可见性单一真相源) / errors / deps
        ├─ domain/           grader · review_scheduler(间隔重复 0..4) · mastery · safety · retriever · provider
        ├─ features/         每业务含 router/service/repository/schemas
        ├─ ai/subagents/     query(查询) / question(出题) / tutor(伴学) + subject_personas(学科人格)
        └─ db/models/        User · Task · Question · TaskQuestion · Conversation/Message · …
        │
        ▼
SQLite（本地零依赖，默认） / PostgreSQL（Docker / 云）
```

**所有 AI 能力经单一 SSE 入口** `POST /api/v1/assistant/chat`（流式 AG-UI 事件帧：USER_MESSAGE / THINKING / TOOL_CALL / TOOL_RESULT / DATA / ASSISTANT_MESSAGE / DONE）。出题 / 伴学 / 查询都走此入口；旧的 `/ai/tutor/ask`、`/ai/tasks/generate` 已废弃并收敛到此。分层不变量（内核不反向依赖 app / fastapi、genkit 唯一落点、归属判定只经 `core.guard`）由 `tests/ai/test_layering_invariants.py` 静态扫描守住（见 `docs/agents/architecture.md`）。

核心原则：
- **不在 LangChain 之上重复封装 provider**：`LLMProvider` 是 `agent_core/ports.py` 里的抽象端口，业务只认抽象、不绑框架；模型只在「模型管理」里添加，引擎解析收敛到 `resolve_engine`（读家长 `ModelConfig`），无内置目录、无本地 `LLM_PROVIDER` 等旁路 env。
- **模型必须经「模型管理」配置**：出题/答疑/批改都需真实引擎；未配置时返回「未配置模型」提示，不再有离线 `mock` 兜底。

---

## 目录

```
.
├── backend/                 # Python 后端（uv 管理，Python >= 3.14，单 wheel 含 app + agent_core）
│   ├── app/
│   │   ├── main.py          # FastAPI 入口（app.main:app）：CORS / 统一错误 / 请求日志
│   │   ├── api/main.py      # 聚合所有 features/* router（挂在 /api/v1）
│   │   ├── core/            # config(env) / db / security / guard / errors / deps / crypto / async_bridge
│   │   ├── domain/          # grader · review_scheduler · mastery · safety · retriever · provider · prompts
│   │   ├── features/        # 按业务切分，每业务含 router/service/repository/schemas
│   │   │   ├── auth children tasks review mastery tutor questions model_management ai assistant health
│   │   ├── ai/              # engine.py(resolve_engine) / model_catalog.py / subagents/{query,question,tutor}
│   │   └── db/models/       # User · Task · Question · TaskQuestion · Conversation · Message · …
│   ├── agent_core/          # 框架无关 agent 内核（零 app/三方依赖）
│   │   └── ports runtime subagent protocol registry router tools adapters(genkit)
│   ├── tests/               # pytest：分层不变量 / SubAgent 契约 / domain 单测（含真实模型 smoke）
│   ├── scripts/             # copyright_compliance_check.py（版权合规门禁）
│   ├── pyproject.toml       # 依赖 + ruff/pytest 配置（app 与 agent_core 同 wheel）
│   ├── uv.lock
│   └── Dockerfile
├── frontend/                # Flutter 平板 App（Riverpod + Dio + Cupertino + shadcn_ui，tablet-first）
│   ├── lib/
│   │   ├── main/            # 入口 + AdaptiveShell（三档断点响应式壳，AppUserMode 作用域）
│   │   ├── configs/app_config.dart   # API Base URL（--dart-define=API_BASE 注入）
│   │   ├── features/        # auth / children / home / practice / review / tutor / assistant / profile
│   │   ├── services/        # auth_session（token 持久化）
│   │   ├── shared/          # data / domain / exceptions / presentation / theme(令牌) / utils / widgets
│   │   └── dev/             # theme_preview.dart（设计系统自检）
│   ├── analysis_options.yaml # flutter_lints + 设计系统硬约束（禁硬编码颜色/裸 Text）
│   └── pubspec.yaml
├── .env.example             # 后端本地配置模板（复制为 .env）
├── docker-compose.yml       # PostgreSQL + backend 一键起
├── docs/agents/             # 面向 AI 代理的架构/规范/命令文档（AGENTS.md 钻取）
└── README.md
```

---

## 快速开始

### 方式 A：本地直接跑（无需 Docker，推荐先验证）

后端用 `uv` 管理依赖（Python >= 3.14，`uv.lock` 已锁定）。本地默认 SQLite，零额外依赖；但 AI 出题/答疑/批改需先在「模型管理」配置模型（见下方「配置模型」），否则相关接口返回「未配置模型」提示。

```bash
# 1) 复制配置模板到仓库根目录（后端会优先读取根目录的 .env）
cp .env.example .env

# 2) 安装依赖并启动（首次 uv sync 会自动创建虚拟环境）
cd backend
uv sync
uv run fastapi dev            # 开发模式，热重载，地址 http://localhost:8000
# 或：uv run uvicorn app.main:app --reload
```

> 不装 uv 也可：`python3.14 -m venv .venv && source .venv/bin/activate && pip install -e . && fastapi dev`。

健康检查：`curl http://localhost:8000/api/v1/health`

#### 平板 / 真机联调（重要）

本地 `fastapi dev` / `uvicorn --reload` **默认只绑定 `127.0.0.1`**。当 App 跑在真机、平板或模拟器上时，`127.0.0.1` 指向的是**设备自身**而非你的电脑，会导致登录/请求报「请求失败 (-1)」且服务端无任何日志（请求根本没进来）。

联调时后端必须放开监听地址，并用电脑**局域网 IP**（不是 `127.0.0.1` / `localhost`）：

```bash
cd backend
# 放开监听 + 局域网可访问；热重载仍可用
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# 前端（另开终端），API_BASE 填电脑局域网 IP：
cd frontend
flutter run --dart-define=API_BASE=http://<电脑局域网IP>:8000
```

> 查电脑局域网 IP：`ifconfig | grep "inet "`（忽略 127.0.0.1）。Docker 方式（`docker compose up`）已默认 `--host 0.0.0.0`，无需此步。
> 若仍连不上：先 `curl http://<电脑局域网IP>:8000/api/v1/health` 确认后端可达；检查防火墙是否放行 8000。

### 方式 B：Docker 一键（PostgreSQL）

```bash
cp .env.example backend/.env    # 按需改 SECRET_KEY / MODEL_APIKEY_SECRET（见「配置模型」）
docker compose up --build     # 启动 PostgreSQL + backend，后端暴露 8000
```

---

## 开发流程（命令速查）

日常开发、测试、运行的命令总表。规范与细节见 `docs/agents/development.md`。

### 后端（目录 `backend/`，Python ≥ 3.14，`uv` 管理）

| 动作 | 命令 |
|------|------|
| 安装依赖 | `cd backend && uv sync` |
| 本地起服（仅本机） | `uv run fastapi dev` 或 `uv run uvicorn app.main:app --reload` |
| 局域网联调（真机/平板必用） | `uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload` |
| Lint（零 error 门禁） | `uv run ruff check .` |
| 测试 | `uv run pytest -q` |
| 真实模型 smoke | `RUN_LLM_SMOKE=1 SMOKE_MODEL_NAME=llama3 SMOKE_MODEL_API_KEY=ollama uv run pytest tests/domain/test_llm_smoke.py -m smoke -v` |
| 健康检查 | `curl http://localhost:8000/api/v1/health` |
| 版权合规自检（门禁逻辑） | `python scripts/copyright_compliance_check.py --self-test` |

### 前端（目录 `frontend/`，Flutter ≥ 3.5）

| 动作 | 命令 |
|------|------|
| 安装依赖 | `cd frontend && flutter pub get` |
| 起服（联调） | `flutter run --dart-define=API_BASE=http://<电脑局域网IP>:8000` |
| 静态分析（零 issue 门禁） | `flutter analyze` |
| 测试 | `flutter test --reporter=github` |
| 设计系统自检（本地） | 运行 `lib/dev/theme_preview.dart` 页面核对令牌一致性 |

### 一键容器（仓库根）

`docker compose up --build`（PostgreSQL + backend，后端默认 `--host 0.0.0.0`）

### CI（`.github/workflows/`）

- `ci.yml`：frontend（`flutter analyze` + `flutter test`）→ backend（`ruff check` + `pytest`）。推 `main` / 开 PR 触发，任意步失败整轮红。
- `compliance.yml`：后端 `pytest` + 版权合规门禁（ADR-0019 / ADR-0020）。

> 联调铁律：后端 `--host 0.0.0.0` + 前端 `API_BASE` 填**电脑局域网 IP**（非 `127.0.0.1`，否则真机报「请求失败 (-1)」且服务端无日志）。详见上方「平板 / 真机联调」。

---

## 配置模型（「模型管理」）

AI 出题 / 伴学 / 批改都需真实引擎，且**无内置模型、无本地 `mock` 兜底**——未添加模型时相关接口返回「未配置模型」提示。只有一条路径：

**家长在「模型管理」中添加**（ADR-0039）
家长登录后在「模型管理」页面点「添加模型」，选服务商（DeepSeek / OpenAI / Ollama / …）自动带出 base_url 与模型名建议，**填写 API Key（必填）**，保存后可「设为默认」。api_key 经 Fernet 加密落 `ModelConfig` 表；未显式指定模型时回落该默认模型。

> `provider ∈ {ollama, openai_compat}`；`base_url` 留空时 ollama 走 `OLLAMA_BASE_URL`（默认 `http://localhost:11434`）。
> **先固定 `MODEL_APIKEY_SECRET` 再加模型**：该值决定加密密钥，改它会让已存 API Key 全部解不开（事故见 `docs/adr/0038`）。加错顺序时，回到「模型管理」重填一次 Key 即可恢复。
> 真实连通 smoke 测试（默认跳过，需真实可用的模型服务）：
> `RUN_LLM_SMOKE=1 SMOKE_MODEL_NAME=llama3 SMOKE_MODEL_API_KEY=ollama uv run pytest tests/domain/test_llm_smoke.py -m smoke -v`

---

## API 速览

所有路径带 `/api/v1` 前缀。交互式文档：http://localhost:8000/docs

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/v1/auth/register` | 家长注册（返回 token） |
| POST | `/api/v1/auth/login` | 登录 |
| GET  | `/api/v1/auth/me` | 当前用户 |
| POST | `/api/v1/children` | 家长添加娃娃账号 |
| GET  | `/api/v1/children` | 家长列出娃娃 |
| POST | `/api/v1/tasks/generate` | 家长生成任务+题目（SSE 流式，调 LLM） |
| GET  | `/api/v1/tasks/today` | 娃娃查看今日任务 |
| POST | `/api/v1/tasks/{task_id}/answer` | 娃娃提交单题 → 自动批改 |
| POST | `/api/v1/tasks/{task_id}/checkin` | 完成任务打卡 |
| GET  | `/api/v1/tasks/wrong-questions` | 娃娃错题列表 |
| GET  | `/api/v1/tasks/children/{child_id}/progress` | 家长看进度（正确率/连续打卡） |
| GET  | `/api/v1/tasks/children/{child_id}/mastery` | 掌握度看板 |
| GET  | `/api/v1/review/due` | 到期待复习题（遗忘曲线） |
| POST | `/api/v1/review/answer` | 复习作答 |
| POST | `/api/v1/assistant/chat` | **AI 统一入口（SSE）**：出题 / 伴学 / 查询，按角色+触发词路由 |
| GET  | `/api/v1/health` | 健康检查 |

> 伴学答疑、出题、查询统一走 `POST /api/v1/assistant/chat`（流式）。旧的 `/api/v1/tutor/ask`、`/api/v1/tutor/quota` 不存在（tutor router 仅 `GET /logs`）；套餐/额度在 assistant 会话内按 `caller` 角色与配额判定。

---

## 前端 Flutter

1. 安装 Flutter SDK（Dart >= 3.5）；用平板或模拟器。
2. 配置后端地址：默认 `http://127.0.0.1:8000`（见 [app_config.dart](file:///Users/yunqi/Documents/develop/openedu/frontend/lib/configs/app_config.dart)）。

   ⚠️ **真机/平板/模拟器联调时**，必须同时满足两点，否则会报「请求失败 (-1)」且服务端无日志：
   - 后端用 `--host 0.0.0.0` 启动（见上方「平板 / 真机联调」）；
   - `API_BASE` 填**电脑局域网 IP**（不是 `127.0.0.1`，那是设备自己）。

```bash
cd frontend
flutter pub get
flutter run --dart-define=API_BASE=http://192.168.1.50:8000
# 或直接改 lib/configs/app_config.dart 里的 AppConfig.apiBase
```

家长端可生成任务、看娃娃列表/进度/掌握度；娃娃端做题看解析、打卡、复习错题、AI 答疑。

---

## 闭环演示步骤

1. 后端先在「模型管理」里添加模型并设为默认（见「配置模型」）。
2. 家长注册 → 登录（拿 token）。
3. 家长添加娃娃（child 账号，记好返回的 ID）。
4. 家长 `POST /api/v1/tasks/generate`（填 child_id、学科、知识点、题型、数量，SSE 流式返回题目）。
5. 娃娃登录 → 首页看到今日任务 → 逐题作答 → 看解析 → 打卡。
6. 家长 `GET /api/v1/tasks/children/{id}/progress` 查看正确率与连续打卡天数。

---

## 路线图

- **一期（已实现）**：刷题练习 + 每日打卡 + AI 出题（经「模型管理」配置真实引擎）。
- **二期（已实现）**：错题本 + 遗忘曲线复习（review 模块 + scheduler）+ 掌握度看板。
- **三期（已实现）**：AI 伴学答疑（内容安全防护 + 每日额度）+ 教材知识库检索（retriever）。
- **长期（上线准备期）**：教材版权合规（上线前必须解决，合规门禁见 `compliance.yml`、决策见 `docs/adr/`）、云部署生产化（见 `docs/adr/`）、跨设备同步。

---

## 合规提醒

教材（人教版等）受版权保护。**自用/开发阶段可用；凡是做成对外分发产品，上线前必须取得版权授权或改用公版/自编内容。**
