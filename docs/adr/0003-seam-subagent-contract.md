# Seam SubAgent 契约

业务维度 = SubAgent（出题 / 伴学），学科维度 = Persona，二者在调用方组合（原 ADR-0021）。

- **业务 SubAgent 包**：`app.ai.subagents` 导入即注册出题、伴学两个业务 SubAgent（`backend/app/ai/__init__.py:29`）。
- **学科人格归一化**：`subject_personas.py` 按学科归一化，作为统一参数注入每个业务 SubAgent，而非每个学科一个 Agent。
- **RAG / Persona 注入点**：RAG 命中内容与学科 Persona 在**调用方**注入，出题库内核（`pipeline.py`）只消费、不持有，保证流式与落库口径一致（`backend/app/ai/subagents/question/pipeline.py:97`）。
- **契约测试**：`tests/ai/test_subagents_seam.py` 在不加载 genkit 重型依赖下验证多 Agent 骨架运行时，`test_query_tools_contract.py` 验证工具契约。

**Considered Options**：① 每学科每业务各一个 Agent（组合爆炸，拒绝）；② 单一通用 Agent 带 system 切换（难维护 seam，拒绝）。选 业务×学科 两维正交注入。

**Consequences**：新增业务线只需新增 SubAgent 包 + manifest；新增学科只需在 `subject_personas` 加配置，不触达 Agent 代码。
