# 家长端导航收敛为单一页面状态，移除 master-detail 详情栏

家长端曾有三个**并列**的导航状态（侧栏索引 / 详情覆盖层 / 「我的」布尔）。`AdaptiveShell.detail` 在中屏与紧凑档会**整幅顶替** `body`，于是「谁盖谁」要靠每个回调自己记得清理——侧栏点击记得清，底部「我的」忘了清。本 ADR 决定：**把三者合成一个 `sealed` 页面状态，并删除 `AdaptiveShell.detail` 与 master-detail 双栏**。

## 背景：个人信息页「被遮挡」其实是没有进渲染树

线上现象：家长从任务列表点进草稿审核后，再点底部「我的」，画面仍停在审核页。

不是 z-index 问题。`adaptive_shell.dart` 的渲染链是：

```dart
Widget get _singleColumn => widget.detail ?? widget.body;
```

中屏 / 紧凑档下 `detail` 非空就整幅顶替 `body`——`ProfileScreen` 挂在 `_buildParentPage()` 里（属 `body`），**压根没被构建**。大屏档下它是并排双栏，所以同一操作在 iPad Pro 横屏（1366 ≥ `largeMin` 1200）「正常」，换窄一点就「被遮挡」。

三条导航路径的清理对称性：

| 入口 | 是否清覆盖层 | 结果 |
|---|---|---|
| 侧栏点击 `_parentTap()` | ✅ 显式清 `_reviewingTask` + `_editingChild` | 正常跟随切换 |
| 底部「我的」`_onProfileTap()` | ❌ 只置 `_showProfile = true` | 审核页顶替，个人信息不渲染 |
| 侧栏头部「添加 / 编辑娃娃」 | ⚠️ 清了 `_editingChild`，没清 `_reviewingTask` | 审核中点它无反应 |

`_parentTap()` 的注释里其实写明了这条纪律（「不清掉会挡住页面切换」），但**只有侧栏点击走了这条路**。

## 决策

- **家长端当前页面只有一个状态：`sealed _ParentPage _parentPage`。** 分支含
  `_Overview` / `_CreateTask` / `_TaskList` / `_WrongQuestions` / `_TutorLogs` / `_AddChild` /
  `_EditChild(child)` / `_QuestionBank` / `_Models` / `_TaskReview(task, back)` / `_Profile`。
  所有入口（侧栏、底部用户区、侧栏头部、助手卡片跳转）都只调 `_go(page)`——**没有第二个状态需要顺带清理**。
  `switch` 的穷尽性由 `sealed` 保证：新增页面忘记在 `_buildParentPage()` 登记会**编译失败**，
  而不是运行时「点了没反应」。

- **「我的」也只是一个页面**（`_Profile`），不再是与索引并列的布尔。这顺带修掉了
  「侧栏『任务』与底部『我的』同时高亮」——两个状态各写各的必然产物。

- **删除 `AdaptiveShell.detail` 与 master-detail 双栏**，连带删 `AppLayout.masterFlex` / `detailFlex`。
  壳只剩 `body` 一个页面宿主，`_cappedWidth(widget.body)` 单栏。

- **`_TaskReview` 自带 `back` 页**，保留「从哪儿进来就回哪儿」；侧栏高亮由 `_highlightFor()` 取 `back`，
  审核不占一个侧栏入口（否则从概览点进来时「任务」会错位高亮）。

- **娃娃端不动。** 它本来就没有 detail，`_showProfile` 与 `_childNavIndex` 的二选一在 `_buildChildView()`
  里是显式互斥的 `if`，不存在三方裁决。留着两套写法是**有意**的：家长端有 11 个页面与跨页跳转，
  娃娃端是 5 个常驻 `IndexedStack` 页签，合并成同一套会让后者更绕。
  ⚠️ 代价是**跨角色共用的回调必须按角色分派**：`_onProfileTap` 同时服务两端（同一个
  `_profileDestination`），改造时只写了家长端那份 → 娃娃端点「我的」毫无反应（已修，并补了
  娃娃端用例）。这类洞 `flutter analyze` 照不出来——类型都对，只是另一端的状态没人写。

## 接受的代价

- **大屏不再有双栏**：iPad Pro 横屏（1366）家长端从「左列表 | 右详情」变整页。
  丢掉的具体能力是「左侧点另一条任务、右侧审核页跟着换」（`ParentTaskReviewScreen.didUpdateWidget` 专为它写过）。
- **审核页宽度从 ≈665（8/13 × 1080）变 1080**，题面卡与操作条需过一遍视觉（本轮未做专项核对）。
- `AppLayout.largeMin` 现在**无代码消费者**（三档断点在代码里实际只剩紧凑 / 非紧凑两分支）。
  常量保留以便将来编排，ADR-0045 已标注。

## Considered Options

- **只补 `_clearOverlays()`，每个入口先调一次**——否（可止血，不可根治）。3 行能修掉当前三个入口，
  但「清覆盖层」仍是每个新入口必须**记得**做的事；下一个入口还会再漏一次，且漏了之后同样是
  `flutter analyze` 照不出来。
- **改成 `Navigator.push` 路由页**——否。`HomeScreen` 直接挂在 `CupertinoApp` 根栈下（`main/app.dart`），
  push 会**连侧栏一起盖住**：用户根本点不到「我的」，问题是以「入口消失」的方式解决的，还丢了侧栏常驻。
- **保留双栏、只把 `detail` 的优先级裁决集中到一个函数**——否。集中能减少遗漏，但「两个状态并存」
  这个根因还在；而双栏带来的收益（大屏并排）小于它引入的复杂度。
- **娃娃端一起并成单一状态**——否（本轮），理由见上。真要统一，应等 `IndexedStack` 常驻挂载的
  取舍（切页签不重建、保留滚动位置）被单独评估过。

## 与既有 ADR 的关系

- **ADR-0045（自适应布局）**：反向修订。删除其「master-detail 宽度配比」「`home_screen` 拆成主栏 + 详情」
  两条，并把大屏档描述改为「与中屏同布局」；`largeMin` 标注为无消费者。
- **ADR-0037（前端分层）**：不变。`_ParentPage` 是 `features/home` 的私有类型，不跨 feature。
- **ADR-0042 / ADR-0054（助手卡片跳转）**：`_parentPageFor(ShellDestination)` 直接产出页面，
  与侧栏点击走同一个 `_go`，不再需要「翻成索引再清层」这一步。

## 守卫

- `frontend/test/parent_nav_single_source_test.dart`（新增）：
  ① 静态——`AdaptiveShell` 不许再有 `Widget? detail`，`home_screen` 不许再出现
  `_parentNavIndex` / `_reviewingTask` / `_editingChild`（这类洞 `flutter analyze` 照不出来）；
  ② 行为——任一时刻侧栏最多一个高亮项，进「我的」后侧栏零高亮且 `ProfileScreen` 真的渲染出来
  （正是「状态不唯一」在界面上唯一能被观测到的痕迹）。
- `frontend/test/adaptive_shell_layout_test.dart`：删除双栏与「detail 顶替 body」三例。
- `frontend/test/stretch_row_guard_test.dart`：第 2 类站点的依据从「master-detail 双栏」改为
  「侧栏 | 内容」Row（棘轮集合本身不变）。
