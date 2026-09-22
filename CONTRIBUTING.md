# 开发 / 部署指南

本文件回答「我怎么把它跑起来、怎么改」。产品功能说明见 [README.md](README.md)；面向编码代理的架构与规范见 [AGENTS.md](AGENTS.md) 与 `docs/agents/`。

技术栈：**Flutter 平板 App（Riverpod + Dio + Cupertino + shadcn_ui，tablet-first）+ Python/FastAPI/SQLModel 后端（单 wheel 含 `agent_core` 内核）+ SQLite（默认）/ PostgreSQL**。

---

## 架构

```
Flutter 平板 App（娃娃端 / 家长端，Riverpod + Dio + Cupertino + shadcn_ui，tablet-first）
        │  HTTP/JSON（/api/v1）+ SSE 流式（/api/v1/assistant/chat）
        ▼
FastAPI 后端（单 wheel 含两个包）
  ├─ agent_core/   框架无关 agent 内核（零 app 依赖、零三方依赖；仅 adapters/genkit.py 接 genkit）
  │     └─ ports / runtime / subagent / protocol / registry / router / tools
  └─ app/         FastAPI 集成层
        ├─ api/main.py       聚合 features/* router
        ├─ core/             config / db / security / guard(归属·可见性单一真相源) / errors / deps
        ├─ domain/           grader · review_scheduler(间隔重复 0..4) · mastery · safety · retriever
        ├─ features/         每业务含 router/service/repository/schemas
        ├─ ai/subagents/     query(查询) / question(出题) / tutor(伴学) + subject_personas
        └─ db/models/        User · Task · Question · TaskQuestion · Conversation / Message · …
        │
        ▼
SQLite（本地零依赖，默认） / PostgreSQL（Docker / 云）
```

**所有 AI 能力经单一 SSE 入口** `POST /api/v1/assistant/chat`（流式事件帧：USER_MESSAGE / THINKING / TOOL_CALL / TOOL_RESULT / DATA / ASSISTANT_MESSAGE / DONE）。出题 / 伴学 / 查询都走此入口，旧的 `/ai/tutor/ask`、`/ai/tasks/generate` 已废弃并收敛到此。

核心原则：

- **不在 LangChain 之上重复封装 provider**：`LLMProvider` 是 `agent_core/ports.py` 里的抽象端口，业务只认抽象、不绑框架；引擎解析收敛到 `resolve_engine`（读家长 `ModelConfig`），无内置目录、无本地 `LLM_PROVIDER` 等旁路 env。
- **模型必须经「模型管理」配置**：出题 / 答疑 / 批改都需真实引擎；未配置时返回「未配置模型」提示，没有离线 `mock` 兜底。
- 分层不变量（内核不反向依赖 app / fastapi、genkit 唯一落点、归属判定只经 `core.guard`）由 `tests/ai/test_layering_invariants.py` 静态扫描守住。

## 目录

```
.
├── backend/                 # Python 后端（uv 管理，Python >= 3.14，单 wheel 含 app + agent_core）
│   ├── app/
│   │   ├── main.py          # FastAPI 入口（app.main:app）
│   │   ├── api/main.py      # 聚合所有 features/* router（挂在 /api/v1）
│   │   ├── core/            # config(env) / db / security / guard / errors / deps / crypto
│   │   ├── domain/          # grader · review_scheduler · mastery · safety · retriever · prompts
│   │   ├── features/        # auth children tasks review mastery tutor questions
│   │   │                    # model_management ai assistant export health
│   │   ├── ai/              # engine.py(resolve_engine) / subagents/{query,question,tutor,guide}
│   │   └── db/models/
│   ├── agent_core/          # 框架无关 agent 内核（零 app/三方依赖）
│   ├── scripts/             # copyright_compliance_check.py（版权合规门禁）
│   └── Dockerfile
├── frontend/                # Flutter 平板 App
│   ├── lib/
│   │   ├── main/            # 入口 + AdaptiveShell（响应式壳）
│   │   ├── configs/app_config.dart   # API Base URL（--dart-define=API_BASE 注入）
│   │   ├── features/        # auth / children / home / practice / review / tutor / assistant
│   │   │                    # export / model_management / profile
│   │   ├── shared/          # data / domain / presentation / theme(设计令牌) / widgets
│   │   └── dev/             # theme_preview.dart（设计系统自检）
│   └── analysis_options.yaml # flutter_lints + 设计系统硬约束
├── .env.example             # 后端本地配置模板（复制为 .env）
├── docker-compose.yml       # PostgreSQL + backend 一键起
└── docs/agents/             # 面向 AI 代理的架构 / 规范 / 命令文档
```

---

## 快速开始

### 方式 A：本地直接跑（无需 Docker，推荐先验证）

后端用 `uv` 管理依赖（Python ≥ 3.14，`uv.lock` 已锁定）。本地默认 SQLite，零额外依赖；但 AI 出题 / 答疑 / 批改需先在「模型管理」配置模型（见下方），否则相关接口返回「未配置模型」提示。

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

本地 `fastapi dev` / `uvicorn --reload` **默认只绑定 `127.0.0.1`**。当 App 跑在真机、平板或模拟器上时，`127.0.0.1` 指向的是**设备自身**而非你的电脑，会导致登录 / 请求报「请求失败 (-1)」且服务端无任何日志（请求根本没进来）。

联调时后端必须放开监听地址，并用电脑**局域网 IP**（不是 `127.0.0.1` / `localhost`）：

```bash
cd backend
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# 前端（另开终端），API_BASE 填电脑局域网 IP：
cd frontend
flutter run --dart-define=API_BASE=http://<电脑局域网IP>:8000
```

> 查电脑局域网 IP：`ifconfig | grep "inet "`（忽略 127.0.0.1）。Docker 方式已默认 `--host 0.0.0.0`，无需此步。
> 若仍连不上：先 `curl http://<电脑局域网IP>:8000/api/v1/health` 确认后端可达；检查防火墙是否放行 8000。

### 方式 B：Docker 一键（PostgreSQL）

```bash
cp .env.example backend/.env    # 按需改 SECRET_KEY / MODEL_APIKEY_SECRET
docker compose up --build       # 启动 PostgreSQL + backend，后端暴露 8000
```

---

## 命令速查

### 后端（目录 `backend/`）

| 动作 | 命令 |
|------|------|
| 安装依赖 | `uv sync` |
| 本地起服（仅本机） | `uv run fastapi dev` 或 `uv run uvicorn app.main:app --reload` |
| 局域网联调（真机 / 平板必用） | `uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload` |
| Lint（零 error 门禁） | `uv run ruff check .` |
| 测试 | `uv run pytest -q` |
| 真实模型 smoke | `RUN_LLM_SMOKE=1 SMOKE_MODEL_NAME=llama3 SMOKE_MODEL_API_KEY=ollama uv run pytest tests/domain/test_llm_smoke.py -m smoke -v` |
| 版权合规自检 | `python scripts/copyright_compliance_check.py --self-test` |

### 前端（目录 `frontend/`，Flutter ≥ 3.5）

| 动作 | 命令 |
|------|------|
| 安装依赖 | `flutter pub get` |
| 起服（联调） | `flutter run --dart-define=API_BASE=http://<电脑局域网IP>:8000` |
| 静态分析（零 issue 门禁） | `flutter analyze` |
| 测试 | `flutter test` |
| 设计系统自检 | 运行 `lib/dev/theme_preview.dart` 页面核对令牌一致性 |

### CI（`.github/workflows/`）

- `ci.yml`：frontend（`flutter analyze` + `flutter test`）→ backend（`ruff check` + `pytest`）。
- `compliance.yml`：后端 `pytest` + 版权合规门禁（ADR-0019 / ADR-0020）。

---

## 配置模型

AI 出题 / 伴学 / 批改都需真实引擎，且**无内置模型、无本地 `mock` 兜底**。只有一条路径：

**家长在「模型管理」中添加**（ADR-0039）——登录后点「添加模型」，选服务商（DeepSeek / OpenAI / Ollama / …）自动带出 base_url 与模型名建议，**填写 API Key（必填）**，保存后可「设为默认」。api_key 经 Fernet 加密落 `ModelConfig` 表；未显式指定模型时回落该默认模型。

> `provider ∈ {ollama, openai_compat}`；`base_url` 留空时 ollama 走 `OLLAMA_BASE_URL`（默认 `http://localhost:11434`）。
> **先固定 `MODEL_APIKEY_SECRET` 再加模型**：该值决定加密密钥，改它会让已存 API Key 全部解不开（事故见 `docs/adr/0038`）。加错顺序时，回到「模型管理」重填一次 Key 即可恢复。

---

## API 速览

所有路径带 `/api/v1` 前缀。交互式文档：http://localhost:8000/docs

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/auth/register` | 家长注册（返回 token） |
| POST | `/auth/login` | 登录 |
| GET  | `/auth/me` | 当前用户 |
| POST | `/children` | 家长添加娃娃账号 |
| GET  | `/children` | 家长列出娃娃 |
| POST | `/tasks/generate` | 家长生成题目（SSE 流式，调 LLM） |
| GET  | `/tasks/today` | 娃娃查看今日任务 |
| POST | `/tasks/{task_id}/answer` | 娃娃提交单题 → 自动批改 |
| POST | `/tasks/{task_id}/checkin` | 完成任务打卡 |
| GET  | `/tasks/wrong-questions` | 娃娃错题列表 |
| GET  | `/tasks/children/{child_id}/progress` | 家长看进度（正确率 / 连续打卡） |
| GET  | `/tasks/children/{child_id}/mastery` | 掌握度看板 |
| GET  | `/review/due` | 到期待复习题（遗忘曲线） |
| POST | `/review/answer` | 复习作答 |
| POST | `/export/sheet` | 打印导出（返回 PDF，source=bank\|task\|wrong_book） |
| POST | `/assistant/chat` | **AI 统一入口（SSE）**：出题 / 伴学 / 查询，按角色 + 触发词路由 |
| GET  | `/assistant/conversations` | 家长的会话历史（仅家长） |
| GET  | `/health` | 健康检查 |

> 伴学答疑、出题、查询统一走 `POST /assistant/chat`（流式）。`tutor` router 仅保留 `GET /logs`（伴学记录）；**每日配额管控已移除**，不存在 `/tutor/quota`。

---

## 改动前必读

- **领域术语**以仓库根 `CONTEXT.md` 为唯一事实源，已落地决策见 `docs/adr/`。
- **设计系统**：颜色 / 间距 / 字号只走设计令牌，禁止硬编码（见 `.impeccable.md` 与 ADR-0044 ~ 0048）。
- **跨层硬规则**：归属与可见性判定只经 `core.guard`；query 工具只经 service 取数。
- **提交**：按逻辑批次拆，正文写「为什么」；记忆类更新单独用 `chore(memory):` 前缀。
