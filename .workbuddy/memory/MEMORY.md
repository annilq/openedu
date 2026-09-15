# openedu · 项目长期约定

## 前端分层（ADR-0036/0037）
- AI 唯一入口 `assistantNotifierProvider`+`AssistantMessageList`（家长端浮动按钮 push 整页 `AssistantChatPage`，ADR-0047；娃娃端同页作为页签）；后端唯一端点 `POST /api/v1/assistant/chat`。业务字段不前端预填（subject 后端算、grade 取 JWT）。
- 单向 `main/ → features/* → shared/*`；`shared/` 不得 import `features/`；`App*` 只给 `shared/widgets/`。
- 9 feature 全有 repository（`domain/repositories` 接口 + `data/repositories/*_impl` + `features/<f>/providers/` 组合根）；**刻意不建 datasource**。守卫 `test/feature_boundaries_test.dart` R1–R5（R4/R5 棘轮，已清零）。
- `ResourceNotifier<T>` 只吃 `Future<T> Function()`，解析在 repository；`decodeList/decodeMap` 在 `shared/utils/json_decode.dart`。请求 DTO 归 domain。

## Dart / Flutter 陷阱
- ✅ `flutter test` 可跑，**先关代理**：`env no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同值 <sdk>/bin/flutter test`（否则 flutter_tester 的本地 WebSocket 走代理，报 `Invalid WebSocket upgrade request`）。
- **Flutter SDK = `/Users/annilq/Documents/fulttersdk/flutter`**（不在 PATH）。`flutter analyze` 很快但退出码常非 0 → 看输出 `No issues found!`。
- ⚠️ **不要跑 `dart format`**：本机 SDK 是 Dart 3.13，其格式化器（tall style）与仓库既有风格**不是同一版**——`dart format lib/` 会改写 118 个文件里的 **85 个**。跑了就会把你（和别人进行中）的改动一起 refmt 成大段噪声 diff。手写保持既有风格，正确性只靠 `flutter analyze` 校验。
- ⚠️ **本仓库可能同时有多个会话在改**（2026-09-16 实测：助手改整页 ADR-0047 与 `AppControl` 高度阶梯 32→40 并行，彼此都改到了 `app_theme.dart` / `AGENTS.md` / `MEMORY.md`）。动手前先看 `git status` + 目标文件 mtime；**任何「实测数据 + 归因」之前，先确认目标文件没被另一个会话改过**；编辑长文件用定点替换而非整文件重写。
- ⚠️ **`Row(crossAxisAlignment: stretch)` 必须包 `IntrinsicHeight`**：左色条行卡（左色条+`Expanded`）落在 `Column`/`ListView`/`CustomScrollView`（高度无界）里会抛 `BoxConstraints forces an infinite height`（`h=Infinity`）。`Column(stretch)` 是横向拉伸、**安全**。守卫 `test/stretch_row_guard_test.dart`（棘轮）。详见 ADR-0044。
- ⚠️ **`ShadButton` 不可放进会压缩它的容器**（`Expanded`/固定宽）：内部文字不收缩 → `RenderFlex overflowed`。并排按钮一律 `Wrap`。主题层按钮水平 padding 已各减 2 抵消 2px 描边增量。
- 相对 import `..` 越过 `lib/` 根时分析器「截断」不报错 → 层数自己数准。

## 视觉语言：新粗野（ADR-0044）
- 高饱和撞色 + 2px 墨黑描边 + 无模糊硬阴影 + 弹簧动效（弃 `Curves.easeOutBack`）。色块=**强调件**（≤卡片 40%、单屏大色块 ≤3 色相、列表行禁整行填充）；亮块配墨黑字、深块配白字（WCAG AA 实测）。
- 列表行用 `AppCard.listRow`（发丝边、无阴影），独立卡用 `AppCard`（2px+硬阴影）；学科三重编码 `AppTags.subject`+`SubjectMarkIcon`；新增 `AppBrutal`/`AppElevation`/`AppSprings`/`AppBrutalButton`；动效 `AppMotion`（PopIn/PressScale/ConfettiBurst，均尊重 reduce-motion）。
- **描边三档（`AppElevation`，禁写裸数字）**：2 `borderWidth` = 内容物体（卡/弹窗/浮层）；1.5 `borderWidthSm` = 密集列表小色块（chip/徽标/题号）；1 `borderWidthHairline` = 结构边与重复安静元素（顶栏底边/侧栏右缘/分隔线/`listRow`）。同屏结构边必须同档。
- **「白色物体在纸底没有边界」是头号陷阱**：`surfaceRaised` 纯白 vs 纸底 `#FDFBF7` 对比仅 ~1.02、`surfaceSunken` vs 白卡 ~1.09 —— 原先靠浅灰 `outline` 兜底，`outline` 换墨黑后**没写边的组件就失去边界**。修法是**补描边而非加粗**（墨黑边已有 ~19:1）。另：`Border.all(color:)` 默认 1px，必须显式写宽。
- **输入框描边刻意保持 1px**：与 `AppControl.inputStrut` 的 `heightOf - 4`（= 2×1px 边 + 2px 内部预留）及 tight 高度三向耦合，加粗会裁字。
- **控件高度（`AppControl`）= 以触控锚点逐阶下推**：主行动档 `heightLg` 为**锚点**（48，同时满足 Material 48dp 与 HIG 44pt），标准档 = 锚点 −`step`(8)，紧凑档 = 锚点 −2×`step`。现取值（紧凑/标准/主行动）：parent·compact **32/40/48**、parent·normal 40/48/56、child·compact 40/48/56、child·normal 48/56/64。**旧标准档 32 是桌面鼠标惯例**（Ant Design/Element Plus），低于所有触控规范，已废弃；38 是 Bootstrap 副产物、非令牌，不采用。`step` 独立常量，**不复用 `AppSpacing.sm`**。
- ⚠️ **`ShadButton.height` 是「内容盒高」而非可见高**：描边画在盒外 → 可见高 = 传入值 + 2×描边宽（声明 32 实测 40，历史上就是这么积累成「输入框 32 按钮 40」）。无描边变体（ghost/link）内容盒高即可见高，主题须另给一套尺寸。守卫 `test/control_height_test.dart`（守阶梯结构 + **实测**渲染高）。
- ⚠️ **`CupertinoButton(padding: zero, child: Icon)` 是第三种高度权威**（默认 minSize 44×44）会撑高同行 → 用 `AppIconAction`（命中区 = 标准档；内层走 `AppFocusableAction` 保键盘可达 + `semanticLabel`）。
- **隐式动画**（`AnimatedContainer`/`AnimatedPositioned`/骨架 shimmer）**不会自动尊重 reduce-motion**，须显式 `duration: reducedMotionOf(context) ? Duration.zero : ...`。
- 浮层阴影统一走 `_floatingShadows()`（暗色返回 `AppElevation.none`）；**别写 `shadows: const []`** 把 `_surfaceDecoration` 算好的阴影抹掉。
- 单一事实源 `.impeccable.md`；术语见 `CONTEXT.md` §设计语言。
- **铺开状态（2026-09-15 第三轮）**：页面层与 `shared/widgets` **均已铺完**。无需改：`home_screen`（组合根零裸样式）、`child_mastery_screen`、`mastery_board`、`app_toast`（本就是实心块）。待真机：① 选项块选中态 2px+硬阴影在 4 块同屏下是否过吵；② 发丝结构边与 2px 内容边同屏的粗细差观感。

## 自适应布局（ADR-0045）
- 布局尺寸**全部收口 `AppLayout`（app_theme.dart，紧邻 AppSpacing）**，禁写裸数字：断点 `compactMax 700` / `largeMin 1200`；侧栏 `sidebarExpanded 240` / `sidebarCollapsed 64`。
- 内容宽度按语义六档：`contentWide 1080` / `contentReading 820` / `contentCard 520` / `contentNarrow 480` / `contentEmpty 440` / `contentFloat 380`。master-detail 用配比 `masterFlex 5` / `detailFlex 8`。
- `AdaptiveShell` 三档：紧凑=娃娃底栏 / 家长汉堡抽屉；中屏=侧栏单栏；大屏（≥1200）有 `detail` → `body | 发丝线 | detail` 双栏。
- ⚠️ **内容区兜底必须 `Align(alignment: Alignment.topCenter)` + `ConstrainedBox`，不可用 `Center`**：`Center` **竖向也居中**，内容不足一屏的页面会浮到屏幕中间，与本仓「内容贴顶自然布局」口径冲突。守卫 `test/adaptive_shell_layout_test.dart`。
- ⚠️ **`Navigator.push` 的整页不在壳的兜底范围内**，必须自带宽度约束（全仓唯一：`PracticeScreen` → `PracticeReviewView`）。新增整页路由时记得自查。
- 键盘可达：`AppFocusableAction`（**定义在 app_theme.dart**，不是 shared/widgets 会成 theme↔widgets 循环）——焦点环用 `foregroundDecoration` + `scheme.accent`（不参与布局、不跳尺寸）；`AppCard` 键盘激活经 `onPressedChanged` 补一次按压反馈；App 根挂 `FocusTraversalGroup(ReadingOrderTraversalPolicy)`。守卫 `test/app_focusable_keyboard_test.dart`。
- ⚠️ **`frontend/.gitignore:20–25` 把六个平台目录全部忽略**，原生 runner（含 macOS/Windows/Linux 的 minSize 800×600）**不受版本控制**，`flutter create` 重生成会回退。
- ⚠️ 测试坑：`SizedBox(width: 2000)` 给不了 2000px 视口（test surface 默认 800×600 会裁，断点静默测错档）→ 必须 `tester.binding.setSurfaceSize(Size(w,h))` + `addTearDown`。

## 交互三态：选中 / 悬停 / 焦点（ADR-0046）
- **「选中」全站只有一种语言**：无描边药丸 + `surfaceActive` + accent 图标（`AppSidebarItem` / 浮层选项 / `_DrawerItem`）。**不要用带描边的卡片表示选中**——放在已带描边的浮层里就是盒中盒。判据：列表项自身不需要边界，需要边界的是它所在的容器。
- **悬停统一走 `AppFocusableAction(hoverHighlight: true)`**（缺省 false）：底色 `surfaceHover`（比选中浅一档），画在**底层** `decoration`，子项自带底色会盖住它 → 悬停/选中天然分层。**禁再手搓 `StatefulWidget + MouseRegion`**。
- 焦点环 `foregroundDecoration` + `accent` + `borderWidth`（不参与布局）。**任何可点区域必须进焦点树，裸 `GestureDetector` 是 bug**。图标按钮命中区分两档：**与控件同行并排**用 `AppIconAction`（标准档），**输入框内部**用 `AppControl.heightSmOf` 方形命中区（同 `app_inputs.dart` 眼睛按钮）。
- **`sidebarTop` 内边距由宿主给，组件自身零外边距**（`AppLayout.sidebarHeaderPadding` LTRB 8/12/8/4；左缘必须 = 导航药丸左缘）。结构尺寸令牌：`tapTarget 44` / `sidebarMenuWidth`(= 侧栏宽 − 2×`sm`) / `popoverChrome`(浮层外框超出内容的 20px) / `menuMaxHeight 400`。
- ⚠️ **浮层宽度令牌指的是「外框宽」**：shadcn 的 `popoverTheme.padding` 与 2px 描边都包在内容**之外**，内容侧必须减 `AppLayout.popoverChrome`（写 224 会得到 244）。
- ⚠️ **浮层锚点一律显式 `ShadAnchor`，别用 shadcn 默认的 `ShadAnchorAuto`**：默认是 `bottomCenter↔bottomCenter` = 相对触发卡**水平居中**且底层再居中一次 → 触发卡比浮层窄时两侧溢出、左溢部分被屏幕左缘钳住（实测外框 0–244 vs 侧栏 240）。展开/抽屉 = `ShadAnchor(offset: Offset(0, xs))`（下方、左缘齐平）；轨态 = `overlayAlignment: Alignment.topRight`（向右飞出，不挡导航图标）。**命名与直觉相反**：`childAlignment` 作用在浮层、`overlayAlignment` 作用在触发卡。
- **轨态（侧栏收起）降级而非隐藏**：信息不能丢（家长要能看出当前娃娃）。`SidebarCollapseScope.maybeOf`（抽屉无 scope → 视为展开）。
- ⚠️ **`ShadApp.custom` 不传 `theme:` 走 shadcn 默认主题**（按钮竖向 padding 8，本仓是 0）→ `ShadButton` 的 `maxHeight` 会把 CTA 文字压到 12px 裁切，**看起来像产品缺陷其实是测试替身假象**。看视觉/几何的测试必须传 `AppTheme.shadFor(false, mode, density)`。
- ⚠️ **`RenderRepaintBoundary.toImage()` 在 `testWidgets` 里必须包 `tester.runAsync`**，否则 fake-async 区 await 永不返回 → 进程挂死（exit 137）。配 `FontLoader` 加载 `assets/fonts/{Inter,NotoSansSC}.ttf` 才有真字形（Lucide 图标字体没加载 → 豆腐块）。"渲染 PNG 回看"是验证视觉修复的有效手段。
  - 同理：**`FontLoader` 前的 `File(...).readAsBytes()` 也是真 IO**，同样要包 `tester.runAsync`（只包 `toImage` 不包字体加载 → 一样挂死 137）。
  - 挂死的探针会**占住 `build/test_cache` 锁**，让后续 `flutter test` 一直等锁甚至假失败 → 之后立刻删临时探针文件。

## Git
- ⚠️ **本仓可能同时有多个会话在跑**（2026-09-16 实际发生过：两个会话同日并行改 `app_theme.dart` / `MEMORY.md`）。后果：① 对方改文件后你的实测数据会「看起来是 bug」——**归因前先确认目标文件 mtime**；② 并发 `Edit`/`Write` 同一文件会互相覆盖（我的 MEMORY 条目被整体抹掉过一次）。**动手前先 `git status` 看有没有别人未提交的改动。**
- ✅ `git push origin main` 可通；⚠️ 常输出 `Everything up-to-date` 但其实**已成功**，以 `git ls-remote origin main` 比对 HEAD 为准。push 走环境代理（端口每会话变），失败先 `curl -x $HTTPS_PROXY https://github.com` 探活再重试。
- 提交按**逻辑批次**拆，正文写「为什么」；`chore(memory):` 可单独提交。`backend/.agents/` 未跟踪，**别顺手 commit**。

## 后端（引擎 / 密钥 / schema / 泄露）
- `decrypt()` 解不开只返 `None`（**密文永不出门**）；`ToolUnsupportedError`(无FC) vs `ProviderRequestError`(厂商拒绝) 落点 `agent_core/adapters/genkit.py#classify_failure`；禁用 `except Exception` 把引擎失败抹成「请添加模型」。
- `SECRET_KEY` 未配置时生成随机密钥落盘 `backend/.secret_key`，启动期冒烟（ADR-0041）。`env_file`/`DATABASE_URL` 均 CWD 无关。
- 工具 schema strict（ADR-0040）：可省略参数要有缺席编码（`""`/`0`/枚举含 `NO_FILTER="all"`），归一收口 `query/tools/_shared.py`。守卫 `tests/ai/test_query_tools_contract.py`。
- 助手推理/正文分流（ADR-0043，已修）：`TextDelta.kind`，`acc` 只收 TEXT；协议泄露判据分**强/弱两档**，强标记命中即判、**不得绑定工具名**。守卫 `tests/ai/test_tool_loop_bounds.py`。残留：默认模型 `deepseek-v4-flash` 多轮 tool loop 会退化成 XML 文本 → 对策是**减跳数**（`child_name` 一跳直达）。

## 后端测试 / 待办
- pytest 前 `cd backend && mv .env .env.hidden`（避 broker 读 .env），跑完恢复；用 `.venv/bin/ruff`、`.venv/bin/pytest`。偶发 `PermissionError: Sensitive content approval timed out` → 重跑即可。
- `Resource<T>` 迁移未完成（Models/DueReview/Review/Bank/Children 仍自建四态）；AI 集成层待业务闭环后整层重构；③/⑤ 重构无 ADR。`docs/adr/` 现 0001–0047。
- 已知未修小瑕疵：无。
