# 自适应布局三档断点、内容宽度令牌与键盘可达性

确立前端自适应布局的单一事实源：**三档断点 + 内容宽度令牌 + 桌面键盘可达性**。

补的是 ADR-0014（响应式导航壳）留下的三处缺口：① 壳只有「紧凑 / 非紧凑」两档，iPad 与桌面完全共用同一套布局；② 内容区无宽度上限，大屏下列表被无限拉宽（宽度全靠各页面自觉，实测 6 个页面完全没约束）；③ 可点区域一律是裸 `GestureDetector`，**不进焦点树**——桌面端 Tab 跳不过去、Enter 点不动。

## 决策

- **布局决策只基于「可用宽度」，禁止按设备形态分支。** 一律读 `LayoutBuilder` 的 `constraints.maxWidth`；禁止 `MediaQuery.orientationOf` / `OrientationBuilder`，禁止 `isTablet` / `isDesktop` 这类硬件判定，也禁止 `MediaQuery.of(context).size.width`（那是**屏宽**，不是可用宽度）。理由：Flutter 应用跑在可缩放窗口、多窗口与画中画里，**设备形态不等于可用空间**；而且 master-detail 的详情栏比窗口窄得多，按屏宽算出来的约束必然溢出。

- **三档断点收敛到 `AppLayout`，值是 700 / 1200。**
  - `< compactMax (700)` **紧凑**：娃娃端底部导航；家长端顶部汉堡 + 左抽屉。
  - `[700, largeMin)` **中屏**：侧栏 240 ↔ 64 可收起。
  - `≥ largeMin (1200)` **大屏**：同上，且 `AdaptiveShell.detail` 非空时展开 master-detail 双栏。
  - **订正**：`adaptive_shell.dart` 的类注释此前写「在三档断点间切换」，但代码只有 compact / 非 compact 两个分支。现在注释与实现一致。

- **内容宽度收敛到 `AppLayout` 的六个语义档，禁止再写裸数字。** 原先散着 1080 / 820 / 520 / 480 / 440 / 380 六个魔法值、19 处调用，无「哪一档才是我该用的」依据。现在按语义命名：`contentWide 1080`（家长端工作区）/ `contentReading 820`（答题阅读区）/ `contentCard 520`（居中结果卡）/ `contentNarrow 480`（登录、表单对话框）/ `contentEmpty 440`（空态 / 提示卡）/ `contentFloat 380`（浮层）。**取值一律沿用原数字**，本次只做收敛命名，不改观感。
  - 后续：`contentFloat` 已随浮层消失被删除（家长端 AI 助手改整页，见 ADR-0047），宽度档由六档变五档。

- **宽度上限在 `AdaptiveShell` 统一兜底，不在页面各写一遍。** 壳的内容区包 `Align(alignment: topCenter)` + `ConstrainedBox(maxWidth: contentWide)`。一处改动覆盖 6 个此前完全无约束的页面（`child_home` / `profile_screen` / `practice_screen` / `review_screen` / `child_form_screen` / `parent_tasks_view`）。
  - 必须包一层对齐，而不是只加 `maxWidth`：只加 `maxWidth` 会让内容贴左、右侧留下一条突兀空带。
  - **用 `Align(topCenter)` 而不是 `Center`**：`Center` 的竖向居中会把「内容不足一屏」的页面（表单、错误态）整块浮到屏幕中间，而本仓明确要「内容贴顶自然布局」（`adaptive_shell.dart` 原注释）。`Align` 横向传下松约束，贪心子项（ListView / scroll view）仍取满 `contentWide`，与 `Center` 等效。由 `test/adaptive_shell_layout_test.dart` 最后一例守住。
  - 页面需要更窄时自带更强的 `ConstrainedBox`（答题 820 / 登录 480），**内层更紧者生效**，不会互相打架。
  - 紧凑宽度下 1080 不生效，等价于无包裹——手机与小平板排布**零变化**。
  - **例外：`PracticeScreen` 由 `Navigator` 推入，不在壳的兜底范围内**，必须自带约束（其 `PracticeReviewView` 是本仓唯一漏掉的页面，已补）。新增 `Navigator.push` 的整页时，记得同样自查。

- **master-detail 的宽度配比用 Flex（5 : 8），不用固定像素。** `AdaptiveShell.detail` 是新的公开入参：
  - 大屏 + detail → `body`（master）| 发丝分隔线 | `detail`，两侧各自撑满、独立滚动；
  - 中屏 / 紧凑 + detail → detail **整幅顶替** body（沿用「详情是整页」的既有行为，平板竖屏与手机不硬塞双栏）；
  - 无 detail → 单栏。
  - 用配比而非固定宽：内容区已被 `contentWide` 钉死，配比在实机宽度区间内变化很小；而主栏可能是表单页，固定 380px 会把它压成一条窄缝。
  - 该 `Row(crossAxisAlignment: stretch)` 的 `stretch` 是**必需**的（让两侧独立滚动、分隔线撑满高度）。**绝不可改用 `IntrinsicHeight`** —— 两个子项都是滚动视图，其固有高度会退化成「所有子项高度之和」，既昂贵又算错。安全性已登记进 `test/stretch_row_guard_test.dart` 的棘轮（第 2 类：父级高度本身有界）。

- **`home_screen` 拆成「主栏 + 详情」两个构建函数**，而不是让详情覆盖层吃掉整页。`_buildParentDetail()` 返回详情（草稿审核 > 编辑娃娃资料），`_buildParentPage()` 返回侧栏选中页；优先级与拆分前完全一致。大屏下两者并排，家长可以在左侧直接换一条继续看。

- **桌面端可点区域统一走 `AppFocusableAction`**（`app_theme.dart`，与 `AppCard` / `AppBrutalButton` 同处）。它补齐三件事：进焦点树（`FocusableActionDetector` + `Shortcuts`/`Actions`）、`Enter`/`Space`/小键盘回车激活（与鼠标点击**同一个** `onTap`）、焦点可见。
  - 焦点环用 `foregroundDecoration` 而非 `decoration` 绘制：前者覆盖绘制、**不参与布局**，聚焦/失焦不会让元素尺寸跳动。
  - 焦点环取 `accent`（靛蓝）而非墨黑：本仓墨黑描边到处都是，用墨黑画焦点环会退化成「边框好像变粗了」，读不出「焦点在这里」。
  - 该组件**全程不注入任何宽高约束**（各层都是透传 proxy），因此可以安全包住 `AppCard`——那张卡对「外层塞进无界宽度」极其敏感（见 `app_theme.dart` 里 `ShadButton.ghost` 的 NOTE）。
  - 已接入：导航项（侧栏 / 轨 / 抽屉 / 底栏）、侧栏收起按钮、汉堡按钮、用户区、**`AppCard` 的可点路径**。后者最重要——只修菜单不修卡片，等于「Tab 得到菜单却打不开任何东西」。
  - `AppCard` 的按压反馈（整卡下沉 + 硬阴影收拢）改由 `onPressedChanged` 驱动；键盘激活时补齐一次 `true→false`，使键盘与鼠标的反馈一致。

- **App 根挂 `FocusTraversalGroup(policy: ReadingOrderTraversalPolicy())`**，让 Tab 顺序按「侧栏 → 主栏 → 详情栏」可预期。这里显式声明策略而不依赖缺省，是为了让「顺序可预期」有据可查。

- **桌面窗口设最小尺寸 800×600**（macOS `minSize` / Windows `WM_GETMINMAXINFO` / Linux `gtk_widget_set_size_request`）。窗口能拖到任意小会让响应式断点失去意义——宽度跌到 700 以下会切进紧凑档那套触控布局，在桌面鼠标下并不好用。800×600 是「侧栏 240 + 主内容 560」依然可用的最小尺寸。
  - **已知限制**：`frontend/.gitignore` 第 20–25 行把 `android / linux / macos / web / windows / ios` 全部忽略，**平台 runner 目录不受版本控制**。因此这三处原生改动只在本机生效，`flutter create` 重新生成或换机器构建都会丢失。要让它成为仓库事实，需先把平台目录纳入版本控制（或改为打补丁脚本）。见「后果」。

- **不引入 `GridView` 做多列重排。** 静态扫描 `Wrap(` 共 29 处，逐处核对后全是**流式 chip 组**（学科标签、元信息 chip、兴趣标签、按钮组）或**内容自适应高度的卡片组**；这类内容的正确原语就是 `Wrap`，`GridView` 的等宽等格反而会把它挤变形。唯一像「卡片墙」的 `parent_overview_view` 统计卡已有自己的 `LayoutBuilder` 分栏，改成 `GridView` 会引入固定 `childAspectRatio`，在大字号的 Child Mode 下有裁字风险。**结论：本仓不存在「该用 GridView 却用了 Wrap」的站点**——审计里「0 处 GridView」是症状级观察，不是缺陷。

## 守卫

- `test/adaptive_shell_layout_test.dart` —— 内容宽度上限 + 水平居中 + **竖向贴顶**、三档断点的行为测试（6 例）。
- `test/app_focusable_keyboard_test.dart` —— Tab 可达 + Enter/Space 激活 + 不可点项不进焦点树 + 键盘补齐按压反馈（4 例）。
- `test/stretch_row_guard_test.dart` —— 棘轮扩为两类站点，新增条目附依据。

## 后果

- 手机与小平板**零变化**（断点以下 1080 不生效、`detail` 走整幅顶替）。
- 大屏（≥1200）行为变化：家长端复核/编辑详情以右侧栏呈现，而非整页；所有页面内容居中且不超过 1080。
- 桌面端从「只有鼠标可用」变为「Tab + Enter 全流程可用」。
- **未解决**：平台 runner 目录仍被 gitignore。原生最小窗口尺寸与「桌面 runner 是 `flutter create` 默认模板」这件事在换机/重建后会回退。彻底解法（纳入版本控制或补丁脚本）另开一张单。
- 未覆盖：`AppBrutalButton` / `AppPrimaryButton` 仍是裸 `GestureDetector`，键盘用户能 Tab 到卡片打开详情，但按钮本身还进不了焦点树；`app_option_tile`（选项卡）同理。按同一模式接 `AppFocusableAction` 即可，留作后续批次。
