# 10: 停止 scene_intent 直连 assistant.repository

**What to build:** tutor 的 `scene_intent` 子代理不再直接 `import features.assistant.repository.last_scene_figure_key`；改为依赖中性端口/服务（下沉到 `materials/core` 或经注入），消除跨特性的越权数据依赖。

**Blocked by:** None (can start immediately)

**Status:** done

- [x] `scene_intent.py` 不再 import `features.assistant.repository`（grep `assistant.repository|from app.features.assistant|import app.features.assistant` 零命中）。
- [x] 取 figure key 改经中性依赖：`last_scene_figure_key` 现从 `app.features.materials.scene_figure_key` 导入（`:42`），行为与 ADR-0089 L2 盖章一致。
- [x] 后端 pytest 相关用例通过（`tests/ai/subagents/tutor/test_scene_intent.py`）；`ruff check` 通过（无越权跨特性 import）。

_— 核验（2026-10-14，交叉核验发现 tracker 陈旧）—_
- 实现已在 main：`463a566 refactor(tutor): stop scene_intent importing assistant.repository (LCC-10)`；`git merge-base --is-ancestor 463a566 main` = true → 早已合入 main。
- 原「定位」已陈旧：`scene_intent.py:37` 现为 `from app.features.materials.figure_stamp import (`，`:42` 才是 `scene_figure_key` 的 `last_scene_figure_key`；原 `features.assistant.repository` 直连已删除并下沉 materials。
- 中性归宿：`app/features/materials`（figure 属素材域），未新建跨特性回边。
