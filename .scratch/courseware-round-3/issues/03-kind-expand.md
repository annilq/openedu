# 03: 环节去 kind 化 · expand（类型化 → 内容块统一，旧形式仍可用）

**What to build:** 按用户拍板，环节不再按 `kind` 类型化——每个环节是统一的 {标题, 话术, 素材, 场景, 练习} 内容块容器，渲染/编辑都"按填了什么"。本票是 **expand 阶段**：在旧 `kind` 形式旁边引入内容块渲染，旧数据与新代码都不破，CI 全程绿。枚举标记 deprecated 但**不删除**（删除归 07 contract）。这是 04/05/06 的前置。

**后端（expand，不动存储契约的破坏性）**
- `schemas.py`：`CoursewareSection.kind: str | None = None`（原必填 → 可选）。旧带 `kind` 的记录照常读、照常写。
- `service.py`：`validate_section_kinds` 放宽——未知/空 `kind` 不再 422（保留函数但跳过校验，或改为无操作 + 警告）。
- `compute_section_diff` 匹配键：由 `(kind, title)` 改为 `(title)`（避免去 kind 后全判新增）；同名多段仍按出现顺序消费。
- AI 起草 `_DraftSection` 不再输出 `kind`；`_sections_from_draft` 不再按 `SECTION_KINDS` 过滤/丢弃。

**前端（expand，引入内容块渲染，旧 kind 调用点迁移为内容推断；枚举保留）**
- `courseware_section.dart`：`CoursewareSectionModel.kind` 保留为**可空只读**字段（兼容旧数据的 JSON 读取），渲染/编辑不依赖它。
- `courseware_section_kind.dart`：枚举标记 `@deprecated`（保留类型与 `kCoursewareSectionKindLabels` 仅作旧数据展示兜底，**不删除**）。
- `editor_section_list.dart`：列表标签/图标改为按内容推断（有 `scene` → 交互、有 `materials` → 素材、否则 → 讲解），去掉 `switch (s.kind)`。
- `courseware_present_widgets.dart`：`_buildBody` 删除 `kind == interactiveScene` 分支，统一走"按内容渲染"的空态文案；`isUnknownKind && 无内容` 的降级保留为"无内容"兜底。

**Blocked by:** None（可立即开始）。

**Status:** ready-for-agent

**验收清单**
- [ ] 后端 `kind` 可选、空/未知 kind 不再 422；旧带 kind 课件照常读
- [ ] `compute_section_diff` 匹配键不含 kind，重起草 diff 不误判全新增
- [ ] AI 起草产物不含 kind 字段
- [ ] 前端渲染/编辑零 `kind` 新分支（除兼容旧数据的可空只读字段）；枚举 `@deprecated` 但仍在、未删
- [ ] 去 kind 后回归：旧带 kind 课件能正常演示；新无 kind 课件能与后续 04/05/06 互写
- [ ] `flutter analyze` 0 issue；`tests/ai/test_layering_invariants.py` 通过；`file_size_guard` 不破
