# openedu · 项目长期约定

> **设计语言/令牌的唯一事实源是 `.impeccable.md`（+ `docs/adr/0044–0047`）**，术语见 `CONTEXT.md`。
> 本文件只留「不写下来就会重犯」的操作性约定；**规则本身不要在这里再抄一份**（超限会被截断，截掉的正是尾部）。

## 0. 环境 / 命令 / 多会话纪律
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）；`flutter analyze` 退出码常非 0 → 认输出 `No issues found!`。
- `flutter test` 必先关代理：`env no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同值 <sdk>/bin/flutter test`，否则报 `Invalid WebSocket upgrade request`。
- ⚠️ **禁跑 `dart format`**：本机 Dart 3.13 的 tall style 与仓库风格不同版 → 会把 118 个文件里的 85 个 refmt 成噪声 diff。手写保持风格，只靠 analyze 校验。
- ⚠️ **本仓常年多会话并行改同一批文件**（`app_theme.dart`/`MEMORY.md`/`AGENTS.md`/`.impeccable.md`）：先 `git status` + 看 mtime；**「实测 + 归因」前确认目标文件没被别的会话改过**；长文件定点替换，写完回读校验（本文件被并发整写覆盖过两次）。
- ⚠️ **`flutter test` 异常慢先查游离进程**：挂死探针（`toImage`/`readAsBytes` 未包 `runAsync`）占住 `build/test_cache` 锁 → 后续等锁 + 假失败。`ps | grep flutter_tester` → kill + 删探针。

## 1. 前端分层（ADR-0036/0037）
- AI 唯一入口 `assistantNotifierProvider` + `AssistantMessageList`（家长端浮球 push 整页 `AssistantChatPage`，ADR-0047；娃娃端同页作页签）；后端唯一端点 `POST /api/v1/assistant/chat`。业务字段不前端预填（subject 后端算、grade 取 JWT）。
- 单向 `main/ → features/* → shared/*`；`shared/` 不 import `features/`；`App*` 只给 `shared/widgets/`。相对 import `..` 越过 `lib/` 根时分析器「截断」不报错 → 层数自己数准。
- 9 feature 均有 repository（接口 `domain/repositories`、实现 `data/repositories`、组合根 `features/<f>/providers/`）；**刻意不建 datasource**。`ResourceNotifier<T>` 只吃 `Future<T> Function()`，解析在 repository；请求 DTO 归 domain。守卫 `test/feature_boundaries_test.dart` R1–R5（棘轮，已清零）。

## 2. 视觉语言（ADR-0044）· 取值与原则见 `.impeccable.md`
- **描边三档（`AppElevation`，禁裸数字）**：2 = 内容物体（卡/弹窗/浮层）；1.5 `borderWidthSm` = 密集小色块（chip/徽标/题号）；1 `borderWidthHairline` = 结构边与安静重复元素（顶栏底边/侧栏右缘/分隔线/`listRow`）。同屏结构边必须同档；`Border.all` 默认 1px，要别的宽度必须显式写。
- **头号陷阱「白物体在纸底没边界」**：`surfaceRaised` 白 vs 纸底 `#FDFBF7` 仅 ~1.02 → `outline` 换墨黑后没写边的组件就失去边界。**补描边而非加粗**（墨黑边已 ~19:1）。**输入框刻意留 1px**（与 `AppControl.inputStrut` 三向耦合，加粗裁字）。
- **`labelLarge` 前景色是 `onCta`，只能用于按钮文字**；拿它当卡片标题会白字隐形。标题/正文分别用 `titleSmall`/`titleMedium`/`body*`，显式给 `onSurface`/`onSurfaceVariant`。
- **空态统一走 `AppEmptyState`**：首次空必须给「下一步做什么」出口；完整版居中（`AppLayout.contentEmpty`）、密集区用 `AppEmptyState.inline`；三态切换时与 `AppError` 同骨架，避免「加载/错误/空」跳版式（ADR-0051）。
- **reduce-motion / 阴影两坑**：隐式动画（`AnimatedContainer`/shimmer）**不自动尊重**系统设置，须 `duration: reducedMotionOf(context) ? Duration.zero : ...`；浮层阴影统一 `_floatingShadows()`（暗色返 `none`），**别写 `shadows: const []`** 抹掉它。

## 3. 控件高度与几何（ADR-0044 增补）
- **高度 = 以触控锚点逐阶下推**：`heightLg` = **锚点 48**（Material 48dp ∩ HIG 44pt）；标准档 = 锚点 − `step`(8)；紧凑档 = 锚点 − 2×`step`。**调档位只改锚点**（取值表在 `AppControl`）；`step` 独立常量，**不复用 `AppSpacing.sm`**。
- ⚠️ **`ShadButton.height` = 「内容盒高」而非可见高**：描边由 `ShadDecorator` 画在盒**外** → 可见高 = 传入值 + 2×描边宽（声明 32 **实测渲染 40**，即「输入框 32 按钮 40」的来源）。换算收口 `AppControl.buttonContentHeight()`。**只看声明值发现不了** → 守卫 `test/control_height_test.dart` 守的是**实测 `getSize`**。
- ⚠️ **图标按钮一律 `AppIconAction`、文字行内操作一律 `AppTextAction`**，别用 `CupertinoButton(padding: zero)`——它默认 `minSize` 44×44，是第三种高度权威、会撑高同行；更糟的是它把 child 套进 Cupertino 默认 `DefaultTextStyle`，强制使用系统字体覆盖内嵌的 Inter + Noto Sans SC，中文变糙。命中区分两档：同行并排 = `AppIconAction`/`AppTextAction`；输入框内部（`app_inputs.dart` 眼睛）= `AppControl.heightSmOf` 方形。
- ⚠️ **`ShadButton` 不可放进会压缩它的容器**（`Expanded`/固定宽）→ 文字不收缩报 `RenderFlex overflowed`；并排按钮一律 `Wrap`。
- ⚠️ **`ShadCard` 比内容高时内容贴顶、不垂直居中**：内部固定 `Row(crossAxisAlignment: start)` + `Column(mainAxisSize: min)`，内容只按自身高度收缩并贴上沿。内容自撑高度时看不出；用 `SizedBox(height:)` 钉高卡片时（侧栏头部触发器钉到 `tapTarget`）差值全落下沿——实测卡片 44 / 内容 28 → 上 1 下 15、中心偏上 7px。钉高的调用点**自己包一层 `Center`**，别去 `AppCard` 内部居中（会动全站每张卡）。
- ⚠️ **`Row(crossAxisAlignment: stretch)` 必须包 `IntrinsicHeight`**：左色条行卡落在无界高父级（`Column`/`ListView`/`CustomScrollView`）会抛 `BoxConstraints forces an infinite height`；`Column(stretch)` 是横向拉伸、安全（守卫 `test/stretch_row_guard_test.dart`）。

## 4. 自适应布局（ADR-0045）· 令牌表见 `AppLayout`
- 布局尺寸**全收口 `AppLayout`（app_theme.dart）**，禁裸数字：断点 / 侧栏宽 / 内容宽度语义档 / master-detail 配比 / 触控目标都在那里。`AdaptiveShell` 三档：紧凑 = 娃娃底栏 / 家长汉堡抽屉；中屏 = 侧栏单栏；大屏（≥1200）有 `detail` → `body | 发丝线 | detail`。
- ⚠️ **内容兜底必须 `Align(topCenter)` + `ConstrainedBox`，不可 `Center`**（`Center` 竖向也居中 → 不足一屏的页面浮到屏幕中间）。守卫 `test/adaptive_shell_layout_test.dart`。
- ⚠️ **`Navigator.push` 的整页不在壳兜底范围内**，须自带宽度约束（`PracticeScreen`→`PracticeReviewView`、家长端 `AssistantChatPage`）。
- ⚠️ **`frontend/.gitignore:20–25` 忽略六个平台目录** → 原生 runner（含 minSize 800×600）不受版本控制，`flutter create` 重生成会回退。

## 5. 交互三态与浮层（ADR-0046）· 三态画法见 `.impeccable.md §Interaction`
- **「选中」全站只有一种语言**：无描边药丸 + `surfaceActive` + accent 图标。**不用带描边的卡片表示选中**——放在带描边的浮层里就是盒中盒（需要边界的是容器，不是列表项自身）。悬停一律 `AppFocusableAction(hoverHighlight: true)`（缺省 false），**禁手搓 `StatefulWidget + MouseRegion`**。
- **任何可点区域必须进焦点树，裸 `GestureDetector` 是 bug**；焦点环用 `foregroundDecoration` + `accent`（不参与布局）。`AppFocusableAction` **定义在 app_theme.dart**（放 shared/widgets 会成 theme↔widgets 循环）。守卫 `test/app_focusable_keyboard_test.dart`。
- ⚠️ **浮层宽度令牌指「外框宽」**：`popoverTheme.padding` 与 2px 描边在内容**之外**，内容侧须减 `popoverChrome`（写 224 得 244）。结构令牌 `sidebarMenuWidth`（侧栏宽 − 2×`sm`）/`menuMaxHeight 400`。
- ⚠️ **浮层锚点一律显式 `ShadAnchor`，别用默认 `ShadAnchorAuto`**：默认 `bottomCenter↔bottomCenter` = 相对触发卡居中且底层再居中一次 → 触发卡比浮层窄时两侧溢出、左溢被屏幕左缘钳住（实测外框 0–244 vs 侧栏 240）。展开/抽屉 = `ShadAnchor(offset: Offset(0, xs))`；轨态 = `overlayAlignment: Alignment.topRight`（向右飞出，不挡导航图标）。**命名与直觉相反**：`childAlignment` 作用于浮层、`overlayAlignment` 作用于触发卡。轨态降级而非隐藏（`SidebarCollapseScope.maybeOf`，抽屉无 scope → 展开）。守卫 `test/sidebar_header_layout_test.dart`。

## 6. 测试与截图探针
- ⚠️ **`toImage()` 在 `testWidgets` 里必须包 `tester.runAsync`**，否则 fake-async 区 await 永不返回 → 挂死 exit 137；**`FontLoader` 前的 `File.readAsBytes()` 同样要包**。真字形需加载 `assets/fonts/{Inter,NotoSansSC}.ttf`。「渲染 PNG 回看」是验证视觉修复的有效手段，用完立刻删探针。
- ⚠️ **`ShadApp.custom` 不传 `theme:` 走 shadcn 默认主题**（按钮竖向 padding 8、浮层内边距 h12/v6）→ 几何断言量到与产品不符的数，`maxHeight` 还会把 CTA 压到 12px 裁切（**像产品缺陷，其实是测试替身假象**）。看视觉/几何的测试必须传 `AppTheme.shadFor(false, mode, density)`。
- ⚠️ **`SizedBox(width: 2000)` 给不了 2000px 视口**（surface 默认 800×600 会裁 → 断点静默测错档）→ 用 `tester.binding.setSurfaceSize(Size(w,h))` + `addTearDown`。
- **`ShadCard` 的可见外框不是 `ShadDecorator`**（搜它找不到元素，探针会崩）→ 找「子树里第一个 `Container` 且 `decoration is BoxDecoration && border != null`」。

## 7. Git
- ✅ `git push origin main` 可通；⚠️ 常输出 `Everything up-to-date` 但其实已成功，以 `git ls-remote origin main` 比对 HEAD 为准。push 走环境代理（端口每会话变），失败先 `curl -x $HTTPS_PROXY https://github.com` 探活。
- 提交按**逻辑批次**拆、正文写「为什么」；`chore(memory):` 可单独提交。`backend/.agents/` 未跟踪，别顺手 commit。多会话在共享文件重叠而无法逐 hunk 拆时，合并单 commit、信息按 ADR 分节。

## 8. 后端
- 密钥/引擎：`decrypt()` 解不开只返 `None`（密文永不出门）；`ToolUnsupportedError`(无 FC) vs `ProviderRequestError`(厂商拒绝) 落点 `agent_core/adapters/genkit.py#classify_failure`；禁 `except Exception` 把引擎失败抹成「请添加模型」。`SECRET_KEY` 缺失时随机密钥落盘 `backend/.secret_key` + 启动冒烟（ADR-0041）。
- 工具 schema strict（ADR-0040）：可省略参数要有缺席编码（`""`/`0`/枚举含 `NO_FILTER="all"`）。助手分流（ADR-0043）：`TextDelta.kind`、`acc` 只收 TEXT，泄露判据强弱两档且强标记不绑工具名。残留：`deepseek-v4-flash` 多轮 tool loop 退化成 XML → 对策**减跳数**。
- pytest 前 `cd backend && mv .env .env.hidden`（跑完恢复），用 `.venv/bin/ruff`、`.venv/bin/pytest`；偶发 `Sensitive content approval timed out` → 重跑。`Resource<T>` 迁移未完成；`docs/adr/` 现 0001–0051。守卫 `tests/ai/`。

## 9. 长列表：分页 / 密度 / 归档（ADR-0053，P0–P2 已落地）
- **取数一律 keyset 游标**（非 offset）：新数据插顶部，offset 会错位。原语 `backend/app/core/pagination.py`；排序键 `(coalesce(created_at, epoch) DESC, id DESC)`。前端统一信封是泛型 `CursorPage<T>`（`TaskPage` 带 counts / `WrongQuestionPage` 带 graduated_total），**不是**扁平 `PageResp`；状态机 `lib/shared/presentation/paging.dart`。
- ⚠️ **追加在途时换查询条件会拼回旧页**：await 后必须重读最新 state 再合并，单看「类型是 Loaded」挡不住。
- ⚠️ **两列不用 `SliverGrid`**：`childAspectRatio` 钉死行高会裁掉随内容变高的卡 → 分行 `Row`+`Expanded`。阈值 `AppLayout.listTwoColumnMin 1048`，上限 2 列。
- **归档三套语义，禁止共用 `archived` 字段**：题库=家长弃用（`archived_at`，可逆）；任务=时间久远（不加字段，按月分段）；错题=系统判定掌握（`graduated_at` 软删除，不再是 `session.delete`）。
- ⚠️ **毕业软删除后每处读错题都要加 `graduated_at IS NULL`**（复习到期队列 / 掌握度统计 / 任务错题本），漏一处毕业的题继续到期。
- 迁移走**启动期偏幂等 DDL**（SQLite `PRAGMA table_info`→`ADD COLUMN`、PG `ADD COLUMN IF NOT EXISTS`、索引 `CREATE INDEX IF NOT EXISTS`），**不引入 alembic**。
