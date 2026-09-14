# LLMProvider 端口上移至 agent_core（业务无关内核）

通用 LLM 抽象与运行时依赖定义为 `agent_core` 的端口，业务工程仅实现抽象并注入 `AgentRuntime`，不把 LLM 耦合进 `app` 层（与 `docs/adr/0032-provider-unification-wheel-packaging.md` 协同）。

- **端口即接口真相源**：`LLMProvider`（消息级，只认「消息」，不感知出题/答疑/批改等业务）、`Retriever`、`Safety`、`RuntimeDeps` 全在 `agent_core/ports.py`，业务无关（`backend/agent_core/ports.py:44-138`）。
- **零业务依赖**：`agent_core` 内核（除 `adapters/` 外）不 import 任何 `app.*` 符号，可独立发布为内部 PyPI 包（`backend/agent_core/ports.py:7`）。
- **上移落点**：通用消息级 `LLMProvider` 已上移到 `agent_core.ports`；教育专有的 `tutor` / `grade_open` 扩展留在 `app.domain` 之上，不污染内核（`backend/app/domain/provider.py:3`、`backend/app/domain/genkit_provider.py:6`）。
- **引擎由调用方解析**：`engine` 为由 `AgentRuntime` 解析好的显式引擎（家长 `ModelConfig` / 前端 `model` 解析所得），经 `RuntimeDeps(provider=...)` 注入（`backend/app/domain/__init__.py:40`、`backend/app/features/assistant/router.py:10`）。
- **统一编排**：所有 AI 能力经 `agent_core` 提供（`AgentRuntime` + `RuntimeDeps`），`app` 层只做 HTTP 适配（`backend/app/features/assistant/router.py:10`、`backend/app/ai/subagents/__init__.py:1`）。

**Considered Options**：① 在 `app` 层直接持有 provider 实现（耦合、不可独立发包，拒绝）；② provider 留在 `agent_core`，业务仅注入抽象（采用）。

**Consequences**：`agent_core` 可独立发布为内部包；`app` 层不反向依赖 LLM 实现细节。新增 provider（`OpenAIProvider` / `AnthropicProvider`）只需新增 `adapters/*` 模块，内核零改动。端口契约由 `tests/ai/test_layering_invariants.py` 守护（内核无 `app` 依赖、genkit 唯一落点、已删模块零残留）。
