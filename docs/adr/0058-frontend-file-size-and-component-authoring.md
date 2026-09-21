# 前端文件规模与组件编写规范

> 状态：已接受 · 2026-09-21
> 关联：ADR-0037（前端分层）· ADR-0042/0054（助手卡片协议）· ADR-0044（视觉语言）·
> ADR-0045（自适应布局）· ADR-0046（导航交互语言）· ADR-0051（空态语言）
> 配套：分析见 `docs/refactor/2026-09-21-flutter-ui-decomposition.md`；
> 自动守卫见 `frontend/test/file_size_guard_test.dart`

## 背景

`frontend/lib` 现状（138 个 .dart / 25,620 行）：

| 规模 | 文件数 | 总行数 | 占 lib |
|---|---|---|---|
| ≥900 行 | 3 | 4,835 | 18.9% |
| 600–900 | 6 | 4,469 | 17.4% |
| 400–600 | 7 | 3,271 | 12.8% |
| 200–400 | 24 | 6,640 | 25.9% |
| <200 | 98 | 6,405 | 25.0% |

**16 个 ≥400 行的文件 = 11.6% 的文件数，占 48.6% 的代码量。** 它们「大」的成因有四种，
处理方式完全不同，这也是本 ADR 不设「统一按行数切分」规则的原因：

| 成因 | 例子 | 症状 |
|---|---|---|
| A 令牌文件里塞了 widget | `shared/theme/app_theme.dart`（2740，含 12 个 widget） | 改一个按钮要打开 2740 行的主题文件 |
| B 数据模型不按聚合分文件 | `shared/domain/models/models.dart`（902） | 找 `TaskModel` 要靠全文搜索 |
| C 页面骨架 / 列表 / 筛选 / 导出被抄了多遍 | 8–10 处 | 改一处漏三处，`_statusLabel` 已在注释里自认「同口径」却仍是两份 |
| D 页面本身就是组合根或表单编辑器 | `home_screen` / `task_form` / `task_review` / `assistant_cards` | 一个文件装了路由 + 状态 + 弹窗 + 卡片 |

**行数不是问题本身，是「职责混装」的症状。** 所以规范的重点是「一个文件装什么」，
行数只是它的可自动检测的代理指标。

## 决策

### 1. 硬阈值（超出即须拆分或登记例外）

| 对象 | 上限 | 说明 |
|---|---|---|
| 单个 .dart 文件 | **400 行** | `lib/dev/**` 与生成代码除外 |
| 单个 `build` 方法 | **60 行** | 超出说明里面塞了区块，区块应提为私有 widget |
| 单个私有方法 | **40 行** | |
| 单文件内私有 widget 类 | **3 个** | 超出说明这个文件在当目录用，应拆成同目录多个文件 |

400 这个数取自现状：**71% 的文件已经在 200 行以内**，400 对新增代码不构成压力，
又足以拦住下一个 `parent_question_bank_view.dart`（838）。

例外只有两类，且必须在文件头注释写明理由：`lib/dev/**`（视觉走查台，长是它的天性）、
生成代码（`*.g.dart` / `*.freezed.dart`）。

### 2. 一个文件只装一个公开物

一个 .dart 文件只能暴露**一个**公开 widget、或**一个**聚合的模型、或**一个** provider。
它的私有实现类（`_XxxState` / `_TagChip`）可以同文件；**别的** widget 一律另开文件。

推论：`assistant_cards.dart`（825 行，9 种卡片）不是「一个大文件」，是**九个文件被拼在了一起**。
（2026-09-21 同日已按此推论拆开，见 `docs/refactor/2026-09-21-flutter-ui-decomposition.md` §8。）

### 3. 抽公共组件有三条门槛，三条全中才进 `shared/`

本仓已经有一批反例：`AppSelectStrip`（2 处抽出，正确）不能当成「什么都该抽」的先例。
**只有一个调用点的东西不许进 `shared/`**——那不是复用，是提前抽象，它会把「这一页的概念」
污染成「全站概念」，改这一页时要先读懂一个通用组件。

三条门槛：

1. **≥2 个真实调用点**（不是「将来可能用到」）；
2. **不 import 任何 `features/`**（ADR-0037；`feature_boundaries_test` 会拦）；
3. **形状稳定**——只抽「结构」，不抽「这一次的取值」。间距、颜色仍由调用方传令牌。

只有一个调用点的，就留在原文件里当私有 widget：`_MonthSections`、`_usageTag` 都是对的。

### 4. 页面按三层写：Page → Section → Widget

| 层 | 职责 | 不许有 |
|---|---|---|
| **Page**（`screens/`） | 路由、壳协作、跨区块状态、导航 | 具体排版细节、卡片内部结构 |
| **Section**（`widgets/`） | 一个区块：自己的筛选 / 列表 / 操作条 | 别的区块的逻辑 |
| **Widget**（`widgets/` 私有或独立文件） | 纯展示，入参进来、像素出去 | `ref.watch`、网络、导航 |

`_buildParentBody` / `_buildSummary` 这类 80+ 行的私有方法，正确去向是提成一个 Section widget，
不是继续在 Page 里加 `_buildXxx`。

### 5. 加载 / 错误 / 空 / 有数据 四态不许散在页面里

每个列表页都在手抄同一段 `if (isLoading) … else if (error) … else if (empty) …`，
且每次手抄都会漏一态（ADR-0051 记录的正是这件事）。

- 三态一律走 `AppLoading` / `AppError` / `AppEmptyState`（空态必须回答「为什么空」与「下一步做什么」）；
- 分页列表一律走统一脚手架（`AppCardSliver` / `AppCardList` + `AppPagingFooter`），
  **不许自己拼 `CustomScrollView` + `SliverPadding`**；
- 空态不许手搓 `_EmptyHint`。现存的 2 处（`parent_question_bank_view` / `parent_task_review_screen`）是漏网的，已登记待改。

### 6. 枚举 → 文案只许存在一处

`_statusLabel` / `_qtypeLabel` 各写了两份，其中一份的注释就写着「与某处同口径」——
**写下这句注释时就已经知道该收口了，但没做。**

- 文案表放 `shared/domain/labels.dart`（跨 feature）或 `features/<x>/domain/`（单 feature）；
- widget 里**不许**出现 `switch (status) { 'draft' => '草稿' … }`；
- 再遇到「与某处同口径」，直接收口，不许留注释。

### 7. Rule of Two：第二次抄就该收口

第一次实现可以直接写；**第二次出现同一段结构，就必须收口**，没有「先复制一份改改」这个中间态。
收口时只抽形状，取值留在调用点（见门槛 3）。

### 8. 自动守卫：文件规模棘轮

新增 `frontend/test/file_size_guard_test.dart`，两条断言：

1. **未登记的文件不得超过 400 行**——新增代码直接被拦住，这是本 ADR 的主要执行力；
2. **已登记的文件不得超过其基线行数**——现存的超限文件登记在测试的 allowlist 里，
   基线**只许下调不许上调**：拆小了基线跟着调小，长回去就测试失败。

第 2 条是棘轮（ratchet）：它不强迫任何人现在就去拆分那批文件，
但保证**它们不会继续变长**，且每拆掉一个就从 allowlist 里删一条。
有意增长某个已登记文件时，必须同步调高基线并在 commit 正文说明理由——这个摩擦是故意的。

> **⚠️ 下表是 2026-09-21 立 ADR 时的快照（14 项）。基线的事实源是
> `frontend/test/file_size_guard_test.dart` 的 `_baseline`，不是这张表。**
> 同日按 `docs/refactor/2026-09-21-flutter-ui-decomposition.md` 的 P0–P4 执行后，
> `models.dart` / `assistant_cards.dart` / `parent_task_form_view.dart` /
> `parent_task_review_screen.dart` 四条已拆到 400 以下并删除登记（现剩 11 项）。

| 文件 | 基线 |
|---|---|
| `shared/theme/app_theme.dart` | 2740 |
| `shared/domain/models/models.dart` | 902 |
| `shared/widgets/adaptive_shell.dart` | 488 |
| `features/home/presentation/widgets/parent/parent_question_bank_view.dart` | 838 |
| `features/assistant/presentation/widgets/assistant_cards.dart` | 825 |
| `features/home/presentation/widgets/parent/parent_task_form_view.dart` | 812 |
| `features/home/presentation/screens/parent_task_review_screen.dart` | 732 |
| `features/home/presentation/widgets/parent/parent_tasks_view.dart` | 649 |
| `features/home/presentation/screens/home_screen.dart` | 656 |
| `features/assistant/presentation/screens/assistant_chat_page.dart` | 555 |
| `features/home/presentation/widgets/parent/parent_question_card.dart` | 511 |
| `features/home/presentation/widgets/parent/parent_wrong_questions_view.dart` | 438 |
| `features/home/presentation/widgets/child_home.dart` | 423 |
| `features/home/presentation/widgets/parent/parent_overview_view.dart` | 406 |

> 拆分批次（P0–P4）见 `docs/refactor/2026-09-21-flutter-ui-decomposition.md`，
> **待当前进行中的任务结束后执行**。每拆掉一个文件，同步从 allowlist 删除该条。

## 新页面 / 新组件检查清单

写完后逐条过：

- [ ] 文件 ≤ 400 行；`build` ≤ 60 行；私有方法 ≤ 40 行；私有 widget ≤ 3 个
- [ ] 只暴露一个公开物
- [ ] 没有手抄页面骨架（`AppContentFrame` + `SectionTitle` + `AppCard`）——走统一骨架
- [ ] 没有自己拼分页列表——走 `AppCardSliver` / `AppCardList` + `AppPagingFooter`
- [ ] 四态走 `AppLoading` / `AppError` / `AppEmptyState`，没有手搓空态
- [ ] 没有 `switch (枚举) => 文案`，文案在 `labels.dart`
- [ ] 没有裸 `GestureDetector`（ADR-0046）、没有裸数字做布局/描边（ADR-0044/0045）
- [ ] 想抽到 `shared/` 的东西：有 ≥2 个调用点吗？有就抽，没有就留在本文件
- [ ] `flutter analyze` 零 issue；`flutter test` 通过（守卫会替你查上面大半条）

## 与既有 ADR 的关系

本 ADR **不重复** ADR-0044/0045/0046 的视觉与交互规则，只补「文件装什么 / 多大」这一层。
那些 ADR 管「长什么样」，本 ADR 管「放哪里、多大」。
