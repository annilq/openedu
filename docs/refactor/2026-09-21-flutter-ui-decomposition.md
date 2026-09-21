# Flutter 前端大文件拆分分析

> 日期：2026-09-21 · 范围：`frontend/lib`（138 个 .dart，25,608 行）
> **规范已落地为 [ADR-0058](../adr/0058-frontend-file-size-and-component-authoring.md)**（含自动守卫
> `frontend/test/file_size_guard_test.dart`）。本文是那 16 个存量文件的**拆分批次**，待当前进行中的任务结束后执行。
> 结论先行：**可以抽，但只有约一半的「大」该由公共组件解决**。剩下的一半是「组合根 / 表单编辑器 / 开发工具」，
> 硬抽公共组件会造出一批只有一个调用点的「通用组件」，反而降低可维护性。

> ## 📌 复核记录（2026-09-21 22:55，ADR-0059 导航收敛合入后）
>
> 另一会话的 `d695eed`/`60576e0` 已合入（家长端导航收敛为单一页面状态）。本次逐条实测复核结论：
> **本文的「结构结论」全部仍然成立，「数值与行号引用」有 7 处失效**（已在正文中就地更正，标记 🔄）。
> 数值变动很小（lib 总量 25,620 → 25,608），**不影响 P0–P4 的批次划分与执行顺序**。
>
> 更正清单：`home_screen` 610→655（§1/§2）· 分布表数字（§1）· `profile_screen` 已删除（§3.6）·
> `AppContentFrame` 调用点 10→16（§3.6）· `app_theme` 三个 widget 行号（§4）· 测试规模（§6）· 守卫基线 656→655。
>
> 复核另发现 3 项本文原来没有的事实，已补为 **§3.7**（其中 `home_screen.build()` 67 行
> **违反刚立的 ADR-0058「build ≤60 行」**，是本次改动自己引入的）。

---

## 1. 现状数据

🔄 实测于 2026-09-21 22:55（ADR-0059 合入后）：

| 规模 | 文件数 | 总行数 | 占 lib |
|---|---|---|---|
| ≥900 行 | 3 | 4,831 | 18.9% |
| 600–900 | 6 | 4,511 | 17.6% |
| 400–600 | 7 | 3,221 | 12.6% |
| 200–400 | 24 | 6,640 | 25.9% |
| <200 | 98 | 6,405 | 25.0% |

**16 个 ≥400 行的文件 = 11.6% 的文件数，占 48.6% 的代码量。** 这就是维护压力的来源。
（总量 25,620 → 25,608，仅 −12 行：`home_screen` 因导航收敛 +45，其余文件基本未动。）

最大的 9 个文件（🔄 `home_screen` 655 行已升入本表，原表为 8 个 / 610 行）：

| 文件 | 行数 | 性质 |
|---|---|---|
| `shared/theme/app_theme.dart` | 2740 🔄 | 令牌 + 主题 + **12 个 widget** |
| `dev/theme_preview.dart` | 1189 | 开发期视觉预览工具 |
| `shared/domain/models/models.dart` | 902 | 全部领域模型塞一个文件 |
| `home/…/parent/parent_question_bank_view.dart` | 838 | 筛选 + 分页列表 + 多选 + 4 个弹窗 |
| `assistant/…/widgets/assistant_cards.dart` | 825 | 9 种卡片 + 标签行 + 推理折叠 |
| `home/…/parent/parent_task_form_view.dart` | 812 | 出题表单 + 预览 |
| `home/…/screens/parent_task_review_screen.dart` | 732 | 草稿复核页 |
| `home/…/screens/home_screen.dart` | 655 🔄 | 组合根（ADR-0059 后新增 `_ParentPage` 11 个页面类） |
| `home/…/parent/parent_tasks_view.dart` | 649 | 任务列表 + Tab + 多选 + 月分段 |

---

## 2. 四种「大」的成因，处理方式完全不同

这是本次分析最关键的结论：**不要按行数统一处理，要先分类**。

| 成因 | 文件 | 正确动作 |
|---|---|---|
| **A. 令牌文件里塞了 widget** | `app_theme.dart` (2740) 🔄 | 拆。12 个 widget 搬去 `shared/widgets/` |
| **B. 纯数据模型聚合** | `models.dart` (902) | 按聚合拆文件。零行为、零风险 |
| **C. 页面骨架 / 列表脚手架重复** | 8–10 处调用点 | 抽公共组件。**收益最大** |
| **D. 页面本身就是组合根或表单** | `home_screen` (655) 🔄 / `task_form` (812) / `task_review` (732) / `assistant_cards` (825) | 只拆**内部子组件**，不抽「通用组件」 |
| **E. 开发工具** | `theme_preview.dart` (1189) | **不动**。它是视觉走查台，长是它的天性，拆开反而不好对照 |

---

## 3. 已确认的重复（带位置，可直接执行）

### 3.1 枚举 → 文案，各写一份

| 重复 | 位置 |
|---|---|
| `_statusLabel`（任务状态） | `parent_question_bank_view.dart:395` 与 `assistant_cards.dart:789`（注释里已写明「同口径」——等于承认是复制） |
| `_qtypeLabel`（题型） | `parent_question_bank_view.dart:403` 与 `parent_question_card.dart:493` |

→ 收口到 `shared/domain/labels.dart`。**改一处忘另一处的风险已经在注释里被记录下来了，还没被修。**

### 3.2 空态绕过 `AppEmptyState`（违反 ADR-0051）

两处手搓 `_EmptyHint`：

- `parent_question_bank_view.dart:816–838`（图标 + 标题 + 说明 + 刷新按钮）
- `parent_task_review_screen.dart:552–591`（图标 + 标题 + 说明）

ADR-0051 已规定空态统一走 `AppEmptyState`。这两处是漏网的，顺便也把「空态文案不一致」的问题固化了。

### 3.3 筛选 chip 行，四种手写实现

| 实现 | 位置 |
|---|---|
| `_gradeChip` / `_archivedChip` | `parent_question_bank_view.dart:554–593` |
| `_TabBar` | `parent_tasks_view.dart:495–527` |
| `_ThemeToggle` | `parent_task_form_view.dart:658` |
| `_Header` 的分区 chip | `parent_wrong_questions_view.dart:283–349` |

四份代码干同一件事：`active ? ShadButton() : ShadButton.outline()` + `size: sm`。
→ 抽 `AppChipRow<T>({options, value, onChanged})`。

⚠️ 注意：抽完要回头核对「选中态是否还是全站一种语言」（ADR-0046）——现在这四份长得像但间距/前缀不一致，统一时别顺手改视觉，先抽形状再谈调值。

### 3.4 分页列表脚手架，4 处手抄

`AppCardSliver/AppCardList` + `AppPagingFooter` + `SliverPadding` 的组合出现在：

- `parent_wrong_questions_view.dart:123–161`
- `parent_tasks_view.dart:215–265`
- `wrong_questions_screen.dart:121–138`
- `parent_question_bank_view.dart:635–653`（非懒加载版）

→ 抽 `AppPagingCardList({state, itemBuilder, onLoadMore, empty})`，把「loading / error / empty / list + footer」四态收进一处。

### 3.5 多选 + 导出，两套近乎相同的流程

- `parent_question_bank_view.dart:111–156`（`_exportSelected`）
- `parent_tasks_view.dart:117–142`（`_exportSelectedTasks`）

两处都是：算降级题数 → 超 `kExportSoftLimit` 弹同一个「题目较多」确认框 → push `ExportPreviewPage`。
→ 抽 `AppExportFlow.launch(context, request, title, downgraded)`。

### 3.6 页面骨架，约 8–10 处手抄

`SingleChildScrollView` + `AppContentFrame` + `SectionTitle` + `AppCard` 出现在
`parent_overview_view` / `parent_task_form_view` / `parent_question_bank_view` / `parent_tutor_logs_view` /
`child_mastery_screen` / `parent_model_management_screen` / 🔄 ~~`profile_screen`~~ / `parent_task_review_screen`。

> 🔄 **`profile_screen` 已于 ADR-0059（`d695eed`）删除**，折叠为 `home_screen` 的 `_Profile` 页面。
> 骨架清单减一处，但**结论不变**——反而印证了「页面骨架在多处手抄」。

`AppContentFrame` 当初就是把 14 处手抄的 `Align + ConstrainedBox` 收口成一个组件（文件头注释有记录）——
**同一个模式在上一层又抄了 🔄 16 遍**（原记 10 处，实测调用点已增至 16，分布于 12 个文件；
其中 `assistant_chat_page` 单文件 3 处、`parent_wrong_questions_view` 与 `parent_task_review_screen` 各 2 处）。
→ 抽 `AppScrollPage({title, sections})` 或在 `AppContentFrame` 之上加一层 `AppSectionCard`。

### 3.7 🔄 复核新增：ADR-0059 引入的 3 项

导航收敛（`d695eed`）本身是**结构净收益**，但顺带让 `home_screen` 从 610 涨到 655 行，
并引入了一处**违反刚立的 ADR-0058** 的地方。复核实测：

| # | 事实 | 位置 | 处理 |
|---|---|---|---|
| 1 | ⚠️ `build()` **67 行**，超过 ADR-0058「单个 `build` ≤60 行」 | `home_screen.dart:426` | 归入 **P4**。这是新规范立好之后**第一个**违反它的文件，且是本次改动自己造成的——建议优先拆，否则规范一出生就有例外 |
| 2 | `_ParentPage` sealed + **11 个页面子类** + `_buildParentPage()` 的 44 行 switch | `home_screen.dart:178` / `:583–651` | 归入 **P4**。`_ParentPage` 层级与页面→widget 映射是**可独立成文件的一整块**（`parent_pages.dart`），迁走后 `home_screen` 回到 ~580 行。注意 11 个子类是**数据持有者不是 widget**，不违反「私有 widget 类 ≤3」，但占掉 70 行声明 |
| 3 | `app_theme.dart:2684` 的注释仍在写「theme ↔ widgets 循环依赖（与 `AppFocusableAction` 留在本文件同一原因）」 | `app_theme.dart:2684` | **P3 执行时一并改**。该注释是 §4 那半截错误结论的源头，不改会持续误导后来者 |

---

## 4. 建议新增 / 拆出的文件

### 新增（shared 层，全部有多处调用点支撑）

| 新文件 | 内容 | 调用点 |
|---|---|---|
| `shared/widgets/app_chip_row.dart` | 通用筛选 chip 行 | 4 |
| `shared/widgets/app_paging_card_list.dart` | 分页列表四态 + footer | 4 |
| `shared/widgets/app_scroll_page.dart` | 滚动页骨架 | 8+ |
| `shared/widgets/app_export_flow.dart` | 导出确认 + 跳转 | 2 |
| `shared/domain/labels.dart` | 枚举 → 文案 | 2 组 |

### 拆出（`app_theme.dart` 2744 行 → 6 个文件）

`app_theme.dart` 里的 **12 个 widget**：`SubjectMarkIcon` / `AppCard` / `AppFocusableAction` /
`AppPrimaryButton` / `AppBrutalButton` / `AppIconAction` / `AppTextAction` / `AppProgressBar` /
`AppTags`(+`_TagChip`) / `AppBadge`(+`_BadgePill`) / `SectionTitle` / `AvatarSquircle`。

建议落到：

```
shared/theme/app_tokens.dart        # AppBrutal/AppSpacing/AppRadius/AppElevation/
                                    # AppLayout/AppControl/AppMotion/AppSprings/AppCurves（零依赖）
shared/theme/app_theme.dart         # AppTheme/AppColors/AppText/UserModeScope/DensityScope
shared/widgets/app_card.dart
shared/widgets/app_focusable_action.dart
shared/widgets/app_buttons.dart     # AppPrimaryButton + AppBrutalButton
shared/widgets/app_actions.dart     # AppIconAction + AppTextAction
shared/widgets/app_tags.dart        # AppTags + AppBadge
shared/widgets/app_section_title.dart
```

### ⚠️ 关于「`AppFocusableAction` 移出去会成循环依赖」

这条既有结论**只对一半**。实际依赖关系是：

- `AppTheme`（328–1054 行）里**只在注释中**提到那些 widget，**代码零引用**；
- 真正需要 `AppFocusableAction` 的是 `AppCard`(:1327) 🔄 / `AppIconAction`(:1802) 🔄 / `AppTextAction`(:1851) 🔄 ——**它们自己也是 widget**。
  （`AppFocusableAction` 本体在 :1478。原记 1435/1829/1886，因 ADR-0059 改动整体位移。）

所以：

- ❌ 只把 `AppFocusableAction` 单独搬走 → `app_theme.dart` 需要 import 它 → **确实成环**；
- ✅ **12 个 widget 一起搬走** → `app_theme.dart` 不再引用任何 widget → **不成环**。

搬迁后 widget 侧 import `app_theme.dart`（取 `AppTheme.colorsOf`），单向。

> 🔄 复核确认：12 个 widget 仍全部在 `app_theme.dart` 内（实测 :147 / :1327 / :1478 / :1618 / :1690 /
> :1802 / :1851 / :1904 / :2031 / :2142 / :2207 / :2246），**本条结论未失效**，只是行号位移。

### 拆出（`models.dart` 902 行 → 按聚合）

```
shared/domain/models/paging.dart        # CursorPage
shared/domain/models/user.dart          # UserModel / InterestsModel
shared/domain/models/question.dart      # QuestionModel / QuestionPreview / BankQuestionItem
shared/domain/models/task.dart          # TaskSpecModel / TaskModel / TaskCounts / TaskPage / 结果类
shared/domain/models/wrong_question.dart# WrongQuestionModel / WrongQuestionPage / ReviewItemModel
shared/domain/models/mastery.dart       # KnowledgeMasteryModel / MasteryModel / ProgressModel
shared/domain/models/answer.dart        # AnswerResultModel / CheckinResultModel
```

用一个 `models.dart` 做 barrel 转出，调用点 **一行都不用改**。

---

## 5. 执行顺序（每批独立可提交、可回退）

| 批次 | 内容 | 风险 | 预估净减行数 |
|---|---|---|---|
| **P0** | `labels.dart` 收口 + 两处 `_EmptyHint` 改 `AppEmptyState` | 极低 | −80 |
| **P1** | `models.dart` 按 barrel 拆分（调用点零改动） | 低 | 0（纯组织） |
| **P2** | 抽 5 个 shared 组件（§4 新增表），逐个替换调用点 | 中 | −400 ~ −600 |
| **P3** | `app_theme.dart` 12 个 widget 整体搬出（一批做完，不要逐个来） | 中高 | 0（纯组织） |
| **P4** | 大页面内部拆私有子组件：~~🔄 `home_screen` 的 `_ParentPage` 层级 + `build()`（§3.7，优先） / `task_form` 的规格行编辑器 / `task_review` 的统计区 / `assistant_cards` 的题卡~~ → **已全部执行，见 §8** | 中 | 0（纯组织） |

**顺序不能颠倒**：P2 的组件要 import 令牌层，若 P3 还没做，组件只能 import 那个 2744 行的
`app_theme.dart`——不是不能用，但 P3 之后又要回头改一轮 import。要么 P3 提前，要么 P2 接受一次返工。

---

## 6. 纪律与风险

1. **禁一次全量重做**（ADR-0044 迁移纪律）。按批次，每批单独 commit，正文写「为什么」。
2. **禁 `dart format`**（本机 tall style 版本不同 → 85/118 文件噪声 diff）。只靠 `flutter analyze`。
3. **跑测试前关代理**：`env no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同值 flutter test`。
4. **现有网够密**：🔄 47 个测试文件 / 7,340 行（原记 41 / 7,034），其中 7 个是静态守卫
   （`feature_boundaries_test` / `content_frame_guard_test` / `no_bare_gesture_guard_test` /
   `stretch_row_guard_test` / `control_height_test` / `tab_screen_no_root_pop_test` /
   🔄 `parent_nav_single_source_test`）。
   P2/P3 动到 `shared/` 时，`feature_boundaries_test` 会直接拦住越界 import。
5. **多会话并行时先 `git status` + 看 mtime，定点 Edit，写完回读**（`app_theme.dart` 属于共享热点文件）。
6. **抽组件不等于改视觉**：先保证形状一致、像素不变，视觉调整另起一轮。
7. 🔄 **动手前先跑一次守卫**：`flutter test test/file_size_guard_test.dart`（2026-09-21 22:55 实测 3/3 通过）。
   拆完一个文件后同步下调 `_baseline` 里那条；**基线只许下调**，长回去会红。

---

## 7. 明确不做

- **不为拆而拆**：把一个 600 行文件切成 6 个 100 行、但彼此 import 的文件，可读性反而更差。
- **不给只有一个调用点的东西抽「通用组件」**：如 `parent_tasks_view` 的 `_MonthSections`、
  `parent_question_bank_view` 的 `_usageTag`——它们是这一页的概念，留在原文件里是对的。
  （`AppSelectStrip` 当初是从 2 处抽出来的，符合标准；不能拿它当「什么都该抽」的先例。）
- **不动 `dev/theme_preview.dart`**：1189 行的走查台，拆开后对照色板要在多个文件间跳。
- **不引入 `freezed` / 代码生成**：`models.dart` 手写 `fromJson` 已稳定，换生成器是一次全量重写，
  与「渐进迁移」纪律冲突。

---

## 8. 执行结果（P0–P4 全部落地，2026-09-21）

按 §5 的批次顺序逐个提交，每批独立可回退。守卫 `_baseline` 从 **14 条降到 11 条**——
五个文件拆到 400 行以下后登记即删除（棘轮只许下调）。

| 批次 | commit | 净效果 |
|---|---|---|
| P0 | `fd17f02` | 枚举文案收口 `shared/utils/question_labels.dart`；两处 `_EmptyHint` → `AppEmptyState`。顺带修掉一个真 bug：`_ParentPage` 卡的 `qtypeLabel('word')` 后端根本没有 `word` 这个值（应为 `open`），开放题一直显示原始英文 key |
| P1 | `44f6277` | `models.dart`（902）按聚合拆 7 个文件 + barrel，调用点零改动 |
| P2 | `f996ab9` | 抽 `AppScrollPage`（收口 7 处抄写的页面骨架）与 `confirmLargeExport`（收口 2 处导出确认弹窗） |
| P3 | `9d7f765` | `app_theme.dart` 12 个 widget 整体搬到 `shared/widgets/`（2740 → 1695） |
| P4-a | `50821a0` | `home_screen`：`_ParentPage` 层级独立成 `parent_pages.dart`（因私有标识不能跨 library，一并改公开）；`build()` 67 → ≤60 |
| P4-b | `4fcb3ad` | `assistant_cards.dart`（821）按卡片种类拆 9 个文件，payload 投影提到 `domain/card_payload.dart` |
| P4-c | `fe17bcb` | `parent_task_form_view`（810 → 347）：规格行 / 兴趣 / 预览三个区块各成文件 |
| P4-d | `18108b8` | `parent_task_review_screen`（708 → 390）：操作栏 + 摘要各成文件；删掉 `AppDialog.confirm` 的第三份抄写 |

### 三条后来才看清的事

1. **`_ParentPage` 必须改成公开才能搬走**——私有标识不跨 library。ADR-0059 的
   「导航单一状态」判据是「只有一个 `_parentPage` 字段」，与类名是否公开无关，
   所以改名不破坏那条约束；守卫同步改断言即可。
2. **`assistant_cards` 拆开后 payload 读法（`_s`/`_i`/`_rowOf`…）无处可去**——它们被
   渲染和「复制纯文本」两处共用。落到 `domain/card_payload.dart` 是唯一不复制的去处，
   也顺带保证了「复制到的内容」与「屏幕上看到的」不会漂移。
3. **`task_review` 的确认弹窗是 `AppDialog.confirm` 的第三份抄写**，且当时只剩一个
   调用点——Rule of Two 在这里不是「抽组件」，是「删掉它」。

### 剩下的

`parent_question_bank_view`（838）/ `parent_tasks_view`（649）/ `parent_question_card`（511）/
`assistant_chat_page`（557）/ `child_home`（428）/ `parent_wrong_questions_view`（442）/
`parent_overview_view`（401）/ `parent_child_selector`（404）仍在基线里。
它们**不是本报告的待办**——这份报告只覆盖 P0–P4 列出的项；下一轮要拆需另起一份分析。
