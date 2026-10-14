# 导航 / 菜单 / 页面展示 交互评审

> 视角：产品交互 + 功能体验。范围：Flutter 前端（`frontend/lib`）。
> 方法：读代码取证据，每条结论附 `file:line`。不含后端 REST 组织（另案）。
> 分支：`ai-intent-routing`。日期：2026-10-14。

---

## 0. 一句话结论

底层组件层（四态 / 键盘可达 / 三档自适应 / 宽度令牌）**已经做对**；
缺的是**路由层**（全 App 只有一个 route）与**菜单信息架构**（11 项平铺 + 两处命名撞车 + 一处创建入口错位）。
前者是结构性的，决定了「返回键直退应用」「无深链」「壳内切页零转场」这一串问题；后者是 IA 的，决定了教师每天要在这套导航上多花多少认知成本。

**先修 P0 的两条（抽屉不关闭、返回键直退），再谈 IA 重构，最后才是转场与动效。**

---

## 1. 现状结构

| 层 | 实现 | 位置 |
|---|---|---|
| App 根 | `ShadApp.custom` → `CupertinoApp(home:)`，**无 routes / onGenerateRoute** | `main/app.dart:124-167` |
| 导航壳 | `AdaptiveShell` 三档：<700 底栏 / 抽屉，≥700 侧栏 240↔64 | `shared/widgets/adaptive_shell.dart:97-163` |
| 教师端状态 | `sealed TeacherPage`，`_go(page)` 单一出口 | `home/presentation/teacher_pages.dart`、`home_screen.dart:106` |
| 学生端状态 | `sealed ChildPage` + `IndexedStack` 4 槽 | `home/presentation/child_pages.dart`、`home_screen.dart:421` |
| 菜单数据 | `NavigationDestinations`，硬编码列表 | `home/presentation/screens/teacher_destinations.dart:37-103` |
| 跨页意图 | `ShellDestination` 枚举（仅 3 个值） | `shared/presentation/shell_navigation.dart` |

三种「打开一个东西」的方式并存：

1. **壳内换页**（`_go` → setState）：11 个一级页 + 4 类下钻页，无栈、无转场
2. **`Navigator.push` 整页**（12 处）：练习、导出预览、AI 助手、课件编辑器、题库详情…
3. **弹窗 overlay**（约 22 处 `showShadDialog`）：模型表单、课件章节、场景关联、班级选择…

---

## 2. 问题清单

### P0-1 · 无路由层：全 App 只有一个 route

**证据**：`main/app.dart:165` `home: home`；全仓 grep `onGenerateRoute|routes:|restorationScopeId` → 0 命中。

**后果（四条，都是用户可感知的）**：

| 后果 | 场景 |
|---|---|
| 无历史栈 | 教师端 11 页平铺替换，切页即丢弃上一页所有局部状态 |
| 无深链 | 外部链接 / 通知 / 未来 Web 版 URL 一律不可能；`TaskListPage(initialTab)` 这类"深链"只能由代码内触发 |
| 重启丢上下文 | 进程被杀后一律回「概览」。教师审核草稿到一半被打断 = 重来 |
| 无状态恢复 | 无 `restorationScopeId`，连滚动位置都不保 |

**建议**：不要求一步到位上 `go_router`。分两步——
- 第一步（推荐）：保持 `_go` 但把 `TeacherPage` 提升为**可序列化**的路径（每个页面类给一个 `path` getter + `fromPath`），用 `RestorationMixin` 或本地存储持久化「当前路径 + 关键参数」，启动时恢复。**不引入 Navigator 栈**，ADR-0059 的单状态不变。
- 第二步（可选）：若未来要 Web / 深链，再上 `go_router`，届时 `TeacherPage.path` 直接就是路由表。

**验收断言**：`flutter test` 新增用例——写入 `StudentDetailPage(id)` 后重启 App，`_teacherPage` 反序列化回来等于原值。

### P0-2 · 无 PopScope：Android 返回键 / 侧滑手势直接退出应用

**证据**：全仓 grep `PopScope|WillPopScope` → 0 命中。根 Navigator 只有 `home` 一个 route。

**后果**：教师在「班级 → 班级学生 → 学生详情 → 编辑学生」四级链上按返回键，直接退出 App，四级全丢。平板（本产品主形态）没有系统返回手势，但外接键盘 Esc / 安卓平板手势都会触发。

**建议**：在 `HomeScreen` 外层包一个 `PopScope(canPop: false, onPopInvokedWithResult:)`，把返回翻译成 `_go(backPage)`：
- 若当前 `TeacherPage` 有 `back` 字段 → 回落；
- 否则若不是 `OverviewPage` → 回落概览；
- 否则 → 双击确认退出（或交给系统）。

**验收断言**：widget 测试——`StudentDetailPage(back: X)` 下触发 pop，断言 `_teacherPage == X`；`OverviewPage` 下触发 pop，断言不消费。

### P1-1 · 紧凑档抽屉点菜单不关闭（一行代码能修）

**证据**：`adaptive_shell.dart:265-269` 构造 `_DrawerItem(destination: d)`；`_DrawerItem.onTap` 只调 `destination.onTap`（`:330-331`），从不调 `_setDrawer(false)`。关闭路径只剩点遮罩（`:232-238`）。

**后果**：<700px 宽（竖屏平板 / 分屏）教师点菜单 → 抽屉不动、遮罩继续盖着新页面。

**改法**：`_DrawerItem` 增加 `VoidCallback afterTap` 或在 destination 的 onTap 外包一层 `() { d.onTap?.call(); _setDrawer(false); }`。

### P1-2 · 学生端「我的」把 IndexedStack 整棵移出渲染树

**证据**：`home_screen.dart:417-420`：

```dart
if (_childPage is ChildProfilePage) {
  return ProfileScreen(user: widget.user, onLogout: widget.onLogout);
}
return IndexedStack(index: childPageIndex(_childPage), children: [...]);
```

**后果**：`ChildProfilePage` 时 IndexedStack 整体出树 → 4 个 tab 页 State 全部销毁 → 回首页全部重建，滚动位置、已展开状态、已加载数据全丢。与 IndexedStack「常驻保状态」的设计意图正面冲突。

**连带**：正因为状态会丢，才有了 `_refreshChildTab`（`:170-185`）手工补刷——注释自己承认这是补丁。

**改法**：把 profile 做成第 5 个 IndexedStack 槽位（`childPageIndex` 返回 4），`ChildProfilePage` 不再走特殊分支。底栏「我的」作为第 5 项独立高亮，逻辑与现在一致。

**验收断言**：首页滚动到底 → 切「我的」→ 切回首页，断言滚动偏移未归零。

### P1-3 · 返回栈靠手工 back 字段，只有一级

**证据**：`TaskReviewPage.back`、`EditStudentPage.back`、`StudentDetailPage.back`、`SceneLibraryEditorPage.back`（`teacher_pages.dart`）。

**后果**：新页面必须记得加 `back` 字段，漏加 = 静默回落概览，`flutter analyze` 照不出来。且只有一级，A→B→C 无法一次回 A。

**建议**：把 `back` 从「各页面自己带」改成**壳持有一个 `List<TeacherPage>` 历史栈**——`_go(page)` 默认 push，`_back()` pop。保留 `_goReplace(page)` 给侧栏切换（切一级入口应清空栈）。这样：
- 新增页面零义务（不用记 `back`）；
- 天然支持多级返回；
- 与 P0-2 的 PopScope 同一份数据源。
- ADR-0059 的核心不变：**仍然只有一个「当前页面」状态**，栈只是它的历史，不是并列的第二个真源。

### P2-1 · 紧凑档无当前位置提示

**证据**：`adaptive_shell.dart:401` 顶栏标题写死 `Text('学生学习')`。

**后果**：收起抽屉后，高亮项在抽屉里看不见，用户不知道自己在哪一页。桌面/平板侧栏常驻时无此问题。

**改法**：`AdaptiveShell` 增加 `String? currentTitle`，`_CompactTopBar` 显示它。由 `HomeScreen` 从当前 `TeacherPage` 映射（`labels.dart` 里写一次，遵守 ADR-0058「枚举→文案只在 labels.dart」）。

### P2-2 · 抽屉无侧滑关闭手势

只有点遮罩一条出路（`adaptive_shell.dart:232-238`）。移动端标准交互缺失。可用 `GestureDetector(onHorizontalDragUpdate:)` 在抽屉面板上左滑关闭，或对标 `DrawerController` 的边缘拖拽。注意遵守「裸 GestureDetector 不进焦点树」的约束——这是纯手势补充，不是可点区域，不违反 ADR-0045。

### P2-3 · 两端刷新策略相反

- 学生端：每次切 tab 强制 `load()`（`home_screen.dart:170-185`），可能闪 loading
- 教师端：切走再切回**不刷新**（`loadWhenIdle` 只在 idle 时加载，`teacher_overview_view.dart:66-79`），看到陈旧数据

**建议**：统一为「stale-while-revalidate」——记录 `lastLoadedAt`，切回时若 >30s 则静默后台刷新（保留旧数据渲染，不进 loading 态）。两端共用一份 `loadIfStale` 扩展。

### P2-4 · 学生端底栏 5 项等宽硬塞

`_BottomNavItem` 用 `Expanded` 等分（`adaptive_shell.dart:204`）。窄屏（<360px）每项 ~72px，「错题本」3 字 + 图标靠 `ellipsis` 截断。建议 <360px 时底栏只留图标，或改用 `MainAxisAlignment.spaceAround` + `Flexible`。

---

## 3. 菜单 IA（教师端 11 项）

现状清单（`teacher_destinations.dart:37-103`，无分组、无权重）：

`概览 / 任务 / 学生 / 班级管理 / 题库 / 资料库 / 模型管理 / 运行轨迹 / 课件 / 场景库 / 素材库`

### IA-1 · 命名撞车：资料库 vs 素材库

| 项 | 实际内容 | 证据 |
|---|---|---|
| 资料库 | 教学文档（PDF 等）+ 手动向量化 + 知识点管理 | ADR-0055，`material_library_view.dart:26-30` |
| 素材库 | 教师自传**图片**，grid 陈列、放大、删除 | ADR-0077，`asset_library_screen.dart:18-27` |

中文里「资料」与「素材」近义，图标 `folderOpen` vs `images` 不足以区分。**改名**：资料库 → 「备课资料」，素材库 → 「图片素材」。

### IA-2 · 父子关系倒置：素材库是课件的资源池

`asset_library_screen.dart:22-27` 自述：课件环节里「添加素材」复用的 `showAssetLibraryPicker` 与素材库页共用同一份 `coursewareAssetLibraryProvider`。它本该是课件中心的一个 tab，却被提到与「课件」平级的一级入口。

### IA-3 · 创建入口错位（最典型的 IA 断裂）

`courseware_center_screen.dart:19-20` 自述：**"空态引导去资料库按知识点备课——那里仍是课件真正的创建入口"**。

即：一级菜单里的「课件」不是创建入口，创建入口是另一个一级菜单「资料库」。教师想做课件，得先知道这个隐藏规则。

**建议**：把课件创建的入口同时挂到「课件」页的主 CTA 上（现在是空态里一句引导文案），至少让两条路径等价。

### IA-4 · 运维项混入业务导航

「模型管理」（家长侧模型配置）与「运行轨迹」（AI 排障审计，ADR-0088）跟「概览 / 任务 / 学生」同列同权重。运行轨迹是排障视图，绝大多数教师不需要每天看。

**建议**：下沉到「我的」页内的一组「系统」分区，或在侧栏底部单独分组。

### IA-5 · 容器与内容分离：学生 vs 班级管理

班级是学生的容器。现在两条平级入口，且返回落点不同：
- 「学生」→ `StudentManagementPage` → 学生详情，`back: StudentManagementPage`
- 「班级管理」→ `ClassStudentsPage` → 学生详情，`back: ClassStudentsPage`（`home_screen.dart:280-295`）

**建议**：合并为「班级」一个入口，页内 tab 切「按班级 / 全部学生」。学生详情的 `back` 由此唯一。

### IA-6 · 无徽标 / 无搜索 / 无最近访问

只有出题进度靠 `genTrailing` 挂「任务」（`teacher_destinations.dart:53`）。待审核草稿数、今日待复习数这类真正需要拉取注意的信号只在概览页的「待办」卡片里，一离开就消失。

**建议**：`AdaptiveNavDestination` 已有 `trailing` 槽位，把「任务 → 草稿数」接上去；侧栏顶部加一个搜索框（11 项已接近需要搜索的规模）。

### 建议 IA（三组 8 项）

```
教学
  概览（待办徽标）
  任务（草稿数徽标）
  班级        ← 合并原「学生」+「班级管理」
  题库
  课件        ← 补上创建 CTA
备课资源
  备课资料     ← 原「资料库」
  场景库
  图片素材     ← 原「素材库」（或下沉为课件页 tab）
系统（收进「我的」）
  模型管理
  运行轨迹
```

---

## 4. 页面展示：缺一条"什么会铺满、什么会浮起"的规则

同一类**编辑**动作散落在三种形态：

| 动作 | 形态 | 证据 |
|---|---|---|
| 知识点场景编辑 | 壳内页，夹 `maxWidth: 560` | `home_screen.dart:250-270`（注释自认"原本为 560 宽弹窗设计"） |
| 模型编辑 | 弹窗 | `model_form_dialog.dart` |
| 课件章节编辑 | 弹窗 | `courseware_section_edit_dialog.dart` |
| 课件编辑 | push 整页 | `courseware_center_screen.dart:182` |
| 题库题目详情 | push 整页 | `teacher_question_bank_view.dart:149` |

**建议立一条判定规则**（写进 `frontend.md`）：

- **带独立保存/取消且需要键盘输入** → push 整页（有转场、有返回、Esc 可退，`AppPushedPage` 已兜底）
- **单选 / 确认 / 短表单** → 弹窗
- **内容浏览类** → 壳内换页
- 知识点场景编辑器按此规则应归**弹窗**（它本来就是 560 宽弹窗设计），改回去可省掉 `home_screen.dart:250-270` 那 20 行兜底代码

### 其余

- **壳内切页零转场**：`_go` 直接 setState，body 瞬间替换；而 push 出去的页面有 Cupertino 滑动转场。同一 App 内两种观感。建议给 body 加一个 `AnimatedSwitcher`（100-150ms 淡入，尊重 `reducedMotionOf`）。
- **内容宽度一刀切**：`AppContentFrame` 默认 `contentWide 1080`。「我的」这种窄表单两侧大片留白。建议 `TeacherPage` 携带自己的 `maxWidth`（概览 1080 / 表单 560 / 我的 480）。
- **无统一页面标题条**：教师端页面各自画 header（`TeacherOverviewView._Header`），其余页未必有。紧凑档尤其明显。建议壳提供统一标题条（配合 P2-1）。

---

## 5. 做对的部分（不要动）

| 项 | 说明 |
|---|---|
| ADR-0059 单一导航状态 | `sealed TeacherPage` / `ChildPage` + `_go` 单一出口，根治了「谁压谁」的裁决 bug。改栈时**保留这个不变式**，栈只是历史不是第二真源 |
| 四态统一 | `AppLoading` / `AppError` / `AppEmptyState` / 分页 footer，全站同一语言 |
| 键盘可达 | `AppFocusableAction` 全覆盖 + `ReadingOrderTraversalPolicy`（`main/app.dart:142-147`） |
| 三档自适应 + 宽度令牌 | `AdaptiveShell` 只看 `constraints.maxWidth`，`AppLayout` 令牌无裸数字 |
| `AppPushedPage` 的逃生理赔 | `showBack` 默认 true + Esc 可退，把「出路」从每页自觉改成结构默认 |
| AI 单入口 | 双端统一浮球 → push 整页，页内三模式不叠三层栈（ADR-0047/0048） |

---

## 6. 落地顺序（按依赖排序）

| # | 项 | 优先级 | 依赖 | 备注 |
|---|---|---|---|---|
| 1 | 抽屉点项自动关闭 | P1（体感最大） | — | 一行，独立提交 |
| 2 | `PopScope` 接管返回键 | P0 | — | 需要「当前页有没有 back」的判定 |
| 3 | 壳持有 `List<TeacherPage>` 历史栈，取代手工 `back` | P1 | 2 | 与 2 同一份数据源，建议一起做 |
| 4 | 学生端 profile 进 IndexedStack 第 5 槽 | P1 | — | 可删 `_refreshChildTab` |
| 5 | 菜单改名（资料库/素材库）+ 分组 header | P1 | — | 纯 UI，无逻辑改动 |
| 6 | 「学生」+「班级管理」合并 | P2 | 3 | 依赖返回栈收敛 |
| 7 | 系统项收进「我的」 | P2 | 5 | |
| 8 | 侧栏徽标（任务草稿数） | P2 | — | `trailing` 槽位已存在 |
| 9 | 壳内切页 `AnimatedSwitcher` | P2 | — | 尊重 reduce-motion |
| 10 | `TeacherPage` 携带 `maxWidth` | P2 | — | |
| 11 | 页面路径序列化 + 重启恢复 | P1（结构性） | 3 | 不引入 go_router |
| 12 | stale-while-revalidate 统一刷新 | P2 | 4 | |

**建议批次**：`1` 单独一提交；`2+3` 一提交（同一份返回栈）；`4` 一提交；`5` 一提交；其余各自独立。
