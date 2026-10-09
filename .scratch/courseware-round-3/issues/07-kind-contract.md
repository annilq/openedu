# 07: 环节去 kind 化 · contract（删除 kind 字段与枚举）

**What to build:** 在 03（expand）已引入内容块渲染、且 04/05/06 全部基于内容块落地后，本票是 **contract 阶段**：彻底移除 `kind` 这一旧形式，让"环节 = 内容块容器"成为唯一事实，清空技术债。

**删除范围**
- 后端 `schemas.py`：移除 `CoursewareSection.kind` 字段；旧记录里的 `kind` 键在读取时忽略（或一次性迁移置空）。
- 前端 `courseware_section.dart`：移除 `CoursewareSectionModel.kind` 可空只读字段。
- `courseware_section_kind.dart`：删除整个 `CoursewareSectionKind` 枚举与 `kCoursewareSectionKindLabels`（03 中已 `@deprecated`，此时无调用点）。
- 清理残留 `SECTION_KINDS` / `s.kind` / `isUnknownKind` 等引用（应已在 03/04/05/06 中归零，本票做最终清扫 + grep 断言）。

**Blocked by:** 03（去 kind·expand）、04（手动添加环节）、05（AI 补充讲解）、06（练习内容块）—— 必须等所有消费方都已基于内容块、不再引用 `kind`。

**Status:** ready-for-agent

**验收清单**
- [ ] 全仓 grep `CoursewareSectionKind` / `.kind` / `SECTION_KINDS` / `kCoursewareSectionKindLabels` 零命中（除本票删除本身）
- [ ] 旧带 `kind` 的课件记录仍能读取并演示（`kind` 键被忽略，不破坏历史数据）
- [ ] `flutter analyze` 0 issue；`ruff check` 0 issue；`tests/ai/test_layering_invariants.py` 通过
- [ ] 去 kind 回归：旧带 kind 课件演示 + 新无 kind 课件与 AI 补充互写，端到端全绿
- [ ] `file_size_guard` 不破；单文件 ≤400 行
