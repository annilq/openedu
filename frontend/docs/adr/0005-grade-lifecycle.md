# ADR-0005: 年级的生命周期、默认与范围

- **Status**: Accepted（决策 2 已实现于 `parent_task_form_view.dart`；决策 1、3 于 2026-08-28 修订为「保持现状」）
- **Date**: 2026-08-28
- **Supersedes**: —
- **Affected**:
  - `frontend/lib/features/home/presentation/widgets/parent/parent_task_form_view.dart`（`_SpecRow.grade` 由 `int` 改为 `int?`：`null`=继承选中娃娃年级，非 `null`=家长手动覆盖；生成时 `toSpec(selected.grade)` 解析）
  - ~~`backend/app/models.py`（`User` 新增 `enrollment_year` / `grade_override`）~~ — **2026-08-28 修订：不采纳，年级维持家长手动维护**
  - ~~`frontend/lib/features/children/presentation/screens/child_form_screen.dart`（年级选项 1~9）~~ — **2026-08-28 修订：不采纳，维持 1~6**

## Context

娃娃的 `grade` 当前是 `User` 上一个**纯手填的整数**（`models.py:27/87`），家长在新建娃娃（`child_form_screen.dart:173-177`）与编辑页手填。经 grill 发现三处空白与不一致：

1. **年级如何演进从未定义**——代码里没有出生日期、入学年份、学年任何字段，也没有任何"年级+1"逻辑。家长若忘记在新学年改年级，出题就会停在旧年级。
2. **任务表单年级硬编码为 2**（`parent_task_form_view.dart:33`），完全没读已选娃娃的年级，与"先选娃娃再建任务"的流脱节。
3. **娃娃年级选项只到 6**（`List.generate(6, …)`），但任务表单到 9、学科下拉现已含 物理/化学/生物（7~9 年级内容），范围不自洽。

用户原提案是「过一年主动+1」或「按入学年龄算」二选一——但 grill 指出二者**不对等**：B 需要新数据（当前模型没有），A 同样缺锚点（不知起点、会重复累加），且"过一年"若理解为生日周年是错的（中国年级在 9 月新学年升级，不在娃生日）。真正的决策是**要不要引入锚点 + 年级由谁算**。

## Decision

### 1. 年级 = 锚点 + 现算（single source of truth = `enrollment_year`）

- `User` 新增锚点字段 **`enrollment_year: int | None`**：娃娃开始**一年级**的那个秋季公历年份（如 2023  Autumn 入学 → `2023`）。
- 新增 **`grade_override: int | None`**：留级 / 跳级等例外时的绝对年级覆盖；`None` = 按锚点算。
- 现算纯函数（前后端共用语义）：
  - `current_school_year(today) = today.year if today.month >= 9 else today.year - 1`（学年以 9/1 为界，标识 = 起始秋季年）。
  - `compute_grade(enrollment_year, today) = current_school_year(today) - enrollment_year + 1`。
  - **effective_grade** = `clamp(grade_override ?? compute_grade, 1, 9)`。
- **向后兼容**：`enrollment_year is None` 时回落到旧行为——直接读手填 `grade`。一次性迁移把存量娃娃的 `enrollment_year` 回填为 `current_school_year - grade + 1`，之后 `grade` 退化为派生值（仍保留列作缓存/兼容，权威值来自锚点）。
- 锚点选 `enrollment_year` 而非 `birthdate`：出生日期要引入"标准入学年龄=6"假设，且同年 1 月与 12 月出生娃娃可能不同年级，锚点更直接无歧义。

### 2. 任务表单年级默认取选中娃娃年级，逐行仍可改

- `_SpecRow.grade` 初值由硬编码 `2` 改为 `selectedChild.grade ?? 2`（在 `build` 内按当前选中娃娃初始化）。
- 每行年级选择**保留可编辑**——支持特殊场景（暑假预习高一年级 / 补差低年级），不因默认而锁死。
- 后端不变：年级仍按 spec 逐行传入；默认只决定前端初值。

### 3. 新建娃娃年级选项扩到 1~9（对齐 K9）

- `ChildFormScreen` 年级 picker 由 `List.generate(6, …)` 改为 `List.generate(9, …)`，与任务表单（1~9）、K9 学科（含 物理/化学/生物）范围一致。
- 新建娃娃表单同时采集 `enrollment_year`（用于驱动决策 #1 的现算；留空则回落手填 `grade`）。

## Consequences

- **正面**
  - 年级一次写入（入学年份）即永久正确，无需定时任务、无需家长每年记得改。
  - 消灭"任务年级硬编码 2"与"娃娃 1~6 / 任务 1~9"两处不一致。
  - `grade_override` 收口留级/跳级，不污染锚点计算。
  - 9/1 学年界符合中国学制，比"生日周年+1"正确。

- **负面 / 成本**
  - `User` 加两列 + 一次性回填迁移（`run_migrations` 幂等加列 + 按 `current_school_year - grade + 1` 回填 `enrollment_year`）。
  - 前后端需共用 `current_school_year` / `compute_grade` 语义（前端用于展示与默认，后端生成任务时若需权威值也应复用，避免读 stale `grade`）。
  - 家长需额外填"入学年份"（或依赖默认推算），新建表单多一个字段。

## Alternatives considered

- **维持手动（现状）**：否决。家长忘改 → 出题年级偏；且用户想要的"按入学年龄算"本就无数据支撑，迟早要加锚点。
- **学年翻页自动+1**（每年 9/1 触发 `grade+1`、封顶 9）：否决。仍需锚点防重复累加（否则每次启动都+1 爆表），且假设人人每年+1（留级/跳级算错）。锚点+现算严格更正确、零定时任务。
- **用 birthdate 当锚点**：否决。引入入学年龄假设且同年不同月娃娃会错位；`enrollment_year` 更直接。

## Open Questions

- **O1**：后端生成任务时是否以 `effective_grade(child)` 为权威（忽略 spec 里的年级）？当前前端默认已取娃娃年级、家长可逐行改；若后端也强制按锚点算则家长手动降级/预习会被覆盖。**倾向：前端默认 + 允许手动覆盖，后端信任 spec 传入值**（保持现有"家长可控"语义），实现阶段再敲定。
- **O2**：`grade_override` 用绝对年级（已选）还是相对偏移（如 `grade_offset=-1` 表留级）？**已选绝对 int**——最无歧义。
- **O3**：存量娃娃回填后，编辑页是否隐藏手填 `grade`、只暴露"入学年份 + 例外覆盖"？实现阶段定。

## Revisions (2026-08-28)

用户决策：**娃娃年级维持家长手动维护（保持现状）**，仅要求「任务出题年级默认与当前选中娃娃年级一致」。据此调整原 ADR：

- **决策 1（锚点 + 现算）— 不采纳**：不再新增 `enrollment_year` / `grade_override`，不做 9/1 自动升级。理由：用户明确选择维持手动维护，当前阶段无需引入锚点字段与一次性迁移；年级正确性继续依赖家长在编辑页手改。
- **决策 2（任务年级默认取娃娃年级）— 已实现**：`parent_task_form_view.dart` 中 `_SpecRow.grade` 改为可空，`null` 表示继承当前选中娃娃年级；Picker 显示值取 `_rows[i].grade ?? selected?.grade ?? 2`，生成时 `toSpec(selected.grade)` 统一解析。家长改过的行保留手动值；切换娃娃时未改动的行自动跟随。
- **决策 3（娃娃表单 1~9）— 不采纳**：维持新建娃娃年级选项 1~6（与「保持现状」一致）。任务表单仍支持 1~9（含初中科目），由家长在出题时按需选高年级。
