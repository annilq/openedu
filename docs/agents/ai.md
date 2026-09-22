# AI 侧硬规则（AI / Assistant）

> 本文件是 `AGENTS.md`「AI」条目的**细节展开**。入口只给一句话结论，正文在这里。
> 分层与跨层不变量见 `docs/agents/architecture.md`；前端卡片渲染见 `docs/agents/frontend.md` §5。

---

## 1. 工具 schema 必须在 OpenAI strict 模式下自洽（ADR-0040）

genkit 对每个工具**无条件**套 `_ensure_strict_json_schema` + `strict: True`，把 `"required": []`
改写成「所有 property 必填」，模型被迫为每个参数编值。

故：

- 每个**可省略**参数都要有类型合法的缺席编码——字符串 `""`、整数 `0`——并在 handler 归一为「未提供」；
- **枚举型参数必须含 `NO_FILTER`（`"all"`）**，否则模型没有「不过滤」可表达。

归一收口在 `backend/app/features/assistant/query/tools/_shared.py`
（`optional_str` / `optional_int` / `resolve_children`），
由 `tests/ai/test_query_tools_contract.py` 的行为级守卫守住。

---

## 2. 引擎失败归因（ADR-0038 / ADR-0033）

- `decrypt()` 解不开**只能**返回 `None`——**密文永不出门**（不得把解不开的密文回显给前端或日志）。
- 厂商失败（认证 / 限流 / 网络）→ `ProviderRequestError` → `ERROR(code="PROVIDER_ERROR")`；
- 与「模型不支持工具调用」（`TOOL_UNSUPPORTED`，ADR-0033）**严格分开**——两者用户可采取的行动完全不同。

**上层不得用 `except Exception` 把引擎失败抹成「请添加模型」**：那会把「密钥填错了」
和「没配模型」混成一句，用户照着做永远修不好。

---

## 3. 助手卡片协议（ADR-0042 / ADR-0054）

- `DATA` 帧的 `data.type` 是**卡片种类判别键**（`question` / `task_list` / `wrong_question_list` /
  `due_review_list` / `mastery_list` / `child_list` / `progress` / `question_bank_list` /
  `guide` / `notice`）。
- `data.result` 只放**结构化字段**（`{title, subject, items?, stats?, total?, text?, actions?}`）——
  **服务端不拼展示串，排版归前端**。
- 新增种类要在 `query/render.py#_KIND` 与前端 `AssistantCardKind` **各登记一次**
  （例外：`guide` 由 `guide` SubAgent 直接产出，不来自工具结果）；前端未登记的 kind 走降级卡（不丢内容）。
- `actions` 是**受控跳转出口**（`[{label, target}]`），`target` 是枚举如 `parent_create_task`，
  **不是 URL**。前端 `ShellDestination.fromTarget` 解读后交给壳消费，认不出的 target 什么也不做。
- **写意图（「创建 / 派发任务」）走 `guide`（`priority=20`）而不是只读的 `query`**——
  凡带「任务 / 作业」的句子都会命中 query 的 triggers，不压过它，写意图就只会得到「我只能查询」。
- **不要**在这条通道上做「服务端下发 UI schema」式的通用 GenUI。

---

## 4. 推理 / 正文分流（ADR-0043）

- `TextDelta.kind`（`TextKind`：`TEXT` / `REASONING`，缺省 `TEXT`）由适配器按 `SegmentKind` 标注；
- `run_with_tools` **只把 `kind=TEXT` 累进答案**，`REASONING` 只作思考回显（`THINKING` 帧）
  且**不进回灌历史**；
- 工具型 subagent「无原生 `ToolCall` 且正文为空」→ `ERROR(TOOL_UNSUPPORTED)` 硬失败，
  **绝不把内部独白当答复**。

守卫 `tests/ai/test_tool_loop_bounds.py`。

**协议泄露判据分强/弱两档**：强标记（`<invoke name=` / `</invoke>` / `<parameter name=`）
**命中即判泄露，不得绑定具体工具名**——模型编造工具名（把 `list_wrong_questions` 写成 `get_mistakes`）
时点名匹配必然落空，绑上去等于开后门。

---

## 5. AI 侧守卫测试一览

| 守卫 | 拦什么 |
|---|---|
| `tests/ai/test_layering_invariants.py` | 后端分层方向（AST 静态扫描） |
| `tests/ai/test_query_tools_contract.py` | 工具 schema 缺席编码 / `NO_FILTER` |
| `tests/ai/test_tool_loop_bounds.py` | 推理正文分流 / 协议泄露 |
| `tests/ai/test_subagents_seam.py` | SubAgent 契约 |
| `tests/ai/test_guide_subagent.py` | 写意图走 `guide`（优先级不被 `query` 抢走） |
