# 02: 把 KnowledgePointSceneEditor 搬进 shared 中性层

**What to build:** SceneSpec 编辑器 + 图库选择器 + 开发者指引，连同资料库仓储（domain 接口/模型、data 实现）与仓库/场景库 provider，一并抽到 `shared/features/materials/`，成为跨特性中性层。home 与 courseware 均从 shared 引用，消除 home↔courseware 环的另一条回边，且不再让 shared 反向依赖 home（R2）。

**Blocked by:** None

**Status:** done

- [x] `KnowledgePointSceneEditor` / `SceneLibraryPicker` / `SceneDeveloperGuide` 定义位于 `shared/features/materials/presentation/widgets/teacher/`。
- [x] 资料库契约（`SceneLibraryEntry`/`MaterialRepository` 等）迁到 `shared/features/materials/domain/repositories/material_repository.dart`；实现迁到 `shared/features/materials/data/repositories/material_repository_impl.dart`。
- [x] `materialRepositoryProvider` + `sceneLibraryProvider` 定义迁到 `shared/features/materials/providers/material_providers.dart`，由 home 组合根（`home_provider` / `knowledge_manage_provider`）再导出，维持既有调用方 import 路径不变（同 `assistant_provider` 公开面约定）。
- [x] 编辑器保存改经 `materialRepositoryProvider.updateKnowledgePointScenes`（不再经 `KnowledgeManageNotifier.saveScenes`），使 shared/materials 不反向依赖 home（破 R2 隐患）。
- [x] `courseware_section_edit_dialog` 从 shared 引用编辑器（不再 import `features/home`）。
- [x] home 内原引用点（10 处 lib + 11 处 test）改为从 shared/materials 引用。
- [x] 定向 grep：courseware 不再 import `features/home`；`flutter analyze` 通过；前端全量测试 552/552 通过。

_— 定位（volatile，仅供本次实施）—_
- 原定义：`frontend/lib/features/home/presentation/widgets/teacher/knowledge_point_scene_editor.dart` → `frontend/lib/shared/features/materials/presentation/widgets/teacher/`
- 回边：`courseware_section_edit_dialog.dart:8`（from home）→ 改指 shared
- 决策：中性层选 `shared/features/materials/`（经 AskUserQuestion 与用户确认），而非 `shared/presentation/`，以贴合 materials 业务边界。
