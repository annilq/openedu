# 02: 话术多段化 + 轻量重点标注

Parent: docs/specs/teacher-courseware-round-2.md（ADR-0067 第二轮 · 编辑器方向）

**What to build:** 环节话术从「单字符串」升级为「有序段列表」，每段可带轻量重点标注（加粗 / 高亮）；教师在编辑器对话框里增 / 删段、切重点；演示页把每段逐条投成提问卡，重点照渲染。首轮单串话术必须继续兼容（旧课件不坏）。不引入新渲染引擎，重点走既有轻量富文本。

**Blocked by:** None（can start immediately）。

**Status:** done

**Done:** T02 已实现并验收。
- 后端 `CoursewareSection` 增 `script_segments: list[CoursewareScriptSegment]`；`service._section_to_dict` 落库段列表，`script` 上限 500→2000 且同步压平多段文本（`backend/app/features/courseware/schemas.py` + `service.py`）。
- 前端 `CoursewareSectionModel` 增 `scriptSegments` + `displaySegments` 回退（有段用段、否则 legacy `script` 包单段、皆空返回空）；新建 `courseware_script_view.dart` 逐段渲染，bold→粗体、highlight→品牌色 + 浅底。
- 编辑器对话框 `courseware_section_edit_dialog.dart` 重写为多段编辑器（增 / 删段、切重点 none→bold→highlight→none、保存写 `scriptSegments` 并压平 `script`）。演示页与练习提问卡改用 `displaySegments`，列表卡预览亦走段文本。
- 向后兼容：旧单串课件经 `displaySegments` 退化单段，不空屏；新增 `test_replace_sections_roundtrips_script_segments`（后端 25 项 courseware 测试全绿）。
- 测试 harness 补 `GlobalMaterialLocalizations.delegate`（与 `main/app.dart` 一致）；拆 present 测试避免同 id 串扰；修复 `AppPrimaryButton` 在对话框按钮行默认 `fullWidth:true`（`expands:true`）导致的 unbounded width 崩溃——改为 `fullWidth:false`。
- 验收：`flutter analyze lib/features/courseware` → No issues；前端 22 项（editor 7 + present 13 + practice 2）全绿；后端 courseware 25 项全绿。

- [x] 环节 payload 的话术字段改为有序段列表 `[{text, emphasis?}]`；后端 schema 与前端 Dart 模型双向对齐、可序列化往返。
- [x] 编辑器对话框支持增 / 删段、切换该段重点（加粗 / 高亮），改动经 `updateSections` 落库。
- [x] 演示页把段列表逐条渲染为提问卡，重点（加粗 / 高亮）正确呈现。
- [x] 首轮遗留的「单字符串话术」课件仍能正常渲染（向后兼容，不报错、不空屏）。
- [x] 全程不引入 Material 系控件；编辑器对话框与渲染 widget 单文件 ≤400 行；`presentation/` 不 import `*/data/`。
- [x] 前端 widget 测试断言：编辑多段后卡片更新、重点渲染生效；以首轮单串形状构造的课件仍渲染正常；三档投影分辨率不溢出。
