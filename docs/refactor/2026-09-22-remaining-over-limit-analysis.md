# 仍超线文件：是否有优化必要（2026-09-22）

P0–P4 拆掉 5 个文件后，守卫 `_baseline` 还剩 **11 条**（见 `test/file_size_guard_test.dart`）。
其中 `home_screen`(586) / `app_theme`(1695) / `adaptive_shell`(490) 是 P4 主动保留的，
其余 8 个是业务大文件。本分析逐项判断是否值得继续拆。

## 先给结论

**没有紧迫性。** ADR-0058 的棘轮（`_baseline` 只许下调）已经锁死了这些文件的**增长**——
它们不会再变长，每拆掉一个就从 allowlist 删一条。所以"是否优化"只取决于
**日常维护摩擦**，而不取决于"会不会更糟"。

与 P0–P4 不同，这 11 个里**没有一个携带正确性 bug，也没有"第三份抄写"这类硬伤**
（P0 修过 `word→open`、P4-d 删过 `AppDialog.confirm` 第三份）。它们纯粹是"行数大"。
因此建议：**不要立刻跑新一轮大批量重构**，把拆分当作"下次碰这个文件做功能时顺手做"的
机会成本，而不是独立任务。

## 逐项判定

判据（ADR-0058 §2）：单文件 ≤400 行 / 单 `build()` ≤60 行 / 单文件 ≤3 个私有 widget。

| 文件 | 行 | 私有件 | 最大 build | 形态 | 该拆？ | 优先级 |
|---|---|---|---|---|---|---|
| `shared/theme/app_theme.dart` | 1696 | 0 | — | 设计令牌枢纽：纯 token 定义 + 2 个 scope，**无 widget、无 build** | **否（豁免）** | — |
| `features/home/…/screens/home_screen.dart` | 586 | 2 | 50 | 应用根 + `_GenerationBanner`，全是导航装配 | **否** | — |
| `features/home/…/parent_overview_view.dart` | 402 | 3 | 59 | 正好 3 件、build ≤60，仅超 2 行 | **否** | — |
| `features/home/…/parent_child_selector.dart` | 405 | 3 | 56 | 同上，仅超 5 行 | **否** | — |
| `shared/widgets/adaptive_shell.dart` | 491 | 4 | 67 / 66 | 壳内 chrome 件（`_BottomNavItem`/`_DrawerItem`/`_CompactTopBar`）与壳强耦合 | **触碰时拆** | 低 |
| `features/assistant/…/assistant_chat_page.dart` | 558 | 4 | 74 / 66 | 主对话页 + `_InputBar`（输入条 66 行） | **触碰时拆** | 低-中 |
| `features/home/…/parent_tasks_view.dart` | 649 | 7 | 74 / 60 | **7 个拼装件** + sealed `_Row` 层级 | **值得拆** | 中-高 |
| `features/home/…/child_home.dart` | 429 | 6 | 88 / 67 | **6 个拼装横幅**（`_BrutalBanner`…）+ `_TaskCard` | **值得拆** | 中 |
| `features/home/…/parent_wrong_questions_view.dart` | 443 | 4 | 70 | 头部 + `_ParentWrongCard`（70 行 build） | **值得拆** | 中 |
| `features/home/…/parent_question_card.dart` | 508 | 0 | 30 | 单 `State` 含 **142 行内联编辑表单** | **值得拆** | 中-高 |
| `features/home/…/parent_question_bank_view.dart` | 807 | 1 | 62 | 单类含 **3 个弹窗**（删除确认 102 / 草稿选择 58 / 新建 48） | **值得拆** | 高 |

## 三类理由

### 1. 不拆（设计豁免 / 已达 ADR 精神）
- **`app_theme`**：令牌集中库，所有消费方都 `AppTheme.colorsOf(context)`，拆开会牺牲可发现性。
  它已因 P3（搬出 12 个 widget）从 2740 降到 1695，剩下的全是 token 本体 + scope，不是"拼装"。
- **`home_screen`**：应用根，多出来的行是导航接线（`ref.listen` 壳 / 任务生成），P4-a 已把
  `build()` 压到 ≤60、私有件仅 2 个。`586` 是合理的根规模。
- **`parent_overview_view` / `parent_child_selector`**：都正好 3 个私有件、build ≤60，只是
  总量比 400 多 2~5 行。这是基线边界 nearest-miss，不值得为这几行单开文件。

### 2. 触碰时拆（真实但轻微的 ADR 违规，独立重构性价比低）
- **`adaptive_shell`**：4 个私有件 + 2 个 build 略超 60（67 / 66）。chrome 件与壳布局强耦合，
  硬拆要导出或挪到 `adaptive_shell_chrome.dart`。壳是稳定、极少改的文件——下次改壳时一并做。
- **`assistant_chat_page`**：4 个私有件、主 build 74 / 输入条 66。把 `_InputBar` 输入条抽成
  `assistant_input_bar.dart` 最干净；其余 3 个小提示件可随它一起走。**中低**。

### 3. 值得拆（真·巨型视图 / 拼装件，但非紧急）
- **`parent_question_bank_view`（807，最高）**：一个 `State` 类里塞了搜索/筛选/列表 + **3 个
  弹窗**（删除确认 102 行最重）。弹窗是天然可搬的"弹出逻辑"，与列表渲染无状态共享 →
  抽到 `question_bank_dialogs.dart`，筛选/题卡渲染抽到 `question_bank_widgets.dart`。
  拆完预计 <400。这是"会持续吸代码"的典型大视图，最该做。
- **`parent_question_card`（508）**：单 `State` 含 142 行 `_buildEditForm` + 100 行 `_buildReadonly`。
  内联编辑器自成一块，可抽 `question_card_editor.dart`；只读体 + 卡壳留原文件。
- **`parent_tasks_view`（649）**：7 个私有件，sealed `_Row` 层级 + `_MonthSections` + `_TaskCard`
  是一组"任务行渲染"，与父页状态耦合弱 → 挪 `task_row.dart` + `task_month_sections.dart`。
- **`child_home`（429）**：6 个拼装横幅是纯展示，`_TaskCard` 与题库卡同源 → 横幅抽到
  `child_home_banners.dart`，`_TaskCard` 视是否复用决定去留。
- **`parent_wrong_questions_view`（443）**：`_ParentWrongCard`（70 行 build）抽 `wrong_question_card.dart`。

## 建议的下一步

**不启动新一轮批量重构。** 理由：
1. 棘轮已锁增长，无"会恶化"风险；
2. 8 个业务文件都是稳定、已上线的功能，拆分有不小的回归风险，而日常收益只是"更好导航"；
3. P0–P4 刚做完，连续大改不利于 git 历史聚焦。

**改成分批触发**：当某个文件因为新需求要被改动时，顺手完成它那一项拆分（弹窗/编辑器/拼装件），
并同步从 `_baseline` 删掉登记——这正好符合棘轮"只许下调"的设计意图。

若仍想现在做，**优先级排序**：`parent_question_bank_view`(807) > `parent_question_card`(508) ≈
`parent_tasks_view`(649) > `child_home`(429) ≈ `parent_wrong_questions_view`(443) >
`assistant_chat_page`(558, 触碰时) > `adaptive_shell`(491, 触碰时)。
