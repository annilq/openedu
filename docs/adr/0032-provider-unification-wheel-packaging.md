# Provider 统一收口 + 单 wheel 打包 + 遗留件清理

出题业务从分散旧模块归位到 `question` 子包并统一经 `LLMProvider`，不再直连 genkit 引擎；`agent_core` 与 `app` 同发一个 wheel，被删除的遗留件严禁复活（与 `docs/adr/0031-port-llmprovider-in-agent-core.md` 协同）。

- **业务归位**：ADR-0032 后教育出题业务全部归位到 `app.ai.subagents.question`（`pipeline.py` 出题管线 / `parsers.py` 契约与解析器），原 `app/ai/generation.py`、`app/ai/parsers/question.py` 已迁走（`backend/app/ai/__init__.py:5`、`backend/app/ai/subagents/question/pipeline.py:3`、`backend/app/ai/subagents/question/parsers.py:14`）。
- **统一走 LLMProvider**：废弃直连 genkit 引擎的旧路径，prompt 组装由调用方负责（ADR-0030 收口 #4），provider 接口只收「已组装 prompt + spec」（`backend/app/ai/subagents/question/pipeline.py:12,13,127`）。
- **遗留件删除**：原 `app/ai/debug_log.py` 在 ADR-0032 收敛中**删除**（零调用方）；观测落库统一收口到 `app.features.assistant`（ADR-0026）（`backend/app/ai/__init__.py:11-12`、`backend/app/features/ai/repository.py:6-7`）。
- **单 wheel 打包**：`agent_core` 随 `app` 一同打包（`pyproject.toml` 的 `[tool.hatch.build.targets.wheel]`），内核与集成层同发一个 wheel，不单独发布（`backend/pyproject.toml:37`、`backend/docs/agents/architecture.md:21`）。
- **死代码守护**：已删除模块不得被任何源码重新引用，由 `tests/ai/test_layering_invariants.py` 静态扫描拦截（`backend/tests/ai/test_layering_invariants.py:37,131`）。

**Considered Options**：① 保留并行旧路径（漂移风险，拒绝）；② 收口单一路径 + 死代码清理 + 不变量守护（采用）。

**Consequences**：流式与落库共用同一 `LLMProvider` 接口，口径一致；删模块后零调用方残留。新增功能不得重新 import 已删符号（`test_layering_invariants` 直接红）。
