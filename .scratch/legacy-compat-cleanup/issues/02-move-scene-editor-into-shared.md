# 02: 把 KnowledgePointSceneEditor 搬进 shared 教师控件

**What to build:** SceneSpec 编辑器不再作为 home 的内部控件；抽到 `shared/presentation/widgets/teacher/` 成为跨特性中性控件，home 与 courseware 均从 shared 引用。消除环的另一条回边。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `KnowledgePointSceneEditor` 定义位于 `shared/presentation/widgets/teacher/`。
- [ ] `courseware_section_edit_dialog` 从 shared 引用它（不再 import `features/home`）。
- [ ] home 内原引用点改为从 shared 引用。
- [ ] 定向 grep：courseware 不再 import `features/home`。
- [ ] `flutter analyze` 通过。

_— 定位（volatile，仅供本次实施）—_
- 定义：`frontend/lib/features/home/presentation/widgets/teacher/knowledge_point_scene_editor.dart`
- 回边：`courseware_section_edit_dialog.dart:8`（from home）
- home 侧另有引用点（grep `knowledge_point_scene_editor|KnowledgePointSceneEditor` 全仓确认）
