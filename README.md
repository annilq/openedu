# 娃娃日常学习应用 · 最小可跑原型（一期）

家长给娃娃布置 AI 生成的日常练习，娃娃在平板上做题、自动批改、打卡。
技术栈：**Flutter 平板 App + Python/FastAPI/LangChain 后端 + PostgreSQL**。
**无模型 key 也能跑通**（内置 MockProvider 兜底）。

---

## 架构

```
Flutter 平板 App（娃娃端 / 家长端）
        │  HTTP/JSON
        ▼
FastAPI 后端
  ├─ routers: auth / children / tasks(出题·批改·打卡·进度)
  ├─ domain: QuestionGenerator · Grader
  │     └─ LLMProvider 抽象 ── MockProvider（默认,无需key） / LangChainProvider（真实模型）
  └─ models: User · Task · Question · AnswerRecord · Checkin
        │
        ▼
PostgreSQL（本地 Docker / 云）
```

核心原则（见 `娃娃学习App_ADR.md`）：
- **不在 LangChain 之上重复封装 provider**，只在"框架层"自封领域接口，业务不绑框架。
- **模型先不定**：`LLM_PROVIDER=mock|langchain` 切换，国产模型填 `LLM_BASE_URL`(OpenAI 兼容) 即可接入。

---

## 目录

```
.
├── backend/                 # Python 后端
│   ├── app/
│   │   ├── main.py          # FastAPI 入口
│   │   ├── config.py        # 配置（env 可配）
│   │   ├── database.py      # SQLAlchemy async + PG/SQLite
│   │   ├── security.py      # 密码哈希 + JWT
│   │   ├── deps.py          # 依赖注入
│   │   ├── models.py        # ORM
│   │   ├── schemas.py       # pydantic
│   │   ├── domain/          # 领域层（provider 抽象 + 出题/批改）
│   │   └── routers/         # auth / children / tasks
│   ├── requirements.txt
│   ├── Dockerfile
│   └── .env.example
├── frontend/                # Flutter 平板 App
│   └── lib/                 # main / api / screens(login,home)
└── docker-compose.yml       # PG + backend 一键起
```

---

## 快速开始

### 方式 A：本地直接跑（无需 Docker，推荐先验证）

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt        # 含 langchain；仅验证 mock 可只装前面依赖
cp .env.example .env                   # 默认 LLM_PROVIDER=mock，无需 key
python run.py                          # 启动于 http://localhost:8000
```

健康检查：`curl http://localhost:8000/health`

### 方式 B：Docker 一键（PostgreSQL）

```bash
cp backend/.env.example backend/.env    # 按需改 JWT_SECRET / LLM_*
docker compose up --build
```

---

## 配置真实大模型

编辑 `backend/.env`：

```
LLM_PROVIDER=langchain
LLM_API_KEY=你的key
LLM_BASE_URL=https://api.hunyuan.cloud.tencent.com/v1   # 国产模型填兼容端点
LLM_MODEL=hunyuan-lite
```

> 国产模型（混元/通义/智谱/豆包）多走 OpenAI 兼容协议，填 `base_url` 即可，业务代码零改动。

---

## API 速览

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/auth/register` | 家长注册（返回 token） |
| POST | `/auth/login` | 登录 |
| POST | `/children` | 家长添加娃娃账号 |
| GET  | `/children` | 家长列出娃娃（含 ID） |
| POST | `/tasks/generate` | 家长生成任务+题目（调 LLM） |
| GET  | `/tasks/today` | 娃娃查看今日任务 |
| POST | `/tasks/{id}/answer` | 娃娃提交单题 → 自动批改 |
| POST | `/tasks/{id}/checkin` | 完成任务打卡 |
| GET  | `/tasks/children/{id}/progress` | 家长查看进度（正确率/连续打卡） |

---

## 前端 Flutter

1. 安装 Flutter SDK；用平板或模拟器。
2. 改 `frontend/lib/api.dart` 的 `kApiBase` 为你电脑局域网 IP，如 `http://192.168.1.50:8000`。
3. 运行：

```bash
cd frontend
flutter pub get
flutter run
```

家长端可生成任务、看娃娃列表（含 ID）；娃娃端做题、提交看对错解析、打卡。

---

## 一期闭环演示步骤

1. 后端以 `mock` 模式启动。
2. 家长注册 → 登录（拿 token）。
3. 家长添加娃娃（child 账号，记好返回的 ID）。
4. 家长 `POST /tasks/generate`（填 child_id、学科、知识点、题型、数量）。
5. 娃娃登录 → 首页看到今日任务 → 逐题作答 → 看解析 → 打卡。
6. 家长 `GET /tasks/children/{id}/progress` 查看正确率与连续打卡天数。

---

## 路线图

- **一期（已搭骨架）**：刷题练习 + 每日打卡 + AI 出题（mock/真实）。
- **二期**：错题本 + 遗忘曲线复习（新增 Review 模块 + scheduler）。
- **三期**：AI 伴学答疑（启用双层内容安全防护，见 ADR-008）+ 教材知识库 RAG（KnowledgeRetriever / IntentRouter）。
- **长期**：教材版权合规（上线前必须解决，见 ADR-012）、云部署、跨设备同步。

---

## 合规提醒

教材（人教版等）受版权保护。**自用/开发阶段可用；凡是做成对外分发产品，上线前必须取得版权授权或改用公版/自编内容。**
