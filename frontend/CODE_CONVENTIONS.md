# 代码规范 — 娃娃学习 (kids_learn)

适用于 `frontend/`（Flutter + Riverpod + Dio）。视觉/设计规范见 `.impeccable.md` 与 `.github/copilot-instructions.md`，本文件聚焦**代码结构与组织**。

## 1. 单文件行数与组件拆分

### 规则
- **单个页面/组件文件不得超过 300 行**（含 import、注释、空行）。
- 超过即视为坏味道，必须拆分为多个子组件，而非继续在一个文件内堆叠。
- 拆分目标：每个 `.dart` 文件只承担**一个清晰职责**（一个屏幕骨架、一个区块、一个可复用卡片、一个对话框等），便于阅读、测试与复用。

### 为什么
- 低年级儿童平板界面信息密度高，单文件过长往往意味着一个 Widget 同时承担了**布局 + 数据装配 + 交互逻辑 + 局部样式**，回归风险随行数指数级上升。
- 拆分后 Riverpod provider 的消费范围更小，热重载更快，AI 与人类导航代码都更省力。

### 拆分原则
1. **按「视觉区块」拆，而非按行数机械切割**：一个区块 = 一个独立子组件（如 `_HeaderBar`、`_TaskListSection`、`_AnswerSheet`、`_ResultFooter`）。
2. **跨特性复用 → `lib/shared/widgets/`**：若子组件会被多个 feature 使用（如卡片、标签、输入框、对话框），提升为 `App*` 语义组件，放 `shared/widgets/`，遵循 `.impeccable.md` 的令牌与语义组件约定。
3. **仅本特性使用 → `lib/features/<feature>/presentation/widgets/`**：特性内私有子组件（命名可带 `_` 前缀或单独文件导出），不要污染 `shared/`。
4. **状态与视图分离**：数据装配、Riverpod watch、复杂回调逻辑保留在屏幕层；纯展示子组件只接收参数 + 暴露回调，保持 dumb/reusable。
5. **import 不算「凑数」**：若文件仅因 import 多而接近 300 行，可接受，但仍建议评估是否区块本身过大。

### 落地目录约定
```
lib/features/<feature>/presentation/
├── screens/<feature>_screen.dart      # 屏幕骨架：组装区块 + 注入 provider，尽量 < 200 行
└── widgets/                            # 本特性子组件
    ├── <feature>_header.dart
    ├── <feature>_section_a.dart
    └── <feature>_result_card.dart
lib/shared/widgets/                     # 跨特性共享 App* 组件
```

### 自查与门禁
- 提交前用 `find lib \( -name "*_screen.dart" -o -name "*_view.dart" -o -path "*/widgets/*.dart" \) -exec wc -l {} + | sort -rn` 自查，任何 > 300 行的文件需先拆分（含屏文件与 feature 内 widget）。
- 子组件文件同样适用 300 行上限；若子组件也超限，继续按区块往下拆一层。

### 已整改项（2026-08-25 完成一轮）
| 文件 | 拆前 | 拆后 | 处理 |
| --- | --- | --- | --- |
| `features/review/presentation/screens/review_screen.dart` | 538 | 215 | 拆出 `review_empty_view` / `review_question_view`；完成页用共享 `AppQuizResultCard`，结果弹窗用 `AppAnswerResultDialog` |
| `features/practice/presentation/screens/practice_screen.dart` | 474 | 165 | 拆出 `practice_question_view` / `practice_done_view`；完成页用共享 `AppQuizResultCard`+彩带+PopIn |
| `features/tutor/presentation/screens/tutor_quota_screen.dart` | 378 | 217 | 拆出 `tutor_usage_card` / `tutor_quota_form`（含内联 `_SubjectToggle`）；保存按钮用 `AppPrimaryButton` |
| `features/tutor/presentation/screens/tutor_chat_screen.dart` | 376 | 156 | 拆出 `tutor_welcome_hint` / `tutor_message_list`(+bubble) / `tutor_chat_input_bar`；发送按钮用 `AppPrimaryButton` |

本轮同步新增 3 个跨特性共享组件：`shared/widgets/app_option_tile.dart`(93) / `app_answer_result_dialog.dart`(63) / `app_quiz_result_card.dart`(130)，并给 `AppPrimaryButton` 增加 `icon` / `loadingLabel` / `height` 参数（移除原 `fullWidth:false` 的死 `Center` 包装）。决策依据见 `docs/adr/0001-extract-shared-quiz-widgets.md`。

### 后续待整改项（下一轮）
| 文件 | 行数 | 备注 |
| --- | --- | --- |
| `features/home/presentation/widgets/parent_dashboard.dart` | 1074 | 家长端看板，严重超标，建议按区块（概览卡 / 任务进度 / 娃娃列表 / 操作区）拆分；本轮未在范围内 |
| `features/home/presentation/widgets/child_home.dart` | 312 | 孩子端首页，轻微超标，可拆出 banner / 任务入口 |

> 整改完成后更新此表，保持与实际行数同步。
