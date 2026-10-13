# 10: 停止 scene_intent 直连 assistant.repository

**What to build:** tutor 的 `scene_intent` 子代理不再直接 `import features.assistant.repository.last_scene_figure_key`；改为依赖中性端口/服务（下沉到 `materials/core` 或经注入），消除跨特性的越权数据依赖。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `scene_intent.py` 不再 import `features.assistant.repository`。
- [ ] 取 figure key 改经中性依赖（materials/core 或服务层），行为不变。
- [ ] 后端 pytest 相关用例通过；`ruff check` 通过。

_— 定位（volatile，仅供本次实施）—_
- `backend/app/ai/subagents/tutor/scene_intent.py:37` `from app.features.assistant.repository import last_scene_figure_key`，`:261` 使用
- 中性归宿候选：`app/features/materials`（figure 属素材域）或服务层；勿新建跨特性回边
