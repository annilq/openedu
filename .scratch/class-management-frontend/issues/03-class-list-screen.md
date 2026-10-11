# Ticket 03 — 班级管理列表页（建/改/删班级 + 空态）

- **What to build**: 新增 `features/classes/presentation/ClassManagementScreen`（classes feature 此前缺 `presentation/`）。展示班级卡片列表：名称 + 年级标签（1–9）+ 人数 + 下钻箭头；行内「重命名 / 删除」走页内联浮层（不用 Material `Dialog`，保持无 Material 祖先）。顶部「+ 新建班级」内联表单（名称 + 年级 1–9 选择器），提交建班；重命名/改年级走底部抽屉表单；删除走确认浮层。空态用 `AppEmptyState`。
- **Blocked by**: 02
- **Status**: ✅ done（2026-10-11，本轮回合已落地并测过）
- **验收清单**:
  - 卡片渲染：名称、年级标签、人数、下钻箭头齐备；点卡片触发下钻（ticket 04 消费此落点）。
  - 新建班级：表单提交 → `POST /classes`；年级 1–9 选择器约束；成功后列表出现新卡片。
  - 重命名/改年级：`PATCH /classes/{id}` 成功；年级标签随改。
  - 删除：确认浮层 → `DELETE /classes/{id}`；后端仅把班内学生 `class_id` 置空（保留账号与错题）；前端提示「N 名学生已转为未分班」。
  - 空态：无班级时显示 `AppEmptyState`（解释为什么空 + 下一步「新建班级」）。
  - 文件规模棘轮：列表/表单/确认浮层拆独立 widget，在 `test/file_size_guard_test.dart` 的 `_baseline` 登记（只许下调）。
  - 全站禁 Material 控件：新增页面/浮层在不套 Material 的树里真构建。
