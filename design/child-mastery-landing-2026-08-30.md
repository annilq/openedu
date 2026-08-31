# 娃娃端「我的学科掌握度」屏 — 落地说明（ADR-0014 Step③延伸·收尾）

> 日期：2026-08-30
> 关联：ADR-0014「学科色扩展」、Step② `SubjectAccent` / `AppTags.subject`、Step③ `AdaptiveShell`、上一延伸「家长端掌握度按学科色着色」
> 范围：把学科色掌握度看板补到娃娃端，闭环 ADR-0014 学科色消费

## 背景

上一延伸把家长端「知识点掌握度」看板按学科色着色，但娃娃端**根本没有掌握度视图**
（数据端点 `/tasks/children/{id}/mastery` 虽可复用，但娃端无对应屏）。ADR-0014 的
「娃娃端动力」目标要求娃能看到自己的学科掌握进展。本次补上娃端「我的学科掌握度」屏，
复用同一套学科色条 + 等级语义徽章。

## 改动

### 1. 抽出共享 `MasteryBoard`（避免重复）
`features/home/presentation/widgets/mastery_board.dart`（新）：
- 把原 `parent_overview_view.dart` 的 `_buildMastery` 逻辑 + `_MasteryBar` + `_levelBadge`
  抽到此处，成为家长/娃共用的 `MasteryBoard`（`ConsumerWidget`）。
- 新增 `isChild` 参数切换第一人称文案：
  - 标题：`已掌握` → `你已掌握`；空态提示：`先布置任务吧～` → `去做几道题，看看你掌握了什么吧～`。
- 进度条/行首色点按学科色、等级用语义徽章——逻辑与上一延伸完全一致，无回归。

`parent_overview_view.dart` 相应收敛：`_buildMastery` 退化为 `=> const MasteryBoard()`，
删除已迁走的 `_levelBadge` / `_MasteryBar` 死代码，并移除不再直接引用的 `models.dart` import。

### 2. 新增娃端屏 `ChildMasteryScreen`
`features/home/presentation/screens/child_mastery_screen.dart`（新）：
- `ConsumerStatefulWidget`，`initState` 用 `widget.user.id` 触发
  `masteryNotifierProvider.load(...)`（娃端以自身 id 拉取；家长端由 `selectedChildProvider` 触发）。
- 渲染 `SectionTitle('我的学科掌握度')` + `MasteryBoard(isChild: true)`，
  外层 `SingleChildScrollView` + `maxWidth: 1080` 容器，与 `ParentOverviewView` 版式一致。

### 3. `home_screen.dart` 接入娃端导航
- `_childDestinations` 追加第 5 项：`掌握度`（`LucideIcons.target`，index 4）。
  娃端导航现为：首页(0) / 复习(1) / 错题本(2) / AI伴学(3) / 掌握度(4) + 我的。
- `_buildChildView` 的 `IndexedStack` 在 index 4 增加 `ChildMasteryScreen(user: widget.user)`。
- 既有娃端 `onNavigateToX` 回调（指向 1/2/3）索引不变，无需改 `ChildHome`。
- 新增 import `child_mastery_screen.dart`。

## 设计权衡
- **抽出而非复制**：`_MasteryBar` 原是父文件私有组件，娃端无法复用。抽到 feature 级
  `mastery_board.dart`（与 provider 同 feature，不引入 shared→features 反向依赖），
  家长/娃共享，后续学科色规则只改一处。
- **娃端独立屏而非塞进首页**：掌握度作为底部导航一级入口，符合「娃娃端动力」——娃能自主查看。
- **数据权限**：端点按 childId 取，娃端传自身 id；后端鉴权是否放行属后端范畴，前端按自身 id 调用是正确形态。

## 验证
- `flutter analyze` → **No issues found**（修了三处：娃屏缺 flutter 基础 import、
  `ConsumerState.build` 误用 `(BuildContext, WidgetRef)` 双参、`parent_overview` 调用点残留 `ref` 实参）。

## ADR-0014 状态
至此 ADR-0014 全部落地：
- ① 规范一致性审计与清除（withValues / 阴影 / 描边）
- ② 双模式（Child/Parent 字号阶梯 + 学科色 + `AppUserMode`）
- ③ 响应式 `AdaptiveShell`（compact/medium/expanded）
- 延伸A：家长端掌握度按学科色着色
- 延伸B（本次）：娃娃端「我的学科掌握度」屏，学科色消费在两端闭环

## 后续可选
- 娃端首页加一个「查看我的掌握度」CTA 卡片，引导进入该屏（当前仅靠底部导航入口）。
- 做题/复习完成后回到该屏时刷新掌握度（当前 IndexedStack 保活不自动刷新，可在 `onDone` 补 `masteryNotifierProvider.load`）。
