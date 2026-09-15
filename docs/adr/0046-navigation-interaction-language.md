# 导航与列表的交互语言：选中态唯一化、悬停分层、头部内边距契约

收口「可点区域」的三种交互反馈（**选中 / 悬停 / 焦点**）为全站唯一实现，并给
`AdaptiveShell.sidebarTop` 补上缺失的内边距契约。

起因是一次侧栏头部的观感问题：切换娃娃的触发卡与侧栏左缘**贴边**、卡片右缘比导航项窄 48px、
侧栏内同时存在 0 / 8 / 16 三种左边缘；浮层里的娃娃选项每个都套一层描边（盒中盒）、
「添加娃娃」与娃娃选项**同形**（读起来像第三个娃娃）；行内编辑按钮的命中区只有 16px 且键盘 Tab 不到。

## 决策

- **`sidebarTop` 的内边距由宿主给，组件自身零外边距。**
  新增 `AppLayout.sidebarHeaderPadding`（LTRB = 8 / 12 / 8 / 4），`AppSidebar` 与抽屉**都**套同一份。
  - 左缘 8 必须等于导航项药丸的左缘（`AppSidebarItem` / `_DrawerItem` 的 `horizontal: AppSpacing.sm`）。
    否则一个 240px 宽的侧栏里会出现两条左边缘，像两个不相干的区块。
  - `ParentChildSelector` 原先自带 `Padding(right: 12)` —— 它只对「右侧紧跟收缩按钮」这一种宿主成立，
    渲染进抽屉（无收缩按钮）时就变成一条没有对应物的右内边距。**组件不该知道宿主两侧是什么。**

- **头部的「主控件 + 收缩按钮」同行等高。** 收缩按钮与选择器触发卡都钉到 `AppLayout.tapTarget`（44）。
  触发卡用 `SizedBox(height:)` 显式钉死而不是靠「头像 28 + 上下 padding 8」凑——凑出来的 44 会被
  `ShadCard` 的描边吃掉 1~2px，且以后换内边距就悄悄错位。

- **收缩态的 `sidebarTop` 不消失，降级为头像。** `AppSidebar` 原先 `if (top != null && !collapsed)` 直接
  不渲染——家长把侧栏收起后就看不出「当前在看谁的数据」。现在轨态渲染头像（无娃娃时渲染 accent 的「+」），
  与 `AdaptiveUserBlock` 在轨态去掉文字只留头像的降级方式一致。
  - 为此新增 `SidebarCollapseScope.maybeOf`：抽屉态不注入该 scope，读不到即视为展开。

- **轨态的头像不加描边。** 轨态里导航图标与收缩按钮都是无描边的悬停药丸，唯独头像套个框会读成
  「另一类东西」。

- **「选中」在全站只有一种语言：无描边药丸 + `surfaceActive` 填充 + accent 图标。**
  浮层里的娃娃选项原先用 `AppCard.listRow`（自带发丝边）——放在一个已带描边的浮层里就是**盒中盒**，
  把「选中」和「容器边界」混成同一种视觉。改为与 `AppSidebarItem` 完全同构的药丸。
  - 判据：**一个列表项自身不需要边界**；需要边界的是它所在的容器。

- **「添加娃娃」是动作，必须与「娃娃」区分。** 它原先与娃娃选项**同一个 `_ChildOption`**，
  头像槽、字重、行高全都一样，读起来就是第三个娃娃。改用 `AppPrimaryButton`（`添加模型` 用的同一个
  组件），在分隔线之下成为浮层页脚 CTA。
  - 浮层原先用 `Column(mainAxisSize: min)` 直接堆选项，娃娃多时会**顶破** `maxHeight` 溢出。
    改为 `Flexible(ListView(shrinkWrap: true))`，过多时浮层内部滚动。

- **悬停反馈收口到 `AppFocusableAction.hoverHighlight`（新增入参，缺省 false）。**
  本次一口气写了三处「`StatefulWidget` + `MouseRegion` 手搓 hover 底色」的重复样板，之后还会有更多。
  收口后调用方只声明意图，不再各写一份状态。
  - 悬停底色用 `surfaceHover`（比 `surfaceActive` **浅一档**），且画在**底层**（`decoration`）——
    子项自带的选中底色会盖住它。于是同一元素上「悬停」与「选中」天然分层、可区分。
  - 悬停底色与焦点环都**不改布局**（前者是背景填充，后者走 `foregroundDecoration`）。
  - 适配范围：侧栏导航项、抽屉项、收缩按钮、浮层选项、行内图标按钮。

- **行内图标操作走 `AppControl.heightSmOf` 方形命中区 + `AppFocusableAction`。**
  浮层里的编辑铅笔原先是裸 `GestureDetector` 套 16px 图标：命中区 16px（低于家长端 32px 底线），
  且永远不在焦点树里。现与输入框里的「眼睛」按钮同档（见 `app_inputs.dart`），并进焦点树。

- **结构尺寸补令牌**（`AppLayout`，禁写裸数字）：`sidebarMenuWidth`（= `sidebarExpanded - 2 × AppSpacing.sm`）、
  `popoverChrome`、`menuMaxHeight 400`；浮层里的分隔线写 `AppElevation.borderWidthHairline` 而不是裸 `1`。

### 浮层的锚点与宽度（第二轮补充）

用户反馈「点击触发卡时浮层选项宽度超出侧边栏」。根因两条，互相叠加：

- **锚点**：shadcn 默认 anchor 是 `ShadAnchorAuto(bottomCenter ↔ bottomCenter)` = 相对触发卡
  **水平居中**，且底层 `positionDependentBox` 还会再居中一次。触发卡 171 宽、浮层 224 宽 →
  两侧各溢出约 26px，左溢部分又被屏幕左缘钳住。实测浮层外框 `0..244`：左缘比触发卡左缘还靠左 8px、
  右缘比侧栏（240）还宽 5px。
  - 改为显式 [`ShadAnchor`]：**展开 / 抽屉** = 浮层左上对齐触发卡左下 + 4px 间隙（开在下方、左缘与
    触发卡（= 侧栏唯一那条左边缘）齐平）；**轨态** = 浮层左上对齐触发卡右上（向轨的右侧飞出、
    顶端齐平）——轨态若仍开在下方左对齐，224 宽的浮层会盖住整条 64px 轨道、挡掉导航图标，
    与「轨态收起后信息不能丢」直接冲突。
  - 命名方向易读反，按实现接线记：`ShadAnchor.childAlignment` 作用在**浮层**上、
    `overlayAlignment` 作用在**触发卡**上。
- **宽度记账**：shadcn 的 `popoverTheme.padding`（本仓 `all(8)`）与 2px 描边都包在**内容之外**，
  所以「浮层外框 224」要写成「内容 224 − `popoverChrome`(20)」。宽度令牌的语义定为**外框宽**，
  `popoverChrome` 把这笔无法从内容侧推导的开销显式记账；配套守卫断言渲染出来的外框宽 == 令牌，
  改了主题内边距或描边宽度会立刻红，而不是静默变宽。
- 顺带统一面板内部：选项药丸、CTA 同为「项」→ 共用同一条左缘（缩进 `xs`）；分隔线是面板级
  结构边 → **通栏**（原先选项缩进 4 / CTA 8 / 分隔线 12，同一面板里三条左边缘）。

## 守卫

- `test/sidebar_header_layout_test.dart`（9 例，用真 `AdaptiveShell` + 真选择器，provider 种入已加载状态）：
  头部左缘 == 导航药丸左缘、选择器与收缩按钮同高、头部有上/左留白、
  **轨态不溢出且降级为头像**、浮层里「添加娃娃」是主按钮且选项不再套 `AppCard`、
  **浮层外框左缘齐平 + 宽度 == 令牌 + 不溢出侧栏**、**面板内部只有一条左边缘**、
  **浮层 CTA 高度 == 标准档令牌**、**轨态浮层向轨右侧飞出且不压住导航图标**。
  - 轨态那条是真正的回归网：展开态那行（头像 + 姓名 + 箭头 + 24px 内边距 = 78px）塞进 48px 宽的轨里
    必然 `RenderFlex overflowed`，只有真正走了降级分支才不会抛。
  - 浮层几何那条也是回归网（已实测：去掉显式 anchor 后它报 `Expected: <8.0> Actual: <0.0>`）。
  - 该文件的台架**必须**给 `ShadApp.custom` 传 `theme: AppTheme.shadFor(...)`：不传会走 shadcn 默认主题
    （浮层内边距 `h12/v6`、按钮竖向内边距 8），断言几何的用例会量到与产品不符的数。

## 后果

- 侧栏头部、抽屉头部、浮层选项、轨态头部的观感统一；家长收起侧栏后仍能看出当前娃娃。
- 桌面端：菜单/导航/浮层选项全部可 Tab、可 Enter 激活、有可见焦点环，鼠标悬停有反馈。
- 副作用：`AppSidebarItem` 的类注释原先写「active 态显示左竖条」，但实现里从来没有左竖条——已订正为
  与实现一致（药丸底色 + accent 图标）。
- **未覆盖**：`AppBrutalButton` / `AppPrimaryButton` 自身仍是 `ShadButton` / 裸 `Container`，
  它们进焦点树的路径靠 shadcn 自带的 `CallbackShortcuts`，未接入 `AppFocusableAction`；
  `app_option_tile`（选项卡）同理。按同一模式接即可，留作后续批次。

## 排查用到的两个测试陷阱（记录以免重踩）

- **`ShadApp.custom` 不传 `theme:` 会用 shadcn 默认主题**，其按钮竖向内边距是 8（本仓主题是 0）。
  在默认主题下渲染 CTA，`ShadButton` 的 `ConstrainedBox(maxHeight: 内容盒高)` 会把文字压到 12px 并裁切——
  看起来像产品缺陷，其实是测试替身的假象。**任何要看视觉的测试都必须显式传 `AppTheme.shadFor(...)`。**
- **`RenderRepaintBoundary.toImage()` 在 `testWidgets` 里必须包 `tester.runAsync`**，否则 fake-async 区
  里 `await` 永不返回，测试进程被挂死（表现为 SIGKILL / exit 137）。
