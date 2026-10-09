# 07: 环节去 kind 化 · contract（删除 kind 字段与枚举）

**What to build:** 在 03（expand）已引入内容块渲染、且 04/05/06 全部基于内容块落地后，本票是 **contract 阶段**：彻底移除 `kind` 这一旧形式，让"环节 = 内容块容器"成为唯一事实，清空技术债。

**删除范围**
- 后端 `schemas.py`：移除 `CoursewareSection.kind` 字段；旧记录里的 `kind` 键在读取时忽略（或一次性迁移置空）。
- 前端 `courseware_section.dart`：移除 `CoursewareSectionModel.kind` 可空只读字段。
- `courseware_section_kind.dart`：删除整个 `CoursewareSectionKind` 枚举与 `kCoursewareSectionKindLabels`（03 中已 `@deprecated`，此时无调用点）。
- 清理残留 `SECTION_KINDS` / `s.kind` / `isUnknownKind` 等引用（应已在 03/04/05/06 中归零，本票做最终清扫 + grep 断言）。

**Blocked by:** 03（去 kind·expand）、04（手动添加环节）、05（AI 补充讲解）、06（练习内容块）—— 必须等所有消费方都已基于内容块、不再引用 `kind`。

**Status:** done

**验收清单**
- [x] 全仓 grep `CoursewareSectionKind` / `SECTION_KINDS` / `kCoursewareSectionKindLabels` 零命中（代码层）；唯一残留是 `docs/adr/0078-courseware-first-class-module.md` 的叙述性散文（描述"去掉 kind"的决策，保留正确）。`.kind` 键仅剩 `SceneSpec.kind`（ADR-0061 渲染器名，另一层，保留不动）。
- [x] 旧带 `kind` 的课件记录仍能读取并演示：后端 `kind` 只是 `sections` JSON 内的键（非独立 DB 列），`CoursewareSection.model_validate` 自动忽略多余键；新增回归测试 `test_legacy_kind_in_stored_sections_is_ignored` 用 `UPDATE … SET sections` 直接写 legacy kind JSON，断言 GET 仍 `section_count==1` 且 `kind` 不在响应里、title/script 原样。前端 `courseware_present_page_test`「旧单串话术课件向后兼容」用例通过。
- [x] `flutter analyze lib/features/courseware` No issues（全仓 6 issue 全属并行会话，非本票）；后端 `ruff check` All passed；`tests/ai/test_layering_invariants.py` 随 49 pytest 通过。
- [x] 去 kind 回归端到端全绿：后端 `pytest tests/features/courseware tests/ai/test_layering_invariants.py` **49 passed**（含新增 1 项旧数据回归）；前端 `courseware_editor_page_test + courseware_practice_test + courseware_present_page_test` **52 passed**。
- [x] `file_size_guard` 本票不破：未新增任何 >400 行文件、未增长任何基线登记文件（仅删除 `courseware_section_kind.dart`）。当前 guard 4 项失败全来自并行会话（app_theme 1702 / adaptive_shell 503 / teacher_tasks_view 672 / student_management_screen 810），未越权改。

**实现备注**
- `kind` 非 DB 列 → 无迁移。后端 `schemas.CoursewareSection` 删 `kind` 字段；`service.py` 删 `_DraftSection.kind` / 整段 `validate_section_kinds` / `_section_to_dict` 与 `_sections_from_draft` 的 kind 序列化 / `replace_sections` 的 kind 校验调用；`errors.py` 删死代码 `COURSEWARE_BAD_KIND`(CW_91006) 及 422 映射；`db/models/courseware.py` 删 `SECTION_KIND_*` 常量 + `SECTION_KINDS` 元组；`__init__.py` / `router.py` 清理 import 与 docstring。
- 前端 `courseware_section.dart` 删 `kind` 字段 / 构造 / fromJson / toJson / copyWith / `isUnknownKind`；`git rm courseware_section_kind.dart`（枚举 + labels）。三测试文件去 import 与构造参数（保留 `interpreter.kind` 的 SceneSpec 断言）。
- 提交纪律：backend / frontend+tests / chore(票据+memory) 三批；排除并行文件（students/workbench/shared/`section_scene_association_block.dart`/`2026-10-08.md`/`app_theme.dart`/`adaptive_shell.dart`）。
