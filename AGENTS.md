# Agents

> openedu 仓库面向 AI 编码代理的**入口索引**。
> **本文件只做渐进式披露**：给「够用的结论 + 去哪看细节」，**规则正文一律不在本文件展开**——
> 正文在 `docs/agents/*`、`.impeccable.md`、`docs/adr/`。
> 动手前：先按「按任务找文档」定位一份读完。领域术语以 `CONTEXT.md` 为准；已落地决策见 `docs/adr/`。

## 这是什么

K12 错题复习应用：家长出题 → 儿童答题产生错题 → 间隔重复复习直至毕业。Flutter 平板 App + FastAPI 后端
（单 wheel 含 `agent_core` 内核 + `app` 集成层）+ SQLite/PostgreSQL。模型在客户端「模型管理」里手动添加
（家长 `ModelConfig`，api_key 经 Fernet 加密；**无内置模型目录**，ADR-0039）；未添加时出题/答疑/批改返回
「未配置模型」提示，**无离线 mock 兜底**。

## 技术栈速览

- **前端**：Flutter（Dart ≥3.5，CI 锁 3.47.2）· Riverpod · Dio · Cupertino · shadcn_ui · tablet-first
- **后端**：Python ≥3.14 · FastAPI · SQLModel · `uv` 管理依赖
- **AI**：`agent_core` 框架无关内核 + genkit 适配器；引擎统一经 `resolve_engine` 解析（只读家长 `ModelConfig` 与其 `is_default`，无内置目录、无本地 `LLM_PROVIDER` 等旁路 env）
- **DB**：SQLite（默认零依赖）/ PostgreSQL（Docker / 云）

## 按任务找文档

| 我要改… | 先读 |
|---|---|
| 后端分层 · `agent_core` 与 `app` 边界 · 单一 SSE 入口 | [`docs/agents/architecture.md`](docs/agents/architecture.md) |
| AI 工具 · SubAgent · 模型引擎 · 助手卡片协议 | [`docs/agents/ai.md`](docs/agents/ai.md) |
| 前端页面 · 组件 · 布局 · 导航 · 文件规模 | [`docs/agents/frontend.md`](docs/agents/frontend.md) |
| 视觉（颜色 / 描边 / 选中悬停焦点 / 空态） | [`.impeccable.md`](.impeccable.md) |
| 命令 · lint · 测试 · ADR 纪律 | [`docs/agents/development.md`](docs/agents/development.md) |
| 领域术语 | [`CONTEXT.md`](CONTEXT.md) |
| 已落地决策 | [`docs/adr/`](docs/adr/) |

## 硬约束速览（一句话版）

> 每条只给结论。**为什么、怎么做、谁在守**见括号内文档——改代码前读那一段，不要只看这一句。

**后端 / AI**

- 取数的归属与可见性判定**只经 `core.guard`**；query 工具只经 service 取数 → `development.md` §3.5
- 工具参数必须有缺席编码（`""` / `0`）、枚举必含 `NO_FILTER` → `ai.md` §1 · ADR-0040
- 引擎失败不许被 `except Exception` 抹成「请添加模型」；密文永不出门 → `ai.md` §2 · ADR-0038
- 助手卡片按 `data.type` 判别，服务端不拼展示串；写意图走 `guide` 而非 `query` → `ai.md` §3 · ADR-0042/0054
- 推理（`REASONING`）不进答案、不进回灌历史 → `ai.md` §4 · ADR-0043

**前端**

- `shared/` 不得 import `features/`；feature 之间不横向互引 → `frontend.md` §1 · ADR-0037
- 布局只看**可用宽度**，尺寸一律走 `AppLayout` 令牌；可点区域一律 `AppFocusableAction` → `frontend.md` §2 · ADR-0045
- 家长端导航只能有一个 `sealed` 状态，**禁止**「索引 + 覆盖层 + 布尔」并列 → `frontend.md` §3 · ADR-0059
- 新文件 **≤400 行**，一个文件只暴露一个公开物 → `frontend.md` §4 · ADR-0058
- 助手是整页不是浮层；会话历史是页内切模式不是三层栈 → `frontend.md` §5 · ADR-0047/0048

**视觉**（细节全在 [`.impeccable.md`](.impeccable.md)，本文件不复述）

- 亮块配墨黑、深块配白；描边三档不写裸数字 → ADR-0044
- 「选中」全站只有一种语言：无描边药丸 + `surfaceActive` → §Interaction · ADR-0046
- 空态必须回答「为什么空」+「下一步做什么」 → §Empty State · ADR-0051
- 学科三重编码：色相 + 明度差 + 几何标记，禁止仅靠颜色 → §Accessibility

> **迁移进行中**（ADR-0044）：token 层先行 + 试点，**禁止一次性全量重做**。未迁移页面仍走旧语义令牌，
> 属预期状态，不必逐个「修正」。

## 命令速查 → [docs/agents/development.md#2-命令速查commands](docs/agents/development.md)

| 场景 | 命令 |
|------|------|
| 后端起服（局域网联调） | `cd backend && uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload` |
| 后端 lint / test | `uv run ruff check .` · `uv run pytest -q` |
| 前端起服（联调） | `cd frontend && flutter run --dart-define=API_BASE=http://<LAN_IP>:8000` |
| 前端 analyze / test | `flutter analyze` · `flutter test` |
| 一键 Docker | `docker compose up --build` |

> 联调铁律：后端 `--host 0.0.0.0` + 前端 `API_BASE` 填**电脑局域网 IP**（非 `127.0.0.1`，否则真机报
> 「请求失败 (-1)」且服务端无日志）。详见 development.md §2.1。

## Agent skills

### Issue tracker → [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md)

Issues / PRDs 以 GitHub Issues 承载，全部操作经 `gh` CLI。建读列评论打标签关闭的命令模板在此。

### Triage labels → [docs/agents/triage-labels.md](docs/agents/triage-labels.md)

五个 canonical triage 角色对应的标签字符串：`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`。

### Domain docs → [docs/agents/domain.md](docs/agents/domain.md)

探索代码前先读 `CONTEXT.md` + 相关 `docs/adr/`；用 glossary 术语命名，矛盾 ADR 需显式提出而非静默覆盖。

## 关键事实源与已知风险

- **领域术语**：`CONTEXT.md`（唯一 glossary）。
- **ADR**：决策记 `docs/adr/`，被代码引用即需有可定位正文。**取号前先看目录最大号**，并查
  `.workbuddy/memory/` 有无已被其他会话预留的号（历史上撞过两次）。
- **历史架构评审**：早期 `agent_core` 评审的 P0/P1/P2 建议均已落地（扩展钩子见 ADR-0035、配置健壮性见 ADR-0041），结论不代表当前状态。
- **平台 runner 未纳入版本控制**：`frontend/.gitignore` 第 20–25 行忽略
  `android / linux / macos / web / windows / ios`，即**平台目录全是本机生成物**。改桌面窗口尺寸、
  原生权限、Info.plist 之类只在本机生效，`flutter create` 重新生成或换机器构建都会回退。
  要做持久改动必须先决定「纳入版本控制 or 打补丁脚本」。
