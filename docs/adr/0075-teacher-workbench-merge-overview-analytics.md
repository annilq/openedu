# ADR-0075 教师工作台合并概览与学情统计

- 状态：提案（待评审）
- 日期：2026-10-08
- 关联：ADR-0070（重构教师端导航，本 ADR 修订其 §2.3 的独立「统计」页决策）、ADR-0068（Class，统计分组来源）、ADR-0059（单源导航）、ADR-0058（文件规模）、ADR-0044（新粗野视觉）、ADR-0064（题库硬删 → 孤儿错题）、ADR-0061 §U（读路径唯一入口）

## 1. 背景（Context）

教师端侧栏当前 10 项（`teacher_destinations.dart:35-92`）：概览 / 任务 / 布置任务 / 学生 / **统计** / 题库 / 资料库 / 模型管理 / 课件 / 场景库。其中**概览**（`OverviewPage` → `TeacherOverviewView`）与**统计**（`AnalyticsPage` → `AnalyticsScreen`）是两个并列入口，且都面向"教师视角的工作台"。

复盘两页真实实现后发现一处**数据层重叠**，并非单纯的功能并列：

- 概览的 analytics 部分（`teacher_overview_provider.dart`）直接复用 `analyticsRepository` 的两个聚合端点——
  `getWrongDistribution(scope='all', dimension='knowledge_point')` 与 `getMastery(scope='all')`——**参数写死**，仅做"进入即看的速览"。
- 统计页（`analytics_screen.dart`）调用**同一仓库的同一三个端点**，但带 `scope` / `dimension` 选择器做下钻。

即：概览的"掌握度概览 + 薄弱知识点"**完全可由统计页在 `scope=all / dimension=knowledge_point` 下复现**；`teacherOverviewProvider` 本质是对 `analyticsRepository` 的重复消费（写死参数版）。`teacher_overview_provider.dart:9` 注释的"分工"是**人为约定**，不是架构隔离，违反了 ADR-0059 的"单源"精神（虽然不是导航状态双源，但是数据意图双源）。

两页的**非重叠**部分：

| 页 | 独有内容 |
|---|---|
| 概览 | 待办、最近任务、学生总数徽标——**任务/学生管理**，非统计 |
| 统计 | 正确率聚合 + 作用域（all/class，单学生已在前序任务移除）/ 维度（学科/年级/学期/知识点）下钻 |

此外，项目当前**零图表库**（本 ADR §2.3 决策引入 fl_chart 改变此现状），两页都是纯文字指标行（`analytics_screen.dart:_MetricRow`、`teacher_overview_view.dart:_StatRow`），KPI 看板场景下"一眼读懂"能力弱。

> ADR-0070 的内部张力：§2.1 已写明"概览改为教师工作台"，§2.3 却又新增了独立的「统计」页。本 ADR 把两者统一，消解该矛盾。

## 2. 决策（Decision）

### 2.1 合并为单一「教师工作台」入口，移除独立「统计」侧栏项

- 删除 `AnalyticsPage` 子类 + `teacher_destinations.dart` 对应入口 + `home_screen.dart` 的 `AnalyticsPage() => …` 映射分支。
- 保留 `OverviewPage` 作为唯一 landing 状态（`TeacherPage` 这个 `sealed` 仍是唯一导航状态，ADR-0059 不变），**UI 标题改为「工作台」**，默认进入。
- 侧栏 10 项 → 9 项，顺序不变（仅去掉「统计」）：概览(工作台) / 任务 / 布置任务 / 学生 / 题库 / 资料库 / 模型管理 / 课件 / 场景库。
- `teacher_nav_single_source_test.dart` 须扩展：移除 `AnalyticsPage` 相关断言，确认 `OverviewPage` 为默认高亮且全树无双高亮漏清。

### 2.2 工作台页面三段式结构

| 区段 | 内容 | 来源 |
|---|---|---|
| **任务区**（保留，非统计） | 待办（`TeacherTodoSection`）+ 最近任务（top 4）+ 学生总数徽标 | 现有概览头部与任务 widget，原样保留 |
| **速览层**（图表化） | 错题分布 / 正确率 / 掌握度 **三块全放**（用户决策）；作用域固定 `all` | 取代现有概览的纯文字"掌握度概览 + 薄弱知识点"，并补齐错题分布与正确率总览 |
| **分析层**（图表化 + 下钻） | 原统计页 body：作用域 all/class + 维度 4 选 + 三聚合（错题分布/正确率/掌握度） | 迁移自 `analytics_screen.dart`，复用 `analyticsNotifier` 与三个现有端点 |

速览层保留概览最有价值的转化入口——薄弱知识点的「就这个出题」行动钩子（跳转出题并预填知识点，ADR-0070/ADR-0072 既有链路）。

### 2.3 图表：引入 fl_chart + 项目适配器（非裸用）

- **引入 `fl_chart` 作为渲染引擎**，但**严禁业务页裸用** `BarChart` / `PieChart` / `RadialBarChart`。所有图表经一层项目适配器（`analytics_charts.dart` 内的 `AppBarChart` / `AppDonutChart` / `AppGroupedBarChart` / `AppStackedBarChart`）注入新粗野令牌，保证视觉一致、防止风格漂移。
- **视觉对齐手段**（fl_chart 出厂皮肤是圆角+渐变+软阴影，必须逐图表覆盖）：
  - `borderRadius: 0` 直角；
  - 条形/扇区 `borderColor: outline, borderWidth: 2`（`AppElevation.borderWidth`）；chip 级小标记用 `borderWidthSm=1.5`；
  - 配色走 `AppColors`（纸底 `surfaceRaised` / 墨黑 `outline` / 强调色块），禁用 fl_chart 默认蓝紫渐变；
  - 卡片级硬阴影由 `AppTheme` 的 `_floatingShadows` 承载，**图表元素本身不画模糊阴影**（fl_chart 不支持无模糊偏移阴影，故不强行模拟，靠卡片 2px 描边 + 硬阴影表达粗野质感）。
- **交互层（采用 fl_chart 的关键理由）**：fl_chart 内置 `BarTouchData` / `PieTouchData` 提供点按高亮、悬浮 tooltip、active 区段反白，开箱即用；薄弱知识点的「点击钻取分析层」可直接挂 `BarTouchData.onTouchCallback`，无需自绘命中测试。这比手写 `CustomPaint` 自实现手势 + tooltip 工作量小且体验一致——满足工作台"既要功能又要交互体验"的要求。
- **Material 祖先验证关（落地前必过）**：本项目全仓禁用 Material 控件，根树为 `ShadApp`+`CupertinoApp`、无 Material 祖先；fl_chart 走 `CustomPaint`+`GestureDetector`，理论上不需要 Material，但鉴于硬禁令，**加依赖后必须先做一次空构建冒烟测试**，确认其未内部引用任何 Material widget（否则构建期即崩「No Material widget found」）。
- 具体图表映射：

  | 指标 | 图表类型（fl_chart） | 交互 |
  |---|---|---|
  | 掌握度概览 | `PieChart`（带孔）或 `RadialBarChart`（环形仪表，中心 `X/Y`） | tooltip 显示已掌握/剩余 |
  | 薄弱知识点 | `BarChart`（horizontal），按 `activeWrong` 降序，颜色按 `accuracy` 分级（红<60 / 琥珀 60–85 / 绿>85） | 点击 → `onTouchCallback` 钻取分析层预选该知识点 |
  | 正确率 | `BarChart` 分组横向条（练习/复习/总体）；速览层亦可用单个大数字 | tooltip 分源显示 |
  | 错题分布 | `BarChart` 竖向堆叠（活跃 vs 毕业） | tooltip 分项 |
  | 掌握度(分析层) | `BarChart` 按知识点条形 + `badgeWidget` level 徽章 | tooltip |
  | 学科×年级热力图 | ⚠️ fl_chart 无原生热力图，**可选**：自绘 `GridView` 色块或推迟 | — |

- **孤儿「未知」组**（ADR-0064 / ADR-0070 §2.4.3 强制显式标注）在图表中以**警示色条**保留，禁止丢弃或混入有效分组。

### 2.4 文件规模护栏（ADR-0058 硬约束）

合并后长页必然超过 `analytics_screen.dart` 已登记的 488 基线 / 400 行新文件护栏。须把页面拆为子文件，主文件只做组合与状态路由：

- `analytics_charts.dart`：fl_chart **适配器层**——`AppBarChart` / `AppDonutChart` / `AppGroupedBarChart` / `AppStackedBarChart` 等，内部强制注入新粗野令牌（borderWidth=2、borderRadius=0、outline 配色）与统一 tooltip/触摸交互，业务页只调适配器、不碰裸 fl_chart。
- `workbench_glance.dart`：速览层（3 张图表卡 + 薄弱知识点列表 + 出题钩子）。
- `workbench_analysis.dart`：分析层（控制条 + 3 张聚合卡，迁移自 `analytics_screen.dart` body）。
- `teacher_overview_view.dart`：工作台壳——头部 + 任务区 + 速览层 + 分析层组合；**删除 `teacherOverviewProvider`**。

拆完后调用 `test/file_size_guard_test.dart` 的 `_baseline` 调低到新主文件实际行数；每个子文件各自登记基线。

### 2.5 数据层去重

- **删除** `teacher_overview_provider.dart` 与 `TeacherOverviewNotifier`（重复消费 `analyticsRepository`）。
- 速览层与统计页共用 `analyticsNotifier` 在 `scope=all` 下的取数结果；若首屏不想一次拉全维度，新增一个**只读 `scope=all` 维度**的轻量 `analyticsSummaryProvider`（仍走同一仓库、同一端点，不做第二次聚合实现），不做任何新的后端逻辑。

## 3. 后果（Consequences）

**正**

- 单一入口、无重复取数、看板可视化提升"一眼读懂"能力。
- 消解 ADR-0070 的内部张力（§2.1 工作台 vs §2.3 独立统计页）。
- fl_chart 经适配器强制对齐新粗野令牌，且开箱交互（触摸 tooltip / 区段高亮）显著提升体验，开发量低于手写 CustomPaint。

**负**

- 工作台长页需分区 / 吸顶导航（速览层 vs 分析层的 sticky section header + 锚点跳转），否则滚动疲劳。
- 删除 `AnalyticsPage` 是**破坏性导航变更**（教师习惯的「统计」独立入口消失）；缓解：工作台内速览层即原统计的 `all` 切片，且分析层完整保留下钻。
- 新增 fl_chart 第三方依赖，须靠适配器层护栏防止风格漂移；落地前必须先过 Material 祖先构建冒烟测试（本项目禁用 Material 控件，fl_chart 内部若误用 Material widget 会构建期即崩）。学科×年级热力图 fl_chart 无原生支持，留作可选（自绘网格或推迟）。

## 4. 验证（Verification）

- 前端：`flutter analyze` 0 issue（`AnalyticsPage` 与 `teacherOverviewProvider` 移除后无残留引用）；`flutter test`（含 `task_empty_state_test` 仍引用 `TeacherOverviewView`、`teacher_nav_single_source_test` 扩展示例）；`file_size_guard_test` 不超标（拆子文件后）。
- 后端：**无改动**（本 ADR 是前端重组，端点保持）。端点级验证仍适用（统计数字必须打到 `GET /stats/*` 验，不能只改 service）。
- 图表：golden test 或快照验证环形/条形渲染；暗色模式令牌读取正确；孤儿组以警示色条出现。

## 5. 明确不做（Out of Scope）

- 后端新端点（复用现有 3 个聚合端点：`/stats/wrong-questions`、`/stats/accuracy`、`/stats/mastery`）。
- 时间趋势（按周/月）、学生横向对比排行榜、统计结果导出（ADR-0070 §5 已列）。
- 裸用 fl_chart（业务页直接 new `BarChart` / `PieChart` 绕过适配器）；适配器层是强制护栏，违反即风格漂移。
- 单学生作用域（已于前序任务移除，本 ADR 不恢复）。
- 移动 `teacherOverviewProvider` 之外的任务/学生管理 widget（待办、最近任务保留在工作台顶部）。
