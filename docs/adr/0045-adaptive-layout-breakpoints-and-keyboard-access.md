# 自适应布局三档断点、内容宽度令牌与键盘可达性

确立前端自适应布局的单一事实源：**三档断点 + 内容宽度令牌 + 桌面键盘可达性**。

补的是 ADR-0014（响应式导航壳）留下的三处缺口：① 壳只有「紧凑 / 非紧凑」两档，iPad 与桌面完全共用同一套布局；② 内容区无宽度上限，大屏下列表被无限拉宽（宽度全靠各页面自觉，实测 6 个页面完全没约束）；③ 可点区域一律是裸 `GestureDetector`，**不进焦点树**——桌面端 Tab 跳不过去、Enter 点不动。

## 决策

- **布局决策只基于「可用宽度」，禁止按设备形态分支。** 一律读 `LayoutBuilder` 的 `constraints.maxWidth`；禁止 `MediaQuery.orientationOf` / `OrientationBuilder`，禁止 `isTablet` / `isDesktop` 这类硬件判定，也禁止 `MediaQuery.of(context).size.width`（那是**屏宽**，不是可用宽度）。理由：Flutter 应用跑在可缩放窗口、多窗口与画中画里，**设备形态不等于可用空间**；而且 master-detail 的详情栏比窗口窄得多，按屏宽算出来的约束必然溢出。

- **三档断点收敛到 `AppLayout`，值是 700 / 1200。**
  - `< compactMax (700)` **紧凑**：娃娃端底部导航；家长端顶部汉堡 + 左抽屉。
  - `[700, largeMin)` **中屏**：侧栏 240 ↔ 64 可收起。
  - `≥ largeMin (1200)` **大屏**：与中屏同布局。曾在此档展开 master-detail 双栏，**已由 ADR-0059 移除**；`largeMin` 常量保留以便将来编排，但当前**无代码消费者**。
  - **订正**：`adaptive_shell.dart` 的类注释此前写「在三档断点间切换」，但代码只有 compact / 非 compact 两个分支。现在注释与实现一致。

- **内容宽度收敛到 `AppLayout` 的六个语义档，禁止再写裸数字。** 原先散着 1080 / 820 / 520 / 480 / 440 / 380 六个魔法值、19 处调用，无「哪一档才是我该用的」依据。现在按语义命名：`contentWide 1080`（家长端工作区）/ `contentReading 820`（答题阅读区）/ `contentCard 520`（居中结果卡）/ `contentNarrow 480`（登录、表单对话框）/ `contentEmpty 440`（空态 / 提示卡）/ `contentFloat 380`（浮层）。**取值一律沿用原数字**，本次只做收敛命名，不改观感。
  - 后续：`contentFloat` 已随浮层消失被删除（家长端 AI 助手改整页，见 ADR-0047），宽度档由六档变五档。

- **宽度上限在 `AdaptiveShell` 统一兜底，不在页面各写一遍。** 壳的内容区包 `Align(alignment: topCenter)` + `ConstrainedBox(maxWidth: contentWide)`。一处改动覆盖 6 个此前完全无约束的页面（`child_home` / `profile_screen` / `practice_screen` / `review_screen` / `child_form_screen` / `parent_tasks_view`）。
  - 必须包一层对齐，而不是只加 `maxWidth`：只加 `maxWidth` 会让内容贴左、右侧留下一条突兀空带。
  - **用 `Align(topCenter)` 而不是 `Center`**：`Center` 的竖向居中会把「内容不足一屏」的页面（表单、错误态）整块浮到屏幕中间，而本仓明确要「内容贴顶自然布局」（`adaptive_shell.dart` 原注释）。`Align` 横向传下松约束，贪心子项（ListView / scroll view）仍取满 `contentWide`，与 `Center` 等效。由 `test/adaptive_shell_layout_test.dart` 最后一例守住。
  - 页面需要更窄时自带更强的 `ConstrainedBox`（答题 820 / 登录 480），**内层更紧者生效**，不会互相打架。
  - 紧凑宽度下 1080 不生效，等价于无包裹——手机与小平板排布**零变化**。
  - **例外：`PracticeScreen` 由 `Navigator` 推入，不在壳的兜底范围内**，必须自带约束（其 `PracticeReviewView` 是本仓唯一漏掉的页面，已补）。新增 `Navigator.push` 的整页时，记得同样自查。

- ~~**master-detail 的宽度配比用 Flex（5 : 8）**~~ **已废弃，见 ADR-0059。** ~~`AdaptiveShell.detail` 是新的公开入参：大屏 + detail → 双栏；中屏 / 紧凑 + detail → 整幅顶替 body；无 detail → 单栏。~~
  废弃原因（不重述细节，只留结论）：`detail` 让「当前该看哪个页面」变成**两个状态的优先级裁决**，而裁决散落在各个回调里——侧栏点击记得清掉详情、底部「我的」忘了清，于是审核期间点「我的」看到的仍是审核页。ADR-0059 用「单一页面状态 + 删除 `detail`」根治，本条及 `AppLayout.masterFlex` / `detailFlex` 随之删除。

- ~~**`home_screen` 拆成「主栏 + 详情」两个构建函数**~~ **已废弃，见 ADR-0059。** 详情不再是独立的构建产物，而是与侧栏页并列的一个页面状态，由同一个 `switch` 产出。

- **桌面端可点区域统一走 `AppFocusableAction`**（`app_theme.dart`，与 `AppCard` / `AppBrutalButton` 同处）。它补齐三件事：进焦点树（`FocusableActionDetector` + `Shortcuts`/`Actions`）、`Enter`/`Space`/小键盘回车激活（与鼠标点击**同一个** `onTap`）、焦点可见。
  - 焦点环用 `foregroundDecoration` 而非 `decoration` 绘制：前者覆盖绘制、**不参与布局**，聚焦/失焦不会让元素尺寸跳动。
  - 焦点环取 `accent`（靛蓝）而非墨黑：本仓墨黑描边到处都是，用墨黑画焦点环会退化成「边框好像变粗了」，读不出「焦点在这里」。
  - 该组件**全程不注入任何宽高约束**（各层都是透传 proxy），因此可以安全包住 `AppCard`——那张卡对「外层塞进无界宽度」极其敏感（见 `app_theme.dart` 里 `ShadButton.ghost` 的 NOTE）。
  - 已接入：导航项（侧栏 / 轨 / 抽屉 / 底栏）、侧栏收起按钮、汉堡按钮、用户区、**`AppCard` 的可点路径**。后者最重要——只修菜单不修卡片，等于「Tab 得到菜单却打不开任何东西」。
  - `AppCard` 的按压反馈（整卡下沉 + 硬阴影收拢）改由 `onPressedChanged` 驱动；键盘激活时补齐一次 `true→false`，使键盘与鼠标的反馈一致。

- **App 根挂 `FocusTraversalGroup(policy: ReadingOrderTraversalPolicy())`**，让 Tab 顺序按「侧栏 → 主栏」可预期（ADR-0059 前写的是「侧栏 → 主栏 → 详情栏」，详情栏已不存在）。这里显式声明策略而不依赖缺省，是为了让「顺序可预期」有据可查。

- **桌面窗口最小尺寸 = 320×568**（macOS `minSize` / Windows `SetMinimumSize` / Linux `gtk_widget_set_size_request`）。
  - **2026-09-17 修订**：旧值 ~~800×600~~ 被推翻，理由见下方「最小窗口尺寸下移」。取值 320×568 = **iPhone SE 竖屏**，即 `frontend/test/device_size_fit_test.dart` 认证过的**最窄真实设备**。地板必须落在被守卫覆盖的集合之内，否则「能拖到的尺寸」与「被测过的尺寸」是两个集合，等于在没人看过的地方跑。
  - macOS / GTK 的 `minSize` 与 `size_request` 均**含标题栏**，两平台高度口径一致；宽度无横向 chrome，故窗口宽 = 内容宽。
  - **已知限制**：`frontend/.gitignore` 第 20–25 行把 `android / linux / macos / web / windows / ios` 全部忽略，**平台 runner 目录不受版本控制**。因此这三处原生改动只在本机生效，`flutter create` 重新生成或换机器构建都会丢失。要让它成为仓库事实，需先把平台目录纳入版本控制（或改为打补丁脚本）。见「后果」。

- **不引入 `GridView` 做多列重排。** 静态扫描 `Wrap(` 共 29 处，逐处核对后全是**流式 chip 组**（学科标签、元信息 chip、兴趣标签、按钮组）或**内容自适应高度的卡片组**；这类内容的正确原语就是 `Wrap`，`GridView` 的等宽等格反而会把它挤变形。唯一像「卡片墙」的 `parent_overview_view` 统计卡已有自己的 `LayoutBuilder` 分栏，改成 `GridView` 会引入固定 `childAspectRatio`，在大字号的 Child Mode 下有裁字风险。**结论：本仓不存在「该用 GridView 却用了 Wrap」的站点**——审计里「0 处 GridView」是症状级观察，不是缺陷。

## 实现期补充决策（2026-09-17）：宽度与「出路」各收一个口

起因是 `ExportPreviewPage`（打印预览）上线时把人**锁死在一屏**：它是 `Navigator.push` 的整页，
拿不到壳的任何兜底，而它既没写返回按钮、也没有 Esc——桌面端没有系统返回手势，
`CupertinoPageRoute` 的滑动返回只有 iOS 有。补一行 `showBack: true` 就能修，但**破的是两件
更基本的事**：

- **宽度出口：`AppContentFrame`（`shared/widgets/`）。**
  此前全仓 **14 处**手抄同一段 `Align` + `ConstrainedBox(maxWidth: contentWide)`，且口径不一致
  ——壳写 `topCenter`、塞进壳里的页面写 `topLeft`。收成一个组件后，宽度令牌只有一处定义；
  `alignment` 仍是调用方参数（迁移时**照抄原值**，不顺手统一）。壳自己 (`AdaptiveShell._cappedWidth`)
  也走同一个组件，于是「只有它是定义，其余都是使用者」。
  ⚠️ 迁移时最容易伤到的是「故意留在框外的兄弟节点」：`practice_review_view` 的底部行动条
  刻意留在约束**外**（它该通栏），一旦把整页钉到 1080，那条会跟着缩窄。看手抄块时必须同时
  看它的 siblings，别只盯着那一段本身。

- **退路出口：`AppPushedPage`（同上）。**
  把「退路」从**每页自觉**改成**结构默认**：`showBack` 默认 **true**（与裸 `AppTopBar` 的 false 相反）、
  Esc 默认可返回（`Shortcuts` 必须是焦点节点的**祖先**且要 `autofocus`，否则桌面端刚进页面时
  焦点树为空、Esc 是死的）、`onBack` 同时接管返回按钮与 Esc（订正子页用它做状态机回退而非路由出栈）。
  `ExportPreviewPage` / `PracticeScreen`（含订正子页）已迁入。

- **为什么助手页没用整页骨架**：`AssistantChatPage` 是**双宿主**（既可 push 也可作壳内页签），
  套 `AppPushedPage` 会在页签形态下长出第二个顶栏。它只迁了宽度部分（三处 → `AppContentFrame`），
  退路由调用方按形态传 `showBack`。
- **`PracticeScreen` 传 `maxWidth: double.infinity`**（不加宽度上限）是有意的保留：本页的回顾阶段
  有一条通栏底部行动条，在此钉 1080 会把它一起缩窄。这是视觉取舍，不属于本轮「退路结构化」的范围。

## 最小窗口尺寸下移（2026-09-17 修订，推翻上文「800×600」）

**触发**：要在桌面上验证手机 / 紧凑档布局，发现**根本拖不到**——macOS 的 `contentRect` 与
`minSize` 同为 800×600，窗口连一像素都缩不了；Windows / Linux 虽默认 1280×720，地板也是 800×600。
而 `compactMax = 700`，**地板比断点还高 100px**。

**为什么旧决策是错的**（不是因为「用户想要」，是因为它的前提不成立）：

- 800×600 的论证是「宽度跌到 700 以下会切进触控布局，**在桌面鼠标下并不好用**」。这是把地板
  用来**挡住不喜欢的尺寸**；地板的正当用途是**挡住会坏掉的尺寸**。两者混同后，副作用是
  **整个紧凑档在桌面构建里从未被渲染过**——一条长期无人经过的分支，比「用户可能拖到自己
  不喜欢的布局」危险得多（拖回去只要一次手势，没人看过的分支会一直在那里烂）。
- 「好不好用」是**偏好**，「能不能验证」是**能力**。能力优先。
- 旧值还制造了一个测不到的盲区：本机没有可用手机 target（`flutter doctor`：Android SDK 缺失、
  iOS 模拟器未装），桌面窗口是**唯一**能看到紧凑档的地方——而它恰好被地板封死。

**代价（主动接受，不粉饰）**：桌面用户现在可以把窗口拖进紧凑档。若将来桌面成为正式发布形态、
且实测证明紧凑档在鼠标下确实难用，正确的解法是**在 UI 层给桌面形态降级提示**，而不是把地板
重新抬到断点之上——抬高地板只会让问题重新变成「看不见」。

**未采纳的方案**：只降低 debug 构建的地板、release 保持 800×600。它更保守，但会引入
「开发时能到、发版到不了」的配置分叉，而分叉本身正是本仓反复踩过的坑
（对照：测试里不传 `theme` 走 shadcn 默认主题，量出来的数「像产品缺陷，实为测试替身假象」）。
地板不影响任何宽度下的渲染结果，故分叉换不来收益，只换来一个需要记住的差异。

## 守卫

- `test/desktop_window_floor_test.dart` —— 静态扫描三份原生 runner，断言**声明的窗口最小宽度
  ≤ `AppLayout.compactMax`**。这是「地板不得高于断点」这条不变量在全仓**唯一能落到 git 里的地方**
  （runner 目录本身被 gitignore，值改了 git 也看不见）。文件不存在时跳过并打印原因
  （fresh clone 未生成平台目录），存在即必须成立。

- `test/content_frame_guard_test.dart` —— 静态扫描 `lib/`，禁止再手写 `Align` + `ConstrainedBox(contentWide)`
  （此前的 14 处已全部迁入，棘轮从「已清零」起算；已验证会咬人）。
- `test/app_pushed_page_test.dart` —— push 整页的**出路**：返回按钮有语义标签、`maybePop`
  真的能离开、**Esc** 能离开、宽度仍守 `contentWide` 且贴顶；`AppContentFrame` 的对齐由调用方决定。
  逐个退化验证过会变红（退回旧写法 / 去掉 `autofocus`）。

- `test/adaptive_shell_layout_test.dart` —— 内容宽度上限 + 水平居中 + **竖向贴顶**、三档断点的行为测试（6 例）。
- `test/app_focusable_keyboard_test.dart` —— Tab 可达 + Enter/Space 激活 + 不可点项不进焦点树 + 键盘补齐按压反馈（4 例）。
- `test/stretch_row_guard_test.dart` —— 棘轮扩为两类站点，新增条目附依据。

## 后果

- 手机与小平板**零变化**（断点以下 1080 不生效）。
- 大屏（≥1200）行为变化：所有页面内容居中且不超过 1080。**2026-09-21 修订**：家长端复核/编辑曾以右侧详情栏呈现，ADR-0059 改为整页（删除 `detail`），本条随之作废。
- 桌面端从「只有鼠标可用」变为「Tab + Enter 全流程可用」。
- 桌面端窗口可拖到 320×568，**紧凑档在桌面上可达**（这是 2026-09-17 修订的目的）。
- **未解决**：平台 runner 目录仍被 gitignore。原生最小窗口尺寸与「桌面 runner 是 `flutter create` 默认模板」这件事在换机/重建后会回退。彻底解法（纳入版本控制或补丁脚本）另开一张单。
- 未覆盖：`AppBrutalButton` / `AppPrimaryButton` 仍是裸 `GestureDetector`，键盘用户能 Tab 到卡片打开详情，但按钮本身还进不了焦点树；`app_option_tile`（选项卡）同理。按同一模式接 `AppFocusableAction` 即可，留作后续批次。
