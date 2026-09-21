# 前端硬规则（Frontend）

> 本文件是 `AGENTS.md`「前端」条目的**细节展开**。入口只给一句话结论，正文在这里。
> 视觉（颜色 / 描边 / 选中悬停焦点 / 空态）不在本文件，见 `.impeccable.md` 与 ADR-0044~0048。

---

## 1. 前端分层（ADR-0037）

`main/ → features/* → shared/*` 单向，**`shared/` 不得 import `features/`**；feature 之间不得横向互引
（唯一豁免 `features/home/presentation/`，展示层组合根）；feature 与后端 `app/features/*` 一一对应。

`App*` 前缀只给 `shared/widgets/` 通用组件——**组件一旦订阅某 feature 的 provider 就落回该 feature**。
守卫 `frontend/test/feature_boundaries_test.dart`（静态扫描）。

---

## 2. 自适应布局与键盘可达性（ADR-0045）

布局决策**只**基于可用宽度（`LayoutBuilder` 的 `constraints.maxWidth`），**禁止**
`MediaQuery.of(context).size.width`（那是屏宽，不是可用宽度）、禁止 `orientationOf`、
禁止 `isTablet`/`isDesktop` 这类设备形态判定。

断点与内容宽度一律走 `AppLayout` 令牌（`compactMax 700` / `largeMin 1200` / `contentWide 1080` /
`contentReading 820` / `contentCard 520` / `contentNarrow 480` / `contentEmpty 440` / `contentFloat 380`），
**禁止写裸数字**。

> `largeMin 1200` 常量仍在但**无代码消费者**（ADR-0059 移除 master-detail 后大屏档无独立编排）。

宽度上限由 `AdaptiveShell` 统一兜底，`Navigator.push` 的整页需自带约束（走 `AppContentFrame`，
守卫 `test/content_frame_guard_test.dart`）。

**可点区域一律用 `AppFocusableAction`**——裸 `GestureDetector` 不进焦点树 → 桌面端 Tab 跳不过去、
Enter 点不动，而 `flutter analyze` 照不出来。

守卫：`test/adaptive_shell_layout_test.dart` + `test/app_focusable_keyboard_test.dart` +
`test/no_bare_gesture_guard_test.dart`。

---

## 3. 导航状态必须单一（ADR-0059）

家长端「当前页面」只能是 `sealed _ParentPage _parentPage` 一个状态，所有入口
（侧栏 / 底部用户区 / 侧栏头部 / 助手卡片跳转）都只调 `_go(page)`。

**禁止**再加「索引 + 覆盖层（审核 / 编辑）+ 布尔（我的）」这类并列状态——并列即需「谁压谁」的裁决，
而裁决散在各回调里必然漏清。实测事故：审核中从底部点「我的」，看到的是审核页，
个人信息**根本没进渲染树**（不是被盖住）。`flutter analyze` 照不出来。

`AdaptiveShell` 只有 `body` 一个宿主，**不得**再加 `detail`。
守卫 `frontend/test/parent_nav_single_source_test.dart`。

⚠️ **`_onProfileTap` 这类回调是两个角色共用的**（家长端侧栏底部 / 娃娃端底栏都指向同一个
`_profileDestination`），而两端「当前页面」的载体不同（家长端 = `_ParentPage` 分支，
娃娃端 = 「页签 + `_showProfile` 布尔」二选一）。改这类回调时**两个角色都要各走一遍**——
只写家长端那份，娃娃端点「我的」就毫无反应，而 `flutter analyze` 照不出来。

---

## 4. 文件规模与组件编写（ADR-0058）

| 对象 | 上限 |
|---|---|
| 单个 .dart 文件 | **400 行**（`lib/dev/**` 与生成代码豁免） |
| 单个 `build` 方法 | 60 行 |
| 单个私有方法 | 40 行 |
| 单文件私有 widget 类 | 3 个 |

- **一个文件只暴露一个公开物**（一个 widget / 一个聚合模型 / 一个 provider）；私有实现类可同文件。
  `assistant_cards.dart`（825 行）不是「一个大文件」，是**九个文件被拼在了一起**。
- **页面按 Page → Section → Widget 三层写**：Page 管路由与跨区块状态，Section 管一个区块，
  Widget 只做展示（不许 `ref.watch` / 网络 / 导航）。80+ 行的 `_buildXxx` 私有方法，
  正确去向是提成 Section widget。
- **抽到 `shared/` 需三条全中**：≥2 个真实调用点 + 不 import 任何 `features/` + 只抽形状不抽取值。
  只有一个调用点的留在原文件当私有 widget——提前抽象会把「这一页的概念」污染成「全站概念」。
- **四态一律走** `AppLoading` / `AppError` / `AppEmptyState`；**分页列表一律走**
  `AppCardSliver` / `AppCardList` + `AppPagingFooter`，不许自己拼 `CustomScrollView` + `SliverPadding`。
- **枚举→文案只在 `labels.dart` 写一次**，widget 里不许出现 `switch (status) => 文案`。
- **Rule of Two**：第二次抄同一段结构就必须收口，不许留「与某处同口径」的注释。

守卫 `frontend/test/file_size_guard_test.dart`——未登记文件 ≤400 行直接拦；
已登记的存量超限文件走**基线只许下调**的棘轮（不强迫现在就拆，但保证不再变长）。

---

## 5. 助手页面形态（ADR-0047 / ADR-0048）

- **AI 助手是整页，不是浮层**（ADR-0047）：家长端右下角浮球 `Navigator.push` 打开
  `AssistantChatPage`（`isParent: true`），娃娃端是「问 AI 老师」页签——同一个页面、同一份会话。
  push 的整页**不在壳的宽度兜底范围内**，页面自己套 `contentWide`。
- **会话历史是页内切模式，不是三层栈**（ADR-0048）：家长端助手页在**页内**切
  `chat` / `history` / `reading` 三态（顶栏就是模式切换器），不新增路由。列表分两段——
  「我的对话」点开**恢复续接**、「孩子的对话」点开**只读回放**：后者不是 UX 取舍，是后端语义
  （家长拿孩子的 `session_id` 续接会另建会话并污染 prompt 历史）。
  读路径是家长专属端点 `GET /assistant/conversations` + `/{id}`，**不与** `/ai/debug/conversations` 复用。
  `reset()`（新对话）与 `resume()`（续接）都在 `assistantNotifier`。

---

## 6. 前端守卫测试一览

| 守卫 | 拦什么 |
|---|---|
| `feature_boundaries_test.dart` | 分层方向 / feature 横向互引 |
| `content_frame_guard_test.dart` | 手抄宽度约束（须走 `AppContentFrame`） |
| `adaptive_shell_layout_test.dart` | 壳布局兜底（须 `Align(topCenter)` + 约束） |
| `app_focusable_keyboard_test.dart` / `no_bare_gesture_guard_test.dart` | 裸 `GestureDetector`（不进焦点树） |
| `stretch_row_guard_test.dart` | `Row(stretch)` 未包 `IntrinsicHeight` |
| `control_height_test.dart` | 控件高度锚点（`ShadButton.height` 是内容盒高） |
| `tab_screen_no_root_pop_test.dart` | 非 push 路由页面裸 `Navigator.pop`（会弹空根栈） |
| `file_size_guard_test.dart` | 文件规模（ADR-0058 棘轮） |
| `parent_nav_single_source_test.dart` | 家长端导航多状态并列（ADR-0059） |

## 7. 测试与截图探针的五个坑

写 widget 测试 / 截图探针时踩过的坑，每一条都会「静默挂死」或「量到错的数」：

- ⚠️ **`toImage()` 与 `FontLoader` 前的 `readAsBytes()` 必须包 `tester.runAsync`**，否则 fake-async 区 await 永不返回 → 挂死 exit 137。真字形需 `assets/fonts/{Inter,NotoSansSC}.ttf`。
- ⚠️ **`ShadApp.custom` 不传 `theme:` 走 shadcn 默认主题** → 量到数与产品不符；必传 `AppTheme.shadFor(false, mode, density)`。`SizedBox(width: 2000)` 给不了 2000px 视口（surface 默认 800×600 会裁 → 断点静默测错档）→ 用 `setSurfaceSize` + `addTearDown`。
- ⚠️ **别直接调 pdfx `PdfDocument.openData`**：无原生一侧时 Future 既不完成也不报错 → 挂死；走 `pdfDocumentOpenerProvider` 注替身；catch 掉的异常也要 `debugPrint`。
- ⚠️ **`pumpAndSettle` 只按「还有没有下一帧」推进**：悬挂 `Timer` 不排帧 → 显式 `pump(delay)`；含 spinner 的子树必然超时。`AnimatedSwitcher` 退场要推**两档时长**。
- ⚠️ **`pumpWidget` 根之上没有 MediaQuery 祖先** → 注入 reduce-motion 要把 `MediaQuery` 放在 `CupertinoApp`/`ShadApp` 之内；直接给 `MediaQueryData(disableAnimations: true)` 会把 size 变 `Size.zero`。
