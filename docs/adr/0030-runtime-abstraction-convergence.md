# 运行时抽象收口（engine 由调用方解析、SOP 注入时机）

大模型引擎解析收敛为单一链：显式 `engine` 注入优先，否则回退 `resolve_engine()`；SOP 作为系统受控资产（manifest 声明的技能），在输入安全闸门**之后**注入，不参与 `check_input` 扫描。

- **引擎单一解析链**：`build_provider(engine=)` 注入显式引擎；未注入时由 `GenkitProvider._resolve` 回退 `resolve_engine()`，不再有第二套解析路径（`backend/app/domain/genkit_provider.py:9`、`backend/app/domain/genkit_provider.py:37`）。
- **engine 由调用方解析**：`engine` 为由调用方（`AgentRuntime` / 家长 `ModelConfig` / 请求级 `model`）解析好的显式引擎，传入则全程使用，避免内部四处自解析（`backend/app/domain/__init__.py:40`）。
- **SOP 是系统受控资产**：`skills` 为 manifest 声明的 SOP（`skills/*.md`），不参与输入安全校验——SOP 文本本身含「越狱/暴力」等安全词，并入 `check_input` 会误伤每条娃娃提问（`backend/app/domain/tutor.py:11`）。
- **SOP 注入在输入闸门之后**：SOP 在 `check_input` 校验通过后才拼进上下文，闸门只拦用户可控输入（`question` / `knowledge_point` / `context`）（`backend/app/domain/tutor.py:146`）。
- **回归测试钉住抽象收口**：未给引擎时 `build_provider()` 仍把 `_engine` 留 `None`、回退全局 `resolve_engine`，不在构造期臆造引擎（`backend/tests/ai/test_runtime_abstractions.py:38`）。

**Considered Options**：① 各 service 自行解析引擎（分裂、难审计，拒绝）；② 引擎由调用方解析后单一注入、SOP 在闸门后注入（采用）。

**Consequences**：引擎解析只剩一条链，新增模型来源只需改 `resolve_engine`；SOP 注入时机固定，安全闸门不再误伤系统提示。不变量由 `tests/ai/test_runtime_abstractions.py` 守护（显式引擎透传、未给引擎回退全局解析、SOP 真消费且不触发输入闸门）。
