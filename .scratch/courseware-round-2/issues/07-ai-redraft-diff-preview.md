# 07: AI 重起草 diff 预览 + 逐段接受

Parent: docs/specs/teacher-courseware-round-2.md（ADR-0067 第二轮 · 编辑器方向）

**What to build:** 教师重起草时，后端返回新稿相对当前稿的「逐段 diff」（新增 / 删除 / 修改）；编辑器渲染 diff 预览，教师逐段选择「用新版 / 留旧版」；接受结果写回同一课件，不新建副本。让 AI 起草只是辅助而非硬覆盖。

**Blocked by:** 02（话术多段化 + 轻量重点标注）——diff 需基于多段话术模型才有意义。

**Status:** done

- [x] 后端 `draft_sections` 在已有「整体起草」能力上，返回逐段 diff（新增 / 删除 / 修改），对照当前课件 sections（含 T02 的多段话术结构）。
- [x] 编辑器渲染 diff 预览，逐段呈现变化。
- [x] 教师逐段选择「用新版 / 留旧版」；接受结果经 `updateSections` 写回同一课件。
- [x] 写回不新建课件副本（同一 `courseware_id`）。
- [x] 全程不引入 Material 系控件；编辑器 widget 单文件 ≤400 行；`presentation/` 不 import `*/data/`；后端改动走归属守卫。
- [x] 后端测试断言 `draft_sections` 返回结构化的逐段 diff；前端 widget 测试断言：diff 预览逐段展示、逐段接受写回正确 payload、不产生重复课件。

**Done note (2026-10):** 后端 `service.redraft_diff` + `compute_section_diff`（added/removed/modified/unchanged，
按 `(kind,title)` 顺序消费匹配，removed 收尾）+ `router POST /{id}/redraft` + `schemas.CoursewareRedraftDiff`；
`test_courseware_crud.py` 17 测试全绿（原 14 + 新 3：逐段结构 / unchanged / 越权 404，且列表仍 1 份不新建副本）。
前端 `courseware_redraft_diff.dart`（模型 + `mergeRedraftChoices`）+ 仓库 `getRedraftDiff` + `courseware_redraft_dialog.dart`
（`showDialog`/`Dialog` 既有约定，默认全采用，二选一开关）+ 编辑器 `_redraft` 改为 `getRedraftDiff → 弹窗 → updateSections` 写回同一课件；
`courseware_editor_page_test.dart` 15 测试全绿（含 5 个 T07：纯函数合并两条 + fromJson + 应用写回 + 取消不落库）；三件套 38 测试零回归；analyze 0 issue。
