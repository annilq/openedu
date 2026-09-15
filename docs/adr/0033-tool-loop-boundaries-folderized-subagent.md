# tool loop 边界 + 文件夹化 SubAgent + 查询/REST 共享领域规则

把「工具执行权归 runtime、查询/REST 共用领域规则、角色裁剪只在工具侧、硬失败不降级」等约定机制化为多条决策，并以文件夹化 SubAgent（`agent.py` + `manifest.py` + `tools/` + `skills/`）落地。本 ADR 是被引用最多的决策源（docstring 与测试大量引用「ADR-0033 决策 N」）。

**边界（tool loop，硬失败不降级）**
- **轮次上限**：tool loop 受 `BaseSubAgent.max_turns`（默认 3）保护，超限以 `ERROR(code="TOOL_TURN_LIMIT")` 中止，杜绝「回灌丢失 → 模型反复重调」的无限循环（`backend/agent_core/subagent.py:10,79,131,210-212`）。
- **硬失败**：引擎不支持工具调用时适配器抛 `ToolUnsupportedError`，runtime 转 `ERROR(code="TOOL_UNSUPPORTED")` 并中止，**绝不静默降级为纯文本**（`backend/agent_core/subagent.py:11-12,133-134`、`backend/agent_core/ports.py:83`、`backend/agent_core/adapters/genkit.py:351,168`）。

> **补充（ADR-0038，非矛盾）**：「硬失败」这条决策不变，但**失败类别**被收紧了。「不支持工具调用」只指模型缺 function calling 能力；厂商拒绝请求（认证 / 限流 / 网络）另立 `ProviderRequestError` → `ERROR(code="PROVIDER_ERROR")`。本 ADR 早期实现把工具路径上的**任意**引擎异常一律包成 `ToolUnsupportedError`，导致 401 被报成「当前模型不支持工具调用」——见 ADR-0038。
> **补充（非矛盾）**：「硬失败」还须覆盖**模型把调用写成了文本**的情形。有些模型（本仓实测 `deepseek-v4-flash` 走标准 FC 无此问题，但本地/中转模型常见）不产出原生 `ToolCall`，而把 `<invoke name="...">` / `{"name": "..."}` 这类调用式写进思考或正文。旧实现此时 `turn_calls` 为空 → `acc`（含原始协议）被 `assistant_message` 当答案回流，用户直接看到内部工具调用格式且查询并未执行。现判为硬失败：文本含调用协议标记**且**点名了已注册工具（`_TOOL_CALL_PROTOCOL_RE` + `_text_looks_like_tool_call`，`backend/agent_core/subagent.py:127-142`）→ `ERROR(code="TOOL_UNSUPPORTED")`，且**整段丢弃本轮回显思考**（`turn_thinking` 缓冲后按轮次判定是否冲刷，`:193,219,267,286`），确保原始协议一帧都不外泄。反向不变量：无协议标记的普通文本收尾仍照常作答案（回归用例 `test_plain_text_answer_without_protocol_marker_passes_through`）。

- **同轮多工具**：一轮内模型请求的多个工具全部执行后再回灌，不丢弃后续请求（`backend/agent_core/subagent.py:135`）。
- **回灌契约**：每轮先入 `assistant(tool_calls=[...])` 再入对应 `tool` 结果（成对出现），适配器据此重建 `ToolRequest ↔ ToolResponse` 配对（`backend/agent_core/subagent.py:137-139,182-203`、`backend/agent_core/ports.py:78`）。
- **呈现双轨**：`TOOL_RESULT` 存原始载荷（模型上下文 + 落库回放），`render_tool_result` 覆写者可补发 `DATA` 帧供前端渲染，前端零改动（`backend/agent_core/subagent.py:92-99`）。

**决策（组织与分层）**
- **决策 6**：`tasks` 业务查询逻辑并入 `query`（单查询入口，只读业务查询唯一入口）；`shared_tool` 包随 tasks 退役，将来复用须按 ADR-0024 语义重建（`backend/app/ai/subagents/query/agent.py:1`、`backend/app/ai/subagents/question/manifest.py:6`、`backend/tests/ai/test_runtime_abstractions.py:47`）。
- **决策 8 / 9**：`query` 工具侧统一做角色裁剪（`project_for_role`，去掉答案与解析）；新增工具遗忘裁剪会被契约测试拦下，不靠 review 纪律（`backend/app/ai/subagents/query/tools/_shared.py:1,25,142`、`backend/app/features/tasks/service.py:173`、`backend/tests/ai/test_query_tools_contract.py`）。
- **决策 11**：`query` 工具结果卡片投影双轨（呈现契约），裁剪只发生在工具侧（`backend/app/ai/subagents/query/render.py:9`）。
- **决策 13**：REST 路由与业务查询工具**共用同一套领域规则**（聚合与裁剪收敛到 service 层），错误码/文案逐字一致；router 仅做 HTTP 翻译，反向依赖被分层不变量拦截（`backend/app/features/tasks/service.py:1,6`、`backend/app/features/mastery/service.py:66,router.py:11`、`backend/app/features/review/service.py:7,router.py:11`、`backend/tests/ai/test_layering_invariants.py:11,15,175`）。

**Considered Options**：① 把编排留在 router/FastAPI（膨胀到 700+ 行、ORM 与领域类型泄漏到 HTTP 层，已否决）；② 下沉到 service + 文件夹化 SubAgent + 机制化边界（采用）。

**Consequences**：router 只做 HTTP 适配（鉴权 + 包 `StreamingResponse`）；tool loop 不死循环、不静默丢工具；越权与儿童内容安全（ADR-008）由工具侧契约测试守护，非靠人工 review；已删 `shared_tool` 严禁复活（静态扫描拦截）。
