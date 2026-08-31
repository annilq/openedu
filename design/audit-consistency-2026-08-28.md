# 规范一致性审计 · 清除报告（2026-08-28）

> 对应步骤①：跑规范一致性审计，清除既有 `withValues(alpha:)` 与缺描边违反。
> 设计依据：`.impeccable.md` §规范一致性 / ADR-0014。

## 审计结论

- **`withValues(alpha:)` 违反**：全库扫描 16 处，已清除 15 处，1 处保留为合理例外（动画运行时 fade，无实体令牌可映射）。
- **硬编码阴影**：发现 1 处 `CupertinoColors.black.withValues(alpha: 0.03)` 阴影，违反「描边分层、无阴影」规则，已删除（卡片本就有 1px 描边）。
- **缺描边（named）**：`parent_overview_view.dart` 的 `_StatCard` 用裸 `Container` 无 1px 描边，已补 `Border.all(color: outline)`。
- **验证**：`flutter analyze` → `No issues found!`（零警告，无 unused import）。

## 清除明细（15 处 `withValues` + 1 阴影 + 1 缺描边）

| 文件:行 | 原写法（伪造分层） | 替换令牌 | 理由 |
|---|---|---|---|
| `shared/widgets/app_error.dart:54` | `errorContainer.withValues(alpha:0.6)` | `errorContainer` | 语义错误容器底色，实色即可 |
| `features/children/.../child_form_screen.dart:230` | `outlineVariant.withValues(alpha:0.8)` | `outline` | 边框统一走 1px 描边令牌（`outline`≡`outlineVariant` 值） |
| `features/tutor/.../tutor_quota_screen.dart:174` | `secondaryContainer.withValues(alpha:0.5)` | `secondaryContainer` | 信息框底色，实色即可 |
| `features/tutor/.../tutor_welcome_hint.dart:25` | `secondary.withValues(alpha:0.2)` | `outline` | 边框走描边令牌 |
| `features/tutor/.../tutor_welcome_hint.dart:52` | `onSecondaryContainer.withValues(alpha:0.85)` | `onSecondaryContainer` | 次级文字实色 |
| `features/tutor/.../tutor_message_list.dart:63` | `primary.withValues(alpha:0.35)` | `outline` | 气泡边框统一描边令牌 |
| `features/home/.../parent_task_review_screen.dart:213` | `outlineVariant.withValues(alpha:0.6)` | `outline` | 边框走描边令牌 |
| `parent_task_review_screen.dart:233` | `statusChip.$2.withValues(alpha:0.85)` | `statusChip.$2` | 状态 chip 底色素，实色 |
| `parent_task_review_screen.dart:489` | `outlineVariant.withValues(alpha:0.6)` + 阴影 | `outline` + **删阴影** | 描边令牌 + 去除硬编码黑阴影（无阴影规则） |
| `parent_task_review_screen.dart:629` | `primaryContainer.withValues(alpha:0.5)` | `primaryContainer` | 答案框底色，实色 |
| `parent_task_review_screen.dart:821` | `outlineVariant.withValues(alpha:0.8)` | `outline` | 输入框边框走描边令牌 |
| `parent_task_review_screen.dart:896` | `outlineVariant.withValues(alpha:0.6)` | `outline` | 空态卡片边框走描边令牌 |
| `features/home/.../parent_question_bank_view.dart:156` | `outlineVariant.withValues(alpha:0.4)` | `outline` | 分隔线走描边令牌 |
| `parent_question_bank_view.dart:354` | `outlineVariant.withValues(alpha:0.6)` | `outline` | 未选中项边框走描边令牌 |
| `features/home/.../parent_overview_view.dart:215` | `_StatCard` 裸 Container 无描边 | `+ border: outline` | 补 1px 描边（named 缺描边违规） |

## 合理例外（保留）

- `shared/widgets/app_motion.dart:254` — `p.color.withValues(alpha: fade)` 位于 confetti 自绘 `CustomPainter`，`fade` 为动画生命周期内的运行时透明度，对随机粒子色无对应实体令牌。属 ADR-0014「celebrate」动效的合法运行时插值，非静态分层伪造，保留并标注。

## 遗留：散落 Container 着色（建议独立 pass）

全库另有 50+ 处 `BoxDecoration`，绝大多数为图标底/头像/分隔线/进度轨等非卡片容器，不应加描边（已确认的卡片型仅 `_StatCard` 一处）。为避免误伤布局，建议后续单独一轮「卡片型 Container → 包 `AppCard`」的人工分类 pass，不在本次自动批量处理。

## 下一步

- ② `app_theme.dart` 落地 Child Mode 字号阶梯 + 学科色 + `AppUserMode` 切换；
- ③ `DesktopShell` 升级为 `AdaptiveShell`（compact 底部导航/抽屉、medium 收起侧栏、expanded 展开）。
