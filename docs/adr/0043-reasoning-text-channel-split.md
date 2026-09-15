# ADR-0043：推理与正文的语义通道分流（`TextDelta.kind`）

需求：模型产出的一段流里，「思维链」与「正式答复」是两回事——前者是模型「想什么」，后者才是「答什么」。本 ADR 记录为什么必须在**协议层**把两者分开、以及分流规则。

## 背景与事故形态

工具型 subagent（`query`）走 `run_with_tools` 时，模型若**不发原生 `ToolCall`**、而是把「我要调工具」的意图写进思维链 / 正文（本地 Ollama、中转模型这类「叙述式调用」模型常见），会发生：

1. `agent_core/adapters/genkit.py` 把所有流片段**一律** `yield TextDelta`——**包括 `SegmentKind.REASONING`**；
2. `run_with_tools` 把所有 `TextDelta` 全累进 `acc`；
3. 模型没产出原生 `ToolCall` 时，`acc` 经 `assistant_message(acc)` 直接下发，**内部独白（含英文推理与 `<invoke>` 调用草稿）就成了 AI 气泡正文**。

**真机复现**：家长 `annilq` 问「查一下 lsc 的错题本」→ 模型无原生 ToolCall，`acc` 是 1255 字符英文独白，原样下发给儿童端。

**既有防护不够**：`_text_looks_like_tool_call`（`subagent.py:141`）只认 `acc` 里的 XML / JSON 调用协议标记（`<invoke name=` / `"name": "` / `function_call`），**拦不住「答案本身就是独白」**这一形态（无协议标记）。

**防护第二例（2026-09-15，同一函数的另一个洞）**：原判据是「协议标记命中 **且** 点名了已注册工具」。真机（`deepseek-v4-flash` / `openai_compat`）上，模型第一轮原生调用 `list_children` 成功拿到 `child_id` 后，**第二轮把「查错题」的调用写成了 XML 文本，并把工具名幻觉成 `get_mistakes`**（真名 `list_wrong_questions`，见 `query/tools/list_wrong_questions.py`）。协议标记明明命中，却因工具名对不上而放行——整段 `<tool_calls><invoke name="get_mistakes">…</invoke></tool_calls>` 原样落库（`message.content`）并下发给用户。

判据已拆为**强 / 弱两档**：强标记（`<invoke name=` / `</invoke>` / `<parameter name=` / `<function_calls>` / `antml:`）是调用外壳的结构性字面量，**命中即判泄露，与工具名无关**；弱标记（`"name": "` / `function_call` / `"function": {`）可能与正文同形（讲解 JSON 时会写到），保留「点名已注册工具」作为收紧。**教训：把结构性协议标记绑到具体工具名上，等于给「模型编造工具名」这一最常见形态开后门。**

**连带修复（同一根因的另一半）**：`query` 的 SOP 原写「先调 `list_children` 拿 `child_id`，再带 id 查明细」，等于强制每次跨娃娃查询都多走一轮「复述一串 uuid」——而这正是 `deepseek-v4-flash` 最容易退化成文本调用的动作（`_shared.py:45-65` 已记录同源形态）。SOP 与 `_SYSTEM` 已改为**优先用 `child_name` 一跳直达**，仅在昵称歧义时才取 `child_id`。

根因：**协议层（`TextDelta`）不分推理 / 正文**，于是「流向」（累不累进 `acc`）与「语义」（思考回显 vs 最终答案）无法对齐。

## 决策

**把推理与正文的语义差异提升为端口契约，由适配器标注、runtime 分流；混流即违例。**

1. **`TextDelta.kind`（端口层新增）**：`agent_core/ports.py#TextKind`——`TEXT`（正式答复，**可**作最终答案）/ `REASONING`（思维链 / 内部独白 / 调用叙述，**只能**当思考回显，**绝不**当答案）。缺省 `TEXT`，兼容旧适配器与测试替身。
2. **适配器按通道标注**：`genkit.py#_TEXT_KIND_OF` 把 `SegmentKind`（`REASONING`/`TEXT`）显式映射到 `TextKind`；**未知通道保守按 `TEXT`**（不致把正文当推理丢掉）。
3. **runtime 分流（`subagent.py#run_with_tools`）**：`kind is REASONING` → 只进 `turn_thinking`（外发为 `THINKING` 帧，且下发前经 `_flushable_thinking` 丢弃整段命中调用协议的伪片段）；`kind is TEXT` → 累进 `acc`。**思维链不进 `acc`、也不进回灌历史**（回灌思维链会污染后续轮次）。
4. **硬失败而非降级**：工具型 subagent「整轮无原生 `ToolCall` 且正文为空」→ `ERROR(code="TOOL_UNSUPPORTED")`，绝不把内部独白当答复。用 `native_fc_seen` 区分两种「本轮没有工具调用」：**从没见过**原生 FC = 能力问题（硬失败）；**见过**（如前轮已下发数据卡、本轮仅无收尾话术）= 安静结束，不误报能力缺陷。
5. **不变式（与 ADR-0033 同源）**：原始调用协议**永不出现在任何下发给客户端的事件里**。

## Considered Options

- **继续堆文本启发式（正则识别「独白」）vs 协议层分离**：选协议层分离。启发式永远追不上模型措辞（本次正是「无协议标记的独白」漏网），且扩大后会误杀正常回答。
- **`kind` 放端口层 vs 留在适配器内部**：选端口层。流向决策（进不进 `acc` / 历史）发生在 runtime，适配器只应负责**标注**语义，不该替 runtime 决定去向。
- **无原生 `ToolCall` 且正文空 → 降级为纯文本 vs 硬失败**：选硬失败。与 ADR-0033 一致——静默降级会把「模型没走 FC」这个真问题藏起来。

## Consequences

- 「英文独白被当答案」的**结构性根因消除**；工具型 subagent 不再把内部独白下发。
- **残留**：纯自然语言叙述（如「我去查一下」，无协议标记、正文非空）仍会作为普通正文流出——**泄露危害已消除**，但根治须模型侧原生 function calling。
- 新增 `TextKind` 端口契约；不标注 `kind` 的旧适配器 / 测试替身默认 `TEXT`，行为与旧版一致。
- **编号更正**：本决策在代码 docstring 中曾被误标为 `ADR-0041`——`docs/adr/0041` 实为「启动期密钥健康检查与配置 CWD 无关化」，属**编号撞号 + 引用悬空**。本 ADR 为该决策的唯一事实源，`ports.py` / `genkit.py` / `subagent.py` 及相关测试的引用已迁回 0043。

## 验证判据

- 后端 `tests/ai/test_tool_loop_bounds.py`：无原生 `ToolCall` 且正文空 → `TOOL_UNSUPPORTED`；思维链不进答案、不进历史；协议伪片段外发前被过滤；正文只走 `ASSISTANT_MESSAGE`、无思维链时不产 `THINKING` 帧；**协议标记命中但工具名是编造的同样硬失败**（`test_fabricated_tool_name_is_not_leaked_as_answer`），且已下发数据卡时报「部分成功」而非「查询无法执行」。
- 后端 `tests/ai/test_genkit_adapter_tools.py`：两通道（`REASONING`/`TEXT`）都要流出，但**语义标注必须分开**。

## 已知遗留

1. **前端尚未消费 `THINKING` 与正文的区分度**：前端目前只渲染 `ASSISTANT_MESSAGE`、忽略 `THINKING`；「AI 气泡 Markdown 渲染」仍待落地（推荐 `gpt_markdown`，落点 `shared/widgets/app_markdown.dart` + `assistant_message_list.dart#_BubbleBody`；根是 `CupertinoApp`，勿引入依赖 Material 祖先的渲染栈）。
2. **纯自然语言叙述未拦**（见 Consequences 残留）：需模型侧原生 FC 根治，不在本 ADR 范围内。
