# 掌握度可视化按学科色着色 — 落地说明（ADR-0014 Step③延伸）

> 日期：2026-08-30
> 关联：ADR-0014「学科色扩展」、Step② `SubjectAccent` / `AppTags.subject`、Step③ `AdaptiveShell`
> 范围：家长端「知识点掌握度」看板的学科色消费闭环

## 背景

ADR-0014 引入学科色（`SubjectAccent`：数学蓝 / 语文玫瑰 / 英语翠绿 / 其它灰），
Step② 在主题层落地、Step③ 把它接到娃娃端任务卡与做题页学科标签。
但家长端「知识点掌握度」看板（`ParentOverviewView`）的掌握度条**仍按掌握等级着色**，
学科色在该视图完全未被消费——这是 ADR-0014 学科色闭环的唯一缺口。

数据侧 `KnowledgeMasteryModel` 自带 `subject` 字段（`models.dart:530`），
因此每个知识点条都能稳定映射到一个学科键，无需后端改动。

## 改动

文件：`frontend/lib/features/home/presentation/widgets/parent/parent_overview_view.dart`

### 1. `_MasteryBar` 进度条 + 行首色点改按学科色（`parent_overview_view.dart:248`）

- 删除原 `_MasteryLevel` 枚举与 `_mappingOf`（按等级→颜色的四态映射），原逻辑把
  「薄弱/待加强」映射成红、`已掌握` 映射成靛蓝——学科信息被完全丢弃。
- 进度条 `AppProgressBar.color` 改为 `sc.accent`（学科强调色）。
- 行首新增 10×10 圆角色点 `sc.accent`，与 `subject · knowledgePoint` 文本并列，
  使每一行的学科色一眼可辨。
- `sc = SubjectAccent.forContext(SubjectAccent.fromName(item.subject), context)`，
  自动跟随亮/暗主题与 `UserModeScope`（娃模式下字号更大，但学科色不变）。

### 2. 掌握等级改用语义徽章（保留警示信号）

进度条让位给学科色后，「薄弱 / 待加强」的红色警示不能丢。新增 `_levelBadge`：

| 等级 | 徽章 |
|---|---|
| 已掌握 / 较扎实 | `AppBadge.successChip`（绿） |
| 巩固中 | `AppBadge.infoChip`（信息靛蓝） |
| 薄弱 / 待加强 | `AppBadge.warningChip`（红/琥珀） |

等级语义仍清晰，但颜色不再与进度条竞争——进度条专职表达「哪个学科」。

### 3. 掌握度卡片顶部加学科色图例

`_buildMastery` 在「已掌握 X / Y」与条目列表之间插入 `Wrap` 图例：
取 `items` 去重后的学科集合，渲染 `AppTags.subject(SubjectAccent.fromName(s), label: s)`。
整块看板的颜色编码自解释，家长无需记忆色值。

## 设计权衡

- **为什么是「条按学科、徽章按等级」而非「条按等级」**：
  学科色是 ADR-0014 的核心交付，必须落在最显眼的进度条上；等级警示改用徽章保留，
  既满足「按学科色着色」又无信息丢失（双编码，非二选一）。
- **未引入运行时 `withValues(alpha:)`**：色点直接复用 `SubjectColors.accent` 实体令牌，
  延续 Step① 的规范纪律（禁用 alpha 伪分层）。
- **娃端未建掌握度视图（本次刻意不做）**：娃娃端当前无掌握度看板（数据端点虽可复用
  `/tasks/children/{id}/mastery`，但需新增娃端目的地 + 屏，超出「着色」范围）。
  学科色在娃端已通过任务卡/做题页标签消费；娃端掌握度视图列为后续可选延伸。

## 验证

- `flutter analyze` → **No issues found**（修了一处顶层函数误用 `static` 的 lint）。
- 真机/模拟器：进入「家长端 → 某娃娃 → 知识点掌握度」，可见数学条蓝、语文条玫瑰、
  英语条翠绿，行首色点同步；薄弱/待加强条仍带红色徽章；顶部图例对应学科。

## 下一步（可选延伸）

- 娃娃端新增「我的学科」掌握度屏，复用同一 `masteryNotifierProvider` + 学科色条，
  作为 ADR-0014「娃娃端动力」的收尾（需在 `AdaptiveShell` 娃端目的地加一项）。
