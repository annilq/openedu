# AGENTS.md — 娃娃学习 App

> 面向 AI 编码代理的项目指引。本文件只放「每个任务都适用」的要点；细分规范通过下方链接按需展开（渐进式披露，避免一次倾泻全部约束）。

## 项目一句话

Flutter（Riverpod + cupertino_ui）平板 / 桌面 App + Python（FastAPI / SQLModel）后端，面向「家长出题、娃娃做题与 AI 伴学」的家庭学习闭环。

## 包管理器（不是 npm）

- 后端：**uv**（Python ≥ 3.14）。`cd backend && uv sync`。
- 前端：**Flutter / Dart**（`flutter pub get`），不是 npm。

## 每个任务都相关的命令

后端（`backend/`）：

| 用途 | 命令 |
|---|---|
| 安装依赖 | `uv sync` |
| 启动开发服 | `uv run fastapi dev`（或 `uv run uvicorn app.main:app --reload`） |
| 测试 | `uv run pytest` |
| Lint | `uv run ruff check .` |
| 真实模型 smoke（需 key） | `LLM_PROVIDER=deepseek RUN_LLM_SMOKE=1 uv run pytest tests/domain/test_llm_smoke.py -m smoke -v` |

前端（`frontend/`）：

| 用途 | 命令 |
|---|---|
| 取依赖 | `flutter pub get` |
| Lint 门禁（零警告） | `flutter analyze` |
| 测试 | `flutter test` |

## 全局硬约束

- API 统一前缀 `/api/v1`；鉴权 `Authorization: Bearer <JWT>`。
- `LLM_PROVIDER=mock`（默认）无需任何 key 即可跑通全闭环（注册→加娃→出题→作答→批改→打卡→进度）。
- 架构变更**先改文档与 ADR，再改代码**（见 [docs/agents/git-workflow.md](docs/agents/git-workflow.md)）。
- 儿童内容安全双层防护 + 教材版权硬门槛（ADR-008 / ADR-012）——**对外分发 / 上线前必须解决版权**。
- 业务代码（`api/`、`domain/`）**禁止直接 `import langchain`**；厂商适配只在 `LangChainProvider` 内，换模型 = 改配置。

## 细分规范（按需展开，不要一次全读）

### 后端 / Python
- 后端约定（SQLModel / cuuid / 配置 / 隔离 / 错误码 / 迁移 / 测试） → [docs/agents/backend.md](docs/agents/backend.md)
- 后端架构（**事实源**，已修正 §5.1 async / §6 Task 状态两处过期描述） → [技术架构_后端.md](技术架构_后端.md)
- 业务功能与架构分析（与上文有重叠，互补阅读；**架构判断以《技术架构_后端.md》为准**） → [项目分析_架构规范与业务功能.md](项目分析_架构规范与业务功能.md)

### 前端 / Flutter
- 前端约定（Clean Arch / App* 组件 / 导航 / 令牌） → [docs/agents/frontend.md](docs/agents/frontend.md)
- 设计系统（令牌 / 字号 / 动效，唯一事实源） → [frontend/.impeccable.md](frontend/.impeccable.md) · [frontend/CONTEXT.md](frontend/CONTEXT.md)
- 单文件行数门禁 → [frontend/CODE_CONVENTIONS.md](frontend/CODE_CONVENTIONS.md)
- Material→Cupertino 迁移契约（已完成） → [frontend/.migration_guide.md](frontend/.migration_guide.md)

### 通用
- 架构决策索引（ADR） → [docs/agents/architecture.md](docs/agents/architecture.md)
- 领域模型与术语 / 错误码 → [docs/agents/domain-model.md](docs/agents/domain-model.md)
- 变更纪律 / Git 流程 → [docs/agents/git-workflow.md](docs/agents/git-workflow.md)
- 待清理 / 待删除项清单 → [docs/agents/cleanup-flags.md](docs/agents/cleanup-flags.md)

### 开发规范 Skill 导航（编码代理可调用）
- `/impeccable`：前端设计评审 / 审计 / 打磨，基于 `frontend/.impeccable.md` 的设计系统令牌。
- 暂未安装 Flutter / Python 专用编码 skill；以上规范文档即事实源，优先读对应语言的子文件。

## Plan Mode

- Make the plan extremely concise. Sacrifice grammar for the sake of concision.
- At the end of each plan, give me a list of unresolved questions to answer, if any.

## Agent skills

### Issue tracker

Issues live as local markdown files under `.scratch/<feature>/` (already in use). See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical triage roles (`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`); defaults match our vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`.
