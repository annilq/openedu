# 娃娃日常学习应用 · 最小可跑原型

家长给娃娃布置 AI 生成的日常练习，娃娃在平板上做题、自动批改、打卡、错题复习与 AI 伴学答疑。
技术栈：**Flutter 平板 App（Riverpod + Dio + Cupertino）+ Python/FastAPI/SQLModel 后端 + PostgreSQL（可换 SQLite）**。
**无模型 key 也能跑通**（默认 MockProvider 兜底）。

---

## 架构

```
Flutter 平板 App（娃娃端 / 家长端）
        │  HTTP/JSON（/api/v1）
        ▼
FastAPI 后端（backend/app）
  ├─ api/routes: auth / children / tasks(出题·批改·打卡·进度) / review(错题·复习) / mastery(掌握度) / tutor(AI伴学·额度) / health
  ├─ domain: QuestionGenerator · Grader · ReviewScheduler · TutorEngine
  │     └─ LLMProvider 抽象 ── MockProvider（默认,无需key） / LangChainProvider（真实模型）/ DeepSeek 快捷预设
  └─ models: User · Task · Question · AnswerRecord · Checkin · …
        │
        ▼
SQLite（本地零依赖，默认） / PostgreSQL（Docker / 云）
```

核心原则（见 `娃娃学习App_ADR.md`）：
- **不在 LangChain 之上重复封装 provider**，只在"框架层"自封领域接口，业务不绑框架。
- **模型先不定**：`LLM_PROVIDER=mock|langchain|deepseek` 切换，国产模型填 `LLM_BASE_URL`(OpenAI 兼容) 即可接入。

---

## 目录

```
.
├── backend/                 # Python 后端（uv 管理，Python >= 3.14）
│   ├── app/
│   │   ├── main.py          # FastAPI 入口（app.main:app）
│   │   ├── core/            # config(env) / db / security
│   │   ├── api/             # 路由：auth / children / tasks / review / mastery / tutor / health
│   │   ├── domain/          # provider 抽象 + 出题/批改/复习/伴学
│   │   └── crud.py / models.py
│   ├── tests/               # pytest（含真实模型 smoke）
│   ├── pyproject.toml       # 依赖声明（替代 requirements.txt）
│   ├── uv.lock
│   └── Dockerfile
├── frontend/                # Flutter 平板 App（Riverpod + Dio + Cupertino）
│   ├── lib/
│   │   ├── main.dart
│   │   ├── main/app.dart
│   │   ├── configs/app_config.dart   # API Base URL 配置
│   │   ├── features/                 # 按功能划分：auth / children / home / practice / review / tutor / profile
│   │   └── shared/                   # 网络 / 本地存储 / 主题 / 通用组件
│   └── pubspec.yaml
├── .env.example             # 后端本地配置模板（复制为 .env）
├── docker-compose.yml       # PostgreSQL + backend 一键起
└── README.md
```

---

## 快速开始

### 方式 A：本地直接跑（无需 Docker，推荐先验证）

后端用 `uv` 管理依赖（Python >= 3.14，`uv.lock` 已锁定）。默认 `LLM_PROVIDER=mock`，无需 key；本地默认 SQLite，零额外依赖。

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

### 方式 B：Docker 一键（PostgreSQL）

```bash
cp .env.example .env          # 按需改 SECRET_KEY / LLM_*
docker compose up --build     # 启动 PostgreSQL + backend，后端暴露 8000
```

---

## 配置真实大模型

编辑仓库根目录 `.env`（后端从根目录读取，容器内兜底读取 `backend/.env`）：

```dotenv
# 方式一：通用 OpenAI 兼容端点（混元/通义/豆包等）
LLM_PROVIDER=langchain
LLM_BASE_URL=https://api.hunyuan.cloud.tencent.com/v1
LLM_MODEL=hunyuan-lite
LLM_API_KEY=你的key

# 方式二：DeepSeek 快捷预设（无需填上面 LLM_* 三项）
# LLM_PROVIDER=deepseek
# DEEPSEEK_API_KEY=你的deepseek_key
```

> 未知 provider 值会回退 mock 并告警；显式选 `langchain`/`deepseek` 但未配好端点会在启动时报错。
> 真实连通 smoke 测试：`LLM_PROVIDER=deepseek RUN_LLM_SMOKE=1 uv run pytest tests/domain/test_llm_smoke.py -m smoke -v`

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
| POST | `/api/v1/tasks` | 家长生成任务+题目（调 LLM） |
| GET  | `/api/v1/tasks/today` | 娃娃查看今日任务 |
| POST | `/api/v1/tasks/{task_id}/answer` | 娃娃提交单题 → 自动批改 |
| POST | `/api/v1/tasks/{task_id}/checkin` | 完成任务打卡 |
| GET  | `/api/v1/tasks/wrong-questions` | 娃娃错题列表 |
| GET  | `/api/v1/tasks/children/{child_id}/progress` | 家长看进度（正确率/连续打卡） |
| GET  | `/api/v1/tasks/children/{child_id}/mastery` | 掌握度看板 |
| GET  | `/api/v1/review/due` | 到期待复习题（遗忘曲线） |
| POST | `/api/v1/review/answer` | 复习作答 |
| POST | `/api/v1/tutor/ask` | AI 伴学答疑 |
| GET  | `/api/v1/tutor/quota` | 伴学额度/用量 |
| GET  | `/api/v1/health` | 健康检查 |

---

## 前端 Flutter

1. 安装 Flutter SDK（Dart >= 3.5）；用平板或模拟器。
2. 配置后端地址：默认 `http://127.0.0.1:8000`（见 [app_config.dart](file:///Users/yunqi/Documents/develop/openedu/frontend/lib/configs/app_config.dart)）。真机/平板联调时改为电脑局域网 IP：

```bash
cd frontend
flutter pub get
flutter run --dart-define=API_BASE=http://192.168.1.50:8000
# 或直接改 lib/configs/app_config.dart 里的 AppConfig.apiBase
```

家长端可生成任务、看娃娃列表/进度/掌握度；娃娃端做题看解析、打卡、复习错题、AI 答疑。

---

## 闭环演示步骤

1. 后端以 `mock` 模式启动。
2. 家长注册 → 登录（拿 token）。
3. 家长添加娃娃（child 账号，记好返回的 ID）。
4. 家长 `POST /api/v1/tasks`（填 child_id、学科、知识点、题型、数量）。
5. 娃娃登录 → 首页看到今日任务 → 逐题作答 → 看解析 → 打卡。
6. 家长 `GET /api/v1/tasks/children/{id}/progress` 查看正确率与连续打卡天数。

---

## 路线图

- **一期（已实现）**：刷题练习 + 每日打卡 + AI 出题（mock/真实）。
- **二期（已实现）**：错题本 + 遗忘曲线复习（review 模块 + scheduler）+ 掌握度看板。
- **三期（已实现）**：AI 伴学答疑（内容安全防护 + 每日额度）+ 教材知识库检索（retriever）。
- **长期**：教材版权合规（上线前必须解决）、云部署、跨设备同步。

---

## 合规提醒

教材（人教版等）受版权保护。**自用/开发阶段可用；凡是做成对外分发产品，上线前必须取得版权授权或改用公版/自编内容。**
