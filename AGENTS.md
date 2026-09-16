# Agents

> openedu 仓库面向 AI 编码代理的**入口索引**。本文件只给「够用的结论 + 去哪看细节」，细节在 `docs/agents/*`。改本仓库前先读完本节与链接文档。
> 领域术语以仓库根 `CONTEXT.md` 为准；已落地决策见 `docs/adr/`。

## 这是什么

K12 错题复习应用：家长出题 → 儿童答题产生错题 → 间隔重复复习直至毕业。Flutter 平板 App + FastAPI 后端（单 wheel 含 `agent_core` 内核 + `app` 集成层）+ SQLite/PostgreSQL。模型在客户端「模型管理」里手动添加（家长 `ModelConfig`，api_key 经 Fernet 加密；**无内置模型目录**，ADR-0039）；未添加时出题/答疑/批改返回「未配置模型」提示，**无离线 mock 兜底**。

## 技术栈速览

- **前端**：Flutter（Dart ≥3.5，CI 锁 3.47.2）· Riverpod · Dio · Cupertino · shadcn_ui · tablet-first
- **后端**：Python ≥3.14 · FastAPI · SQLModel · `uv` 管理依赖
- **AI**：`agent_core` 框架无关内核 + genkit 适配器；引擎统一经 `resolve_engine` 解析（只读家长 `ModelConfig` 与其 `is_default`，无内置目录、无本地 `LLM_PROVIDER` 等旁路 env）
- **DB**：SQLite（默认零依赖）/ PostgreSQL（Docker / 云）

## 架构 → [docs/agents/architecture.md](docs/agents/architecture.md)

后端 `agent_core`（零 `app` / 零三方依赖的 agent 内核）与 `app`（FastAPI 集成层）同发一 wheel；前端 Riverpod + adaptive shell + 设计令牌单一事实源。所有 AI 能力收敛到单一 SSE 入口 `POST /api/v1/assistant/chat`。分层不变量由 `tests/ai/test_layering_invariants.py` 静态扫描守住。改跨层代码前必读。

## 开发规范 → [docs/agents/development.md](docs/agents/development.md)

- **Lint**：后端 `ruff`（E/W/F/I，忽略 E501，零 error）；前端 `flutter analyze`（零 issue）。
- **测试**：后端 `pytest`（分层不变量 / SubAgent 契约 / domain 单测）；前端 `flutter test`。
- **ADR**：决策记 `docs/adr/`，被引用即需可定位；领域词汇以 `CONTEXT.md` 为唯一事实源。
- **设计系统**：颜色/间距/字号只走 `AppColors`/`AppSpacing`/`AppText` 令牌，禁止硬编码。
- **跨层硬规则**：归属/可见性判定只经 `core.guard`；query 工具只经 service 取数。
- **工具 schema 必须在 OpenAI strict 模式下自洽**（ADR-0040）：genkit 对每个工具无条件套 `_ensure_strict_json_schema` + `strict: True`，把 `"required": []` 改写成「所有 property 必填」，模型被迫为每个参数编值。故每个可省略参数都要有类型合法的缺席编码（字符串 `""`、整数 `0`）并在 handler 归一为「未提供」；枚举型参数必须含 `NO_FILTER`（`"all"`）。归一收口在 `query/tools/_shared.py`（`optional_str` / `optional_int` / `resolve_children`），由 `tests/ai/test_query_tools_contract.py` 的行为级守卫守住。
- **引擎失败归因**（ADR-0038）：`decrypt()` 解不开只能返回 `None`（**密文永不出门**）；厂商失败（认证/限流/网络）→ `ProviderRequestError` → `ERROR(code="PROVIDER_ERROR")`，与「模型不支持工具调用」（`TOOL_UNSUPPORTED`，ADR-0033）**严格分开**。上层不得用 `except Exception` 把引擎失败抹成「请添加模型」。
- **前端分层**（ADR-0037）：`main/ → features/* → shared/*` 单向，**`shared/` 不得 import `features/`**；feature 之间不得横向互引（唯一豁免 `features/home/presentation/`，展示层组合根）；feature 与后端 `app/features/*` 一一对应。`App*` 前缀只给 `shared/widgets/` 通用组件——组件一旦订阅某 feature 的 provider 就落回该 feature。由 `frontend/test/feature_boundaries_test.dart` 静态扫描守住。
- **自适应布局与键盘可达性**（ADR-0045）：布局决策**只**基于可用宽度（`LayoutBuilder` 的 `constraints.maxWidth`），**禁止** `MediaQuery.of(context).size.width`（那是屏宽，不是可用宽度）、禁止 `orientationOf`、禁止 `isTablet`/`isDesktop` 这类设备形态判定。断点与内容宽度一律走 `AppLayout` 令牌（`compactMax 700` / `largeMin 1200` / `contentWide 1080` / `contentReading 820` / `contentCard 520` / `contentNarrow 480` / `contentEmpty 440` / `contentFloat 380`），**禁止写裸数字**；宽度上限由 `AdaptiveShell` 统一兜底，`Navigator.push` 的整页需自带约束。**可点区域一律用 `AppFocusableAction`**（裸 `GestureDetector` 不进焦点树 → 桌面端 Tab 跳不过去、Enter 点不动，而 `flutter analyze` 照不出来）。守卫 `frontend/test/adaptive_shell_layout_test.dart` + `app_focusable_keyboard_test.dart`。
- **助手卡片协议**（ADR-0042）：`DATA` 帧的 `data.type` 是**卡片种类判别键**（`question` / `task_list` / `wrong_question_list` / `due_review_list` / `mastery_list` / `child_list` / `progress` / `notice`），`data.result` 只放**结构化字段**（`{title, subject, items?, stats?, total?, text?}`）——服务端不拼展示串，排版归前端。新增种类要在 `query/render.py#_KIND` 与前端 `AssistantCardKind` 各登记一次；前端未登记的 kind 走降级卡（不丢内容）。**不要**在这条通道上做「服务端下发 UI schema」式的通用 GenUI。
- **推理/正文分流**（ADR-0043）：`TextDelta.kind`（`TextKind`：`TEXT`/`REASONING`，缺省 `TEXT`）由适配器按 `SegmentKind` 标注；`run_with_tools` 只把 `kind=TEXT` 累进答案，`REASONING` 只作思考回显（`THINKING` 帧）且**不进回灌历史**。工具型 subagent「无原生 `ToolCall` 且正文为空」→ `ERROR(TOOL_UNSUPPORTED)` 硬失败，绝不把内部独白当答复。守卫 `tests/ai/test_tool_loop_bounds.py`。协议泄露判据分强/弱两档：强标记（`<invoke name=` / `</invoke>` / `<parameter name=`）**命中即判泄露，不得绑定具体工具名**——模型编造工具名（把 `list_wrong_questions` 写成 `get_mistakes`）时点名匹配必然落空，绑上去等于开后门。

## 设计语言 → [.impeccable.md](.impeccable.md) · [ADR-0044](docs/adr/0044-neo-brutalist-visual-language.md) · [ADR-0045](docs/adr/0045-adaptive-layout-breakpoints-and-keyboard-access.md) · [ADR-0046](docs/adr/0046-navigation-interaction-language.md) · [ADR-0047](docs/adr/0047-assistant-full-page-for-parent.md)

**新粗野（Neo-Brutalism）**：高饱和原色撞色 + 2px 墨黑描边 + 无模糊硬阴影 + 弹性动效。取代 2026-09 前的 Linear 克制风（1px 描边 / 无阴影 / 中饱和小面积）。

> 渐进披露：本页**只列改视觉代码前必须知道的硬约束**。完整色板、品牌人格、自适应布局与八条设计原则见 `.impeccable.md`；选型过程与八个方向的取舍见 ADR-0044，布局断点 / 宽度令牌 / 键盘可达性见 ADR-0045，选中 / 悬停 / 焦点三态语言见 ADR-0046，家长端助手整页形态见 ADR-0047，助手会话历史（页内切模式 / 孩子只读）见 ADR-0048。术语见 `CONTEXT.md` §设计语言。

- **一个色只有一种合规文字**（AA 实测，不可互换）：亮块 `yellow / lime / cyan / teal / orange / coral / magenta / green` 配**墨黑 `#111110`**；深块 `violet / red / blue` 配**白**。原因：所有高饱和色配白字对比度最高只有 4.78，过不了 4.5。
- **色块是强调件，不是铺底**：单卡片内彩色填充 ≤ 卡片面积 40%、单屏不同色相 ≤ 3、列表行禁止整行彩色填充（只留 4px 学科色条）。撞色的作用是让人一眼找到重点。
- **描边三档禁写裸数字**：2 `AppElevation.borderWidth`（内容物体：卡 / 弹窗 / 浮层）· 1.5 `borderWidthSm`（密集列表小色块：chip / 徽标 / 题号）· 1 `borderWidthHairline`（结构边与重复安静元素：顶栏底边 / 侧栏右缘 / 分隔线 / `listRow`）。
- **墨黑描边是功能必需，不是装饰**：相邻高饱和色块对比度**中位数仅 1.67**（最低 `violet/red = 1.00`，亮度完全相同）。没有描边它们在视觉上分不开——任何「描边太重了去掉吧」的改动都是破坏可读性。
- **「选中」全站只有一种语言**（ADR-0046）：无描边药丸 + `surfaceActive` 填充 + accent 图标。**不要用带描边的卡片表示选中**——放在已带描边的浮层里就是盒中盒，把「选中」和「容器边界」混成一件事。
- **悬停走 `AppFocusableAction(hoverHighlight: true)`**（ADR-0046）：底色 `surfaceHover`（比选中浅一档）、画在底层故不会盖住选中态。**不要各组件手搓 `StatefulWidget + MouseRegion`**。焦点环一律 `foregroundDecoration` + `accent`（不参与布局，不跳尺寸）。任何可点区域必须进焦点树——**裸 `GestureDetector` 是 bug**。
- **布局与结构尺寸禁写裸数字**（ADR-0045/0046）：全部收口 `AppLayout`（断点 / 内容宽度各档 / `tapTarget` / `tapTargetLg` / `sidebarHeaderPadding` / `sidebarMenuWidth` / `popoverChrome` / `menuMaxHeight`）。`sidebarTop` 的内边距由宿主给，**组件自身零外边距**。
- **AI 助手是整页，不是浮层**（ADR-0047）：家长端右下角浮球 `Navigator.push` 打开 `AssistantChatPage`（`isParent: true`），娃娃端是「问 AI 老师」页签——同一个页面、同一份会话。改它时记住：push 的整页**不在壳的宽度兜底范围内**，页面自己套 `contentWide`。
- **助手会话历史是页内切模式，不是三层栈**（ADR-0048）：家长端助手页在**页内**切 `chat` / `history` / `reading` 三态（顶栏就是模式切换器，trailing 历史图标进列表、列表态切「返回 + 新对话」），不新增路由。列表分两段——「我的对话」点开**恢复续接**、「孩子的对话」点开**只读回放**（行带「只读」徽标、回放态底栏说明原因）：后者不是 UX 取舍，是后端语义（家长拿孩子的 `session_id` 续接会另建会话并污染 prompt 历史）。读路径是**新开**的家长专属端点 `GET /assistant/conversations` + `/{id}`，**不与** `/ai/debug/conversations` 复用；折叠（哪些行算气泡）归服务端、卡片怎么画归前端（不违反 ADR-0042）。`reset()`（新对话）与 `resume()`（续接）都在 `assistantNotifier`；`Conversation.title` 在建会话时写首条用户消息截断 20 字、读出侧须回落 NULL。

令牌层（`frontend/lib/shared/theme/app_theme.dart`）：`AppBrutal` 撞色原色 + `onColor()` 合规前景配对 · `AppElevation` 描边宽度与无模糊硬阴影 · `AppSprings` 物理弹簧（**取代 `Curves.easeOutBack`**）· `SubjectMark` 学科几何标记。

**学科标识必须三重编码**：色相 + 明度差 + 几何标记（数学 ■ / 语文 ● / 英语 ▲），**禁止仅靠颜色区分学科**——语文与英语同属暖色系，在红绿色盲下会趋同。

> **迁移进行中**（ADR-0044）：token 层先行 + 试点，**禁止一次性全量重做**。未迁移页面仍走旧语义令牌，属预期状态，不必逐个「修正」。

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
- **架构评审**：`docs/agent-core-architecture-review.md`——**2026-09-11 快照**。其 §7 的 P0/P1/P2 建议均已关闭（P0 补 ADR → `docs/adr/` 现 0001–0048；P1 compaction → `app/features/assistant/repository.py`；P2 extension hooks → ADR-0035），§6 的「前端 SSE 逐帧渲染」后端侧已排除、前端代码层已消解（仅余真机验证）。读它时注意其结论是快照，不代表当前状态。
- **ADR 索引**：`docs/adr/` 已落地 0001–0048（含 0008/0012/0014/0015/0017/0019/0020/0021–0028/0030–0048）；仅 0006/0007/0009–0011/0013/0016/0018/0029 无文档。新增决策先补 ADR 再在代码中交叉链接引用。
- **平台 runner 未纳入版本控制**：`frontend/.gitignore` 第 20–25 行忽略 `android / linux / macos / web / windows / ios`，即**平台目录全是本机生成物**。改桌面窗口尺寸、原生权限、Info.plist 之类只在本机生效，`flutter create` 重新生成或换机器构建都会回退。要做持久改动必须先决定「纳入版本控制 or 打补丁脚本」。
