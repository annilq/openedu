# ADR-0014 Step ③：AdaptiveShell 响应式导航壳 + 学科色消费

> 日期：2026-08-28 · 前置：ADR-0014 Step ①②（双模式已落主题层）
> 目标：把 `DesktopShell` 升级为数据驱动的 `AdaptiveShell`，按断点切换三档布局；并把学科色接到娃娃端学科徽章。

## 改动清单

### 1. 新增 `frontend/lib/shared/widgets/adaptive_shell.dart`
- `AdaptiveNavDestination`：数据驱动导航项（icon / label / active / onTap / trailing）。**同一份定义**同时喂给侧栏、底栏、抽屉三种形态，保证选中态与回调唯一来源。
- `AdaptiveShell`（ConsumerStatefulWidget）：`LayoutBuilder` 取宽度，按断点分流：
  - **expanded ≥1024**：展开侧栏 240 + 内容。
  - **medium 700–1023**：收起图标轨 64/240（`_collapsed` 持久化，复用 `storageServiceProvider`）。
  - **compact <700**：
    - 娃娃端（`AppUserMode.child`）= 底部导航（自绘 `Row`+`GestureDetector`，**不用 Material 的 `BottomNavigationBar`**）。
    - 家长端（`AppUserMode.parent`）= 顶部汉堡条 + 左抽屉（`Stack`+`AnimatedPositioned` 滑入 + `scrim` 遮罩，**不用 Material 的 `Drawer`/`Scaffold`**）。
  - 侧栏/轨态复用既有 `AppSidebar` + `AppSidebarItem`（经 `SidebarCollapseScope`）；紧凑态自绘，避免引入需要 Material 祖先的控件（根 `ShadApp` 无 Material 祖先）。
- `_BottomNavItem` / `_DrawerItem` / `_CompactTopBar`：紧凑态三件套。
- `AdaptiveUserBlock`：导航壳底部用户区（侧栏/轨/抽屉共用），收缩态只显头像、展开态显名称+副标题（年级/家长账号）。

### 2. `frontend/lib/features/home/presentation/screens/home_screen.dart`
- 移除 `DesktopShell` / `ParentSidebar` / `ChildSidebar` 依赖，改用 `AdaptiveShell`。
- 新增 `_parentDestinations` / `_childDestinations` / `_profileDestination` / `_parentTap`：
  - 家长目的地与旧 `ParentSidebar` 同序（0–4 + 6 题库）；审核覆盖层存在时先关层再切换（保留旧侧栏 `onNavTap` 行为）。
  - 副标题：家长「家长账号」、娃娃「${grade}年级」。
- 删除的两个旧侧栏文件已清理（仅 `HomeScreen` 引用）。

### 3. `frontend/lib/shared/theme/app_theme.dart`
- `AppColors` 新增 `scrim` 令牌（固定半透明黑 `0x66000000`，亮/暗同值），供抽屉遮罩使用，避免运行时 `withValues(alpha:)` 伪造（延续 Step ① 的规范一致性纪律）。

### 4. 学科色消费（娃娃端徽章）
- `child_home.dart` `_TaskCard`：单科任务标签由 `AppTags.normal(subject)` → `AppTags.subject(SubjectAccent.fromName(subject))`；多科仍用中性 `AppTags.normal('多科（n）')`。
- `practice_question_view.dart`：做题页学科标签由 `AppTags.normal(q.subject)` → `AppTags.subject(SubjectAccent.fromName(q.subject))`。
- 学科色按 `SubjectAccent.fromName` 解析（数学蓝 / 语文玫瑰 / 英语翠绿 / 其它灰），未知学科归 reserved，不破坏既有标签语义。

### 5. 删除的死代码
- `desktop_shell.dart`（`DesktopShell`）、`parent_sidebar.dart`（`ParentSidebar`）、`child_sidebar.dart`（`ChildSidebar`）—— 均仅被 `HomeScreen` 引用，已被 `AdaptiveShell` + 数据驱动目的地取代。

## 验证
- `flutter analyze` → **No issues found**（含 `unnecessary_const` 修复）。
- 真机/模拟器：拖拽窗口宽度即可观察三档切换；娃娃端底部导航、家长端汉堡抽屉；切「娃娃模式」后学科标签带学科色。

## 遗留 / 下一步
- **掌握度可视化（mastery）**：娃娃端目前无掌握度视图，学科色尚未在掌握度条上消费。建议在家长端 `ParentOverviewView` 的掌握度/薄弱点条形图按学科色着色（家长端也可借学科色区分多科），作为 Step ③ 的延伸。
- 断点阈值（700 / 1024）已写入 `.impeccable.md`「Responsive Breakpoints」，后续新增页面直接复用 `AdaptiveShell` 即可。
