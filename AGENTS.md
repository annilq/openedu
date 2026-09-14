# Agents

> openedu 仓库面向 AI 编码代理的**入口索引**。本文件只给「够用的结论 + 去哪看细节」，细节在 `docs/agents/*`。改本仓库前先读完本节与链接文档。
> 领域术语以仓库根 `CONTEXT.md` 为准；已落地决策见 `docs/adr/`。

## 这是什么

K12 错题复习应用：家长出题 → 儿童答题产生错题 → 间隔重复复习直至毕业。Flutter 平板 App + FastAPI 后端（单 wheel 含 `agent_core` 内核 + `app` 集成层）+ SQLite/PostgreSQL。模型经「模型管理」配置（家长 `ModelConfig` / 管理员 `BUILTIN_MODELS`）；未配置时出题/答疑/批改返回「未配置模型」提示，**无离线 mock 兜底**。

## 技术栈速览

- **前端**：Flutter（Dart ≥3.5，CI 锁 3.47.2）· Riverpod · Dio · Cupertino · shadcn_ui · tablet-first
- **后端**：Python ≥3.14 · FastAPI · SQLModel · `uv` 管理依赖
- **AI**：`agent_core` 框架无关内核 + genkit 适配器；引擎统一经 `resolve_engine` 解析（家长 `ModelConfig` / 管理员 `BUILTIN_MODELS`，无本地 `LLM_PROVIDER` 等旁路 env）
- **DB**：SQLite（默认零依赖）/ PostgreSQL（Docker / 云）

## 架构 → [docs/agents/architecture.md](docs/agents/architecture.md)

后端 `agent_core`（零 `app` / 零三方依赖的 agent 内核）与 `app`（FastAPI 集成层）同发一 wheel；前端 Riverpod + adaptive shell + 设计令牌单一事实源。所有 AI 能力收敛到单一 SSE 入口 `POST /api/v1/assistant/chat`。分层不变量由 `tests/ai/test_layering_invariants.py` 静态扫描守住。改跨层代码前必读。

## 开发规范 → [docs/agents/development.md](docs/agents/development.md)

- **Lint**：后端 `ruff`（E/W/F/I，忽略 E501，零 error）；前端 `flutter analyze`（零 issue）。
- **测试**：后端 `pytest`（分层不变量 / SubAgent 契约 / domain 单测）；前端 `flutter test`。
- **ADR**：决策记 `docs/adr/`，被引用即需可定位；领域词汇以 `CONTEXT.md` 为唯一事实源。
- **设计系统**：颜色/间距/字号只走 `AppColors`/`AppSpacing`/`AppText` 令牌，禁止硬编码。
- **跨层硬规则**：归属/可见性判定只经 `core.guard`；query 工具只经 service 取数。
- **前端分层**（ADR-0037）：`main/ → features/* → shared/*` 单向，**`shared/` 不得 import `features/`**；feature 之间不得横向互引（唯一豁免 `features/home/presentation/`，展示层组合根）；feature 与后端 `app/features/*` 一一对应。`App*` 前缀只给 `shared/widgets/` 通用组件——组件一旦订阅某 feature 的 provider 就落回该 feature。由 `frontend/test/feature_boundaries_test.dart` 静态扫描守住。

## 命令速查 → [docs/agents/development.md#2-命令速查commands](docs/agents/development.md)

| 场景 | 命令 |
|------|------|
| 后端起服（局域网联调） | `cd backend && uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload` |
| 后端 lint / test | `uv run ruff check .` · `uv run pytest -q` |
| 前端起服（联调） | `cd frontend && flutter run --dart-define=API_BASE=http://<LAN_IP>:8000` |
| 前端 analyze / test | `flutter analyze` · `flutter test` |
| 一键 Docker | `docker compose up --build` |

> 联调铁律：后端 `--host 0.0.0.0` + 前端 `API_BASE` 填**电脑局域网 IP**（非 `127.0.0.1`，否则真机报「请求失败 (-1)」且服务端无日志）。详见 development.md §2.1。

## Agent skills

### Issue tracker → [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md)

Issues / PRDs 以 GitHub Issues 承载，全部操作经 `gh` CLI。建读列评论打标签关闭的命令模板在此。

### Triage labels → [docs/agents/triage-labels.md](docs/agents/triage-labels.md)

五个 canonical triage 角色对应的标签字符串：`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`。

### Domain docs → [docs/agents/domain.md](docs/agents/domain.md)

探索代码前先读 `CONTEXT.md` + 相关 `docs/adr/`；用 glossary 术语命名，矛盾 ADR 需显式提出而非静默覆盖。

## 关键事实源与已知风险

- **领域术语**：`CONTEXT.md`（唯一 glossary）。
- **架构评审**：`docs/agent-core-architecture-review.md`（含 P0 缺失 ADR、P1 缺 compaction、P2 缺扩展钩子、前端 SSE 逐帧渲染待定）。
- **ADR 索引**：`docs/adr/` 已落地 0001–0037（含 0008/0012/0014/0015/0017/0019/0020/0021–0028/0030–0037）；仅 0006/0007/0009–0011/0013/0016/0018/0029 无文档。新增决策先补 ADR 再在代码中交叉链接引用。
