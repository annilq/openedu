# openedu · 项目长期约定

> 设计语言 / 令牌 / 设计原则的唯一事实源：`.impeccable.md`；决策：`docs/adr/0044–0053`；术语：`CONTEXT.md`。
> 本文件只留**实测数字 / 归因 / 操作纪律**；`.impeccable.md` 已写清的原则不在此重复。

## 0. 环境 / 命令 / 多会话
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）；`flutter analyze` 退出码常非 0 → 认输出 `No issues found!`。
- `flutter test` 必先关代理：`env no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同值 <sdk>/bin/flutter test`，否则报 `Invalid WebSocket upgrade request`。
- ⚠️ **禁跑 `dart format`**：本机 Dart tall style 与仓库不同版 → 118 个文件里 85 个被 refmt 成噪声 diff。手写保持风格，只靠 analyze。
- ⚠️ **多会话并行改共享文件**（`app_theme.dart`/`MEMORY.md`/`AGENTS.md`/`.impeccable.md`）：先 `git status` + 看 mtime；长文件**定点 Edit**，写完回读（本文件被并发整写覆盖过两次）。
- ⚠️ **`flutter test` 异常慢先查游离进程**：挂死探针占住 `build/test_cache` 锁 → 后续等锁假失败。`ps | grep flutter_tester` → kill + 删探针。
- ⚠️ **新增原生插件必须完整重跑 App**：Hot Restart 不补原生注册 → pigeon `PlatformException(channel-error)`，改代码修不了。判据：进程启动时间 vs `pubspec.lock` mtime。真含插件代码的是 `Contents/MacOS/<app>.debug.dylib`（`strings | grep -i pdfx`），60KB 的 `MacOS/<app>` 只是壳。
- ⚠️ **本机 `grep` 是 BSD 版，不支持 BRE 的 `\|` 交替**（那是 GNU 扩展）→ `grep "a\|b"` **静默返回空**，看着像「文件里没有」。一律 `grep -E "a|b"`；并且**`grep -c` 得 0 不能当作「没有 X」的证据**（要用 `Grep` 工具或 `grep -E` 复核）。本轮因此误判过两次。

## 1. 前端分层（ADR-0036/0037）
- AI 唯一入口 `assistantNotifierProvider` + `AssistantMessageList`；后端唯一端点 `POST /api/v1/assistant/chat`。业务字段不前端预填（subject 后端算、grade 取 JWT）。
- 单向 `main/ → features/* → shared/*`；`shared/` 不 import `features/`；`App*` 只给 `shared/widgets/`。相对 import `..` 越过 `lib/` 根时分析器「截断」不报错 → 层数自己数准。
- 各 feature 均有 repository（接口 `domain/repositories`、实现 `data/repositories`、组合根 `features/<f>/providers/`）；**刻意不建 datasource**。守卫 `test/feature_boundaries_test.dart`。

## 2. 视觉与控件的实测事实（取值 / 原则见 `.impeccable.md`）
- 描边三档禁裸数字：2 `AppElevation.borderWidth`（卡/弹窗/浮层）· 1.5 `borderWidthSm`（chip/徽标/题号）· 1 `borderWidthHairline`（顶栏底边/侧栏右缘/分隔线/`listRow`）。`Border.all` 默认 1px。
- ⚠️ **「白物体在纸底没边界」是头号陷阱**：`surfaceRaised` vs 纸底 `#FDFBF7` 仅 ~1.02 → **补描边而非加粗**。**输入框刻意留 1px**（与 `AppControl.inputStrut` 耦合，加粗裁字）。
- 空态统一 `AppEmptyState`（三态与 `AppError` 同骨架，ADR-0051）。**reduce-motion**：隐式动画不自动尊重系统设置，须 `reducedMotionOf(context) ? Duration.zero : …`；浮层阴影统一 `_floatingShadows()`（暗色返 `none`），**别写 `shadows: const []`**。
- **高度 = 触控锚点逐阶下推**：`heightLg` = 锚点 48；标准 = −`step`(8)；紧凑 = −2×`step`。调档只改锚点（`AppControl`）；`step` 不复用 `AppSpacing.sm`。
- ⚠️ **`ShadButton.height` 是「内容盒高」**，描边画在盒**外** → 可见高 = 值 + 2×描边宽（声明 32 **实测 40**）。换算收口 `AppControl.buttonContentHeight()`；只看声明值发现不了 → 守卫 `test/control_height_test.dart`。
- ⚠️ **图标按钮一律 `AppIconAction`、文字行内操作一律 `AppTextAction`**；`CupertinoButton` 的 `minSize` 44×44 是第三种高度权威，会撑高同行。
- ⚠️ **`ShadButton` 不可放进会压缩它的容器**（`Expanded`/固定宽）→ `RenderFlex overflowed`；并排按钮一律 `Wrap`。
- ⚠️ **`ShadCard` 比内容高时内容贴顶不居中**（实测卡片 44/内容 28 → 上 1 下 15）；钉高的调用点**自己包 `Center`**，别改 `AppCard`。
- ⚠️ **`Row(crossAxisAlignment: stretch)` 必须包 `IntrinsicHeight`**，否则无界高父级抛 `BoxConstraints forces an infinite height`；`Column(stretch)` 安全（守卫 `test/stretch_row_guard_test.dart`）。
- ⚠️ **两条语义色通道已接线**（2026-09-17 审计 + 落地）：① `SubjectMarkIcon`/`SubjectKey.mark`（`app_theme.dart:131-196`）**由 `_TagChip` 渲染**（`AppTags.subject` 返回的私有组件内部），三重编码是通的——**只读工厂函数就断言「零业务调用」是错的，会漏掉工厂返回的私有组件**；唯一真缺口是 `mastery_board.dart` 的纯色点，已改 `SubjectMarkIcon`。② 助手卡片 `_CardHeader` 已接类别色（cyan=待办/复习、magenta=错题/掌握，其余中性，守「单屏色相 ≤ 3」），前景走 `AppBrutal.onColor`。清单见 `.scratch/design-amplification-audit-2026-09-17.md`。
- **动效（批次 D 落地）**：`AppProgressBar` 有填充过渡（`TweenAnimationBuilder`，`begin == end` → **首帧直接落终值**，只有挂载后的值变化才过渡；`ShadProgress` 的 determinate 分支是裸 `FractionallySizedBox`，内部零动画）；`PopIn.delay` 已存在（`Timer` + dispose 取消，延迟期按 `fromScale` 全透明就位），错峰步长 `AppMotion.interaction * min(i, 4)`。
- ⚠️ **`reducedMotionOf` 事实源在 `shared/theme/app_theme.dart`**（不是 `app_motion.dart`）：主题层的隐式过渡也要读它，反向 import 会成 theme↔widgets 循环。**别用 `export ... show reducedMotionOf` 转出**——会让 6 个调用点的 `app_motion` import 全变 `unnecessary_import`（analyze 零 issue 硬要求）。守卫 `test/pop_in_stagger_test.dart` 静态断言 `disableAnimations` 只出现一次。

## 3. 自适应布局（ADR-0045）· 令牌表见 `AppLayout`
- `AdaptiveShell` 三档：紧凑 700 = 娃娃底栏 / 家长汉堡抽屉；中屏 = 侧栏单栏；≥1200 有 `detail` → `body | 发丝线 | detail`。
- ⚠️ **内容兜底必须 `Align(topCenter)` + `ConstrainedBox`，不可 `Center`**（竖向也居中 → 不足一屏的页面浮到屏幕中间）。守卫 `test/adaptive_shell_layout_test.dart`。
- ⚠️ **`Navigator.push` 的整页不在壳兜底范围内**（PracticeScreen / ExportPreviewPage / 家长端 AssistantChatPage）。**宽度一律走 `AppContentFrame`（全仓唯一出口，原 14 处手抄已清零，守卫 `test/content_frame_guard_test.dart`）；退路一律走 `AppPushedPage`（`showBack` 默认 true、`Shortcuts`+`Focus(autofocus)` 让 Esc 生效）**——别再每页手写 `AppTopBar(showBack:)`，默认 `false` + 桌面端无返回手势 = 锁死一屏（`ExportPreviewPage` 即此坑）。`AppContentFrame.alignment` 照抄原值（壳 topCenter / 壳内页 topLeft）；勿把「故意留在框外的兄弟节点」（`practice_review_view` 通栏底部行动条）一起钉窄。
- ⚠️ **`frontend/.gitignore:20–25` 忽略六个平台目录** → 原生 runner（含 minSize 800×600）不受版本控制。
- ⚠️ **浮层宽度令牌指「外框宽」**：`popoverTheme.padding` + 2px 描边在内容**之外** → 内容侧须减 `popoverChrome`（写 224 得 244）。`AppFocusableAction` **定义在 app_theme.dart**（放 shared/widgets 会成 theme↔widgets 循环）。守卫 `app_focusable_keyboard_test.dart` + `sidebar_header_layout_test.dart`。

## 4. 测试与截图探针
- ⚠️ **`toImage()` 与 `FontLoader` 前的 `readAsBytes()` 必须包 `tester.runAsync`**，否则 fake-async 区 await 永不返回 → 挂死 exit 137。真字形需 `assets/fonts/{Inter,NotoSansSC}.ttf`。「渲染 PNG 回看」是验证视觉修复的有效手段，用完立刻删探针。
- ⚠️ **`ShadApp.custom` 不传 `theme:` 走 shadcn 默认主题** → 量到与产品不符的数（**像产品缺陷，实为测试替身假象**）。看视觉/几何必传 `AppTheme.shadFor(false, mode, density)`。
- ⚠️ **`SizedBox(width: 2000)` 给不了 2000px 视口**（surface 默认 800×600 会裁 → 断点静默测错档）→ 用 `setSurfaceSize` + `addTearDown`。
- **`ShadCard` 的可见外框不是 `ShadDecorator`** → 找「子树里第一个 `Container` 且 `BoxDecoration && border != null`」。
- ⚠️ **widget 测试里不要直接调 pdfx 的 `PdfDocument.openData`**：无原生一侧时 Future **既不完成也不报错** → `flutter_tester` 挂死。走 `pdfDocumentOpenerProvider` 接缝注入抛错替身。
- ⚠️ **catch 掉的异常也要 `debugPrint` 留痕**（接住 + 友好文案会让控制台一句话没有，排障失去唯一线索）。
- ⚠️ **`pumpAndSettle` 只按「还有没有下一帧」推进**：悬挂的 `Timer` 不排帧 → 单靠它计时器永不触发（必须显式 `pump(delay)`）；**含不确定态 spinner 的子树它必然超时**（永远排下一帧）→ 用显式 `pump(时长)`。`AnimatedSwitcher` 退场在「整档时长 + 再一帧」处才摘节点，且 ticker 要等第一个 tick 才开始计时 → 测试推**两档时长**，不要写死「第几帧」。
- ⚠️ **`pumpWidget` 的根之上没有 MediaQuery 祖先** → 注入 reduce-motion 必须把 `MediaQuery` 放在 `CupertinoApp`/`ShadApp` **之内**（`home` 包 `Builder` + `copyWith(disableAnimations:)`，保留 size）；直接 `MediaQueryData(disableAnimations: true)` 会把 size 变成 `Size.zero`。

## 5. Git / 后端 / 长列表
- ✅ `git push origin main` 可通；⚠️ 常输出 `Everything up-to-date` 但其实已成功 → 以 `git ls-remote origin main` 比对 HEAD 为准。push 走环境代理（端口每会话变）。提交按**逻辑批次**拆、正文写「为什么」；`chore(memory):` 单独提交；`backend/.agents/` 未跟踪，别顺手 commit。
- **引擎失败归因**：`decrypt()` 解不开只返 `None`（**密文永不出门**）；`ToolUnsupportedError`(无 FC) vs `ProviderRequestError`(厂商拒绝) 落点 `agent_core/adapters/genkit.py#classify_failure`；禁 `except Exception` 把引擎失败抹成「请添加模型」。`SECRET_KEY` 缺失 → 随机密钥落盘 + 启动冒烟（ADR-0041）。
- 工具 schema strict（ADR-0040）：可省略参数要有缺席编码（`""`/`0`/枚举含 `NO_FILTER="all"`）。助手分流（ADR-0043）：`acc` 只收 TEXT，泄露判据强弱两档。残留：`deepseek-v4-flash` 多轮 tool loop 退化成 XML → 对策**减跳数**。
- pytest 前 `cd backend && mv .env .env.hidden`（跑完恢复）；用 `.venv/bin/ruff`、`.venv/bin/pytest`；偶发 `Sensitive content approval timed out` → 重跑。`Resource<T>` 迁移未完成。守卫 `tests/ai/`。
- **长列表（ADR-0053）**：取数一律 **keyset 游标**（非 offset，新数据插顶部会错位），原语 `backend/app/core/pagination.py`，前端 `CursorPage<T>`（`lib/shared/presentation/paging.dart`）；⚠️ 追加在途时换查询条件会拼回旧页 → await 后重读最新 state 再合并；⚠️ 两列**不用 `SliverGrid`**（`childAspectRatio` 钉死行高会裁卡）→ `Row`+`Expanded`，阈值 `listTwoColumnMin 1048`；⚠️ 毕业软删后**每处**读错题都要加 `graduated_at IS NULL`；归档三套语义禁共用（题库 `archived_at` / 任务按月分段 / 错题 `graduated_at`）；迁移走启动期偏幂等 DDL，不引入 alembic。
