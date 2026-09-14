# AI 调用归一封装（build_ai_provider / resolve_engine 单一入口）

所有同步 AI provider 构造经 `build_ai_provider` 归一封装，统一由 `resolve_engine` 解析模型引用；router / service 不再各自构造 provider。Phase 1 = 结构化出题端点（直接传规格、不走自由文本正则），Phase 2 = 归一封装（消除「批改忽略 model」的分裂）。

- **归一封装入口**：`build_ai_provider(model_ref, *, parent_id, session)` 把模型引用透传给 `resolve_engine` 再交 `build_provider` 构造，单行调用点便于未来接 quota/audit（`backend/app/core/ai_plumbing.py:21`）。
- **契约测试锁不变量**：`build_ai_provider` 确实把 `model_ref` / `parent_id` 透传给 `resolve_engine`，且 `model_ref` 为 `None` 回落 `None`（`backend/tests/ai/test_ai_plumbing.py:21`）。
- **Phase 1 结构化出题端点**：`POST /api/v1/tasks/generate` 经归一封装构造 provider；测试打桩点落在 service 而非 router（ADR-0033 编排下沉后 router 已不 import `build_ai_provider`）（`backend/tests/api/routes/test_tasks_generate.py:38`）。
- **批改经归一封装**：`answer` 批改用 `Grader(build_ai_provider(task.model, parent_id=task.parent_id, session=session))`，尊重 `task.model` / 家长 `ModelConfig`（`backend/app/features/tasks/service.py:1098`）。
- **出题经归一封装**：`generate_task_stream` 同样用 `build_ai_provider(req.model, parent_id, session)` 构造出题 provider，与批改/伴学同一条解析链（`backend/app/features/tasks/service.py:1155`）。
- **桩接受关键字参数**：生产代码调用带 `parent_id` / `session` 关键字参数，测试桩须用 `lambda *a, **k` 接受（ADR-0034 归一封装）（`backend/tests/features/review/test_service.py:62`）。

**Considered Options**：① 各 endpoint/service 各自 `resolve_engine` + `build_provider`（分裂、易漏 model，拒绝）；② 统一经 `build_ai_provider` 单层封装（采用）。

**Consequences**：模型解析集中一处，`task.model` / 家长 `ModelConfig` / 请求级 `model` 全线贯通；未来加审计/配额只改 `ai_plumbing.py`。不变量由 `tests/ai/test_ai_plumbing.py`（透传 + 回落）与 `test_tasks_generate.py`（打桩点正确）守护。
