# 业务 SubAgent × 学科 Persona 正交组合

业务维度 = SubAgent（出题 / 伴学 / 查询），学科维度 = Persona，二者在调用方正交组合（与 `docs/adr/0003-seam-subagent-contract.md` 同源，本条沉淀「学科维度如何注入」的明确约定）。

- **业务 SubAgent 包**：各 SubAgent 以文件夹 `<business>/`（含 `agent.py` + `manifest.py` + `tools/` + `skills/`）组织，由 `agent_core.AgentRuntime` 统一发现加载（`backend/app/ai/subagents/__init__.py:1`、`backend/app/ai/__init__.py:29` 惰性导入时即注册）。
- **学科人格归一化**：`subject_personas.py` 按学科归一化，作为统一参数注入每个业务 SubAgent，而非每学科各建 Agent（`backend/app/ai/subagents/subject_personas.py:1`）。
- **注入点在调用方**：RAG 命中内容与学科 Persona 在**调用方**注入，出题库内核（`pipeline.py`）只消费、不持有，保证流式与落库口径一致（`backend/app/ai/subagents/question/pipeline.py:56,97`）。
- **边界约定**：出题与查询的意图边界由 manifest 的 `priority` + `triggers` 决定（出题 `priority=0` 高于伴学兜底，低于查询 `priority=12`，`backend/app/ai/subagents/question/manifest.py:6,26`）。
- **契约验证**：`tests/ai/test_subagents_seam.py` 在不加载 genkit 重型依赖下验证多 Agent 骨架运行时与学科 Persona 注入。

**Considered Options**：① 每学科每业务各一个 Agent（组合爆炸，拒绝）；② 单一通用 Agent 带 system 切换（seam 难维护，拒绝）。选 **业务 × 学科两维正交注入**。

**Consequences**：新增业务线只需新增 SubAgent 包 + manifest；新增学科只需在 `subject_personas` 加配置，不触达 Agent 代码。RAG/Persona 在调用方注入，出题库内核保持纯净、流式与落库同源。
