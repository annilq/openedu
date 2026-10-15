# AI 会话中的 Slot Filling 分析（openedu 现状 + 主流实现）

> 研究问题：当用户在 AI 会话里发起"新建一个任务 / 出几道题"这类复杂流程任务时，openedu 的 AI agent 是否会追问缺失的必要信息（年级、学科、知识点、是否多学科组卷）？主流 agent 是怎么实现 slot filling 的？
>
> 结论先行：openedu 的 AI 会话**没有真正的 slot filling**。它只有出题子代理里一句"请告诉我科目、年级和题型"的通用兜底文案，既不区分缺哪个槽、也不保存半成形意图、不逐槽追问、不问知识点、不问多学科组卷。结构化"新建任务"靠前端表单收集规格，不是 AI 追问。

---

## 1. 现状证据（基于本仓库代码，file:line）

### 1.1 入口与路由是确定性的，没有澄清环节

- `app/features/assistant/service.py:407-419`：`IntentSignal(text=message, action=req.action)` 交给 `rt.decide`，路由是"规则匹配 triggers → 启发式 hints 兜底"，纯关键词，无 LLM 兜底、无槽位概念。
- `agent_core/router.py:43-104`：`match_action` 做动作等值匹配；`_rule_match` / `_heuristic` 都是子串包含判断。整条链路不认识"缺失信息"。
- `tests/ai/test_intent_routing_contract.py` 把 `task_generate` 钉死为 `question` business，且"未知动作容错回落文本路由"。即使用户只说"新建一个任务"而没带任何学科/年级，也会被路由到出题助手，然后由出题助手自行决定怎么办。

### 1.2 出题子代理的"缺失信息"处理（全代码库唯一的"追问"）

`app/ai/subagents/question/agent.py:348-398` 的 `run()` 是唯一接触"缺参数"的代码：

```python
structured = ctx.extra.get("specs")
if structured:
    items = build_prompt_from_specs(structured)        # 结构化路径（助手会话不会走到）
else:
    specs = parse_specs_from_text(message)             # 自由文本正则提取
    if not specs:
        extra_subject = str(ctx.extra.get("subject") or "")
        if extra_subject:                              # 回落课件/知识点下钻的学科
            specs.append({...})                        # 用透传的 subject/grade/kp 补
    if not specs:
        yield self._finish(
            "请告诉我科目、年级和题型，例如：「帮我出 3 道三年级分数选择题」。"
        )
        return
    items = expand_specs(specs)
```

`parse_specs_from_text`（`agent.py:204-286`）用正则/别名提取 `subject / grade / count / qtype / knowledge_point`，提取不到就留空。

**逐条对照用户的疑问，当前行为如下：**

| 用户关心的槽 | 当前是否追问 | 代码事实 |
|---|---|---|
| 学科 | 仅当**完全**提取不到、且上下文也无 subject 时，才发那句通用文案；一旦提取到任一学科就直接出题 | `agent.py:389-393`；`detect_subject` 找不到返回 `""`（`tutor/agent.py:21-26`） |
| 年级 | **不追问**。教师端自由文本没写年级 → `grade=0` 默认（`agent.py:225`）；学生端来自班级（`service.py:74-82, 494-498`），未分班则 0 | 无校验、无提示 |
| 题型 | **不追问**。默认 `choice`（`agent.py:243`） | 缺省即选择题 |
| 知识点 | **从不作为必填槽追问**。提取不到留空串 `kp=""`，直接出题 | `agent.py:259-270` |
| 多学科组卷 | **完全没有此意图/槽位**。只存在于输出概览 `_subject_summary`（`agent.py:295-307`），从不询问"是否要多学科合卷" | 无对应代码路径 |
| 半成形意图 | **不保存**。追问后直接 `return`，用户需重新发一条完整消息；无对话级槽位累积 | 无状态机 |

### 1.3 为什么助手会话不走"结构化 specs"路径

`ctx.extra["specs"]` 只在 `app/features/tasks/service.py:1134` 被赋值（结构化 `POST /tasks/generate`），且 `message=""`（`service.py:1123` "结构化规格走 ctx.extra['specs']，不依赖自由文本"）。而 `assistant/service.py` 构造 `ctx` 时（`service.py:484-506`）**不含 `specs`**。因此助手会话 100% 走自由文本分支 —— 也就是 1.2 的那条唯一兜底。

### 1.4 结构化"新建任务"路径：表单驱动，不是 AI 追问

`app/features/tasks/service.py:1121-1140` 从前端表单提交的 `req.specs` 构造 `ctx` 直接出题。缺失字段由前端的表单 UI / 请求 Pydantic schema 校验（如 `{"specs": []}` 的空规格用例，`test_tasks_generate.py:129`），**不是 AI 在对话中追问**。

结论：真正"收集年级/学科/知识点"的是前端表单，不是 AI agent 的 slot filling。

---

## 2. 主流 Slot Filling 如何实现（要点）

完整机制、一手官方文档链接与对比表见同目录 `slot-filling-mainstream.md`。这里是要点摘录。

### 2.1 工具/函数调用契约式（OpenAI / Anthropic）
缺失信息被当成**schema 契约问题**：JSON Schema `required` + `strict:true`（OpenAI）会在缺必填时直接拒绝请求；否则开发者在服务端校验 `tool_calls` 参数、回灌错误，模型重试填补。Anthropic 用 `input_schema` + `tool_result(is_error:true)` 触发"Claude 重试 2-3 次带修正"。`tool_choice` 强制指定 `collect_slots` 工具 + `strict` = 近确定性收槽。

### 2.2 结构化输出 + Pydantic（LangChain）
`model.with_structured_output(Schema)` 中**无默认值的字段即必填**；缺失时 Pydantic 抛 `ValidationError`，经 `ToolStrategy(handle_errors=...)` 自动 re-prompt 并回显具体缺哪个字段。

### 2.3 对话状态追踪 / 表单填充（Rasa Forms、Dialogflow CX、MS Bot Waterfall）
声明式 `required_slots`：框架按序逐槽 `utter_ask_<slot>`，校验失败 reprompt（`validate_<slot>` 返回 `None` 即重问），确定性最高。Dialogflow CX 用 `Page.form.parameters[].required` + `initialPromptFulfillment` + `repromptEventHandlers` 实现；MS Bot 用 `WaterfallDialog` + `Prompt` 类（类型/区间校验，`RetryPrompt` 直到合法）。

### 2.4 LLM Agent 的人机确认（LangGraph `interrupt()` / `Command(resume=)`）
节点内 `interrupt(payload)` 暂停 → 人类补槽 → `Command(resume=value)` 续跑（需 checkpointer + `thread_id`）。适合"不可逆动作前确认"。

### 2.5 ReAct / plan-and-execute（LLM 判定是否追问）
是否追问由模型决定（输出文本 or 调 `ask_clarification` 工具），灵活但非确定、难测。业界通用启发式：**阻塞 / 不可逆 / 高风险槽才问；可恢复 / 有默认值的槽推断并声明假设**。

### 2.6 机制对比（摘录自主流文档 §5）

| 机制 | 谁检测缺失 | 追问方式 | 确定性 | 适用 |
|---|---|---|---|---|
| OpenAI/Anthropic `required` + strict | schema + 服务端校验 | 模型 re-call / `is_error` 重试 | 高 | 通用 LLM agent、自然语言收槽 |
| LangChain 结构化输出 + Pydantic | Pydantic `ValidationError` | 自动 re-prompt | 高 | 结构化记录抽取 |
| Rasa/Dialogflow 表单填充 | 框架 DST 循环 | 逐槽 `utter_ask_*` | 极高 | 任务型对话、少量已知槽 |
| MS Bot Waterfall + Adaptive Cards | 类型/区间校验 | `RetryPrompt` | 极高 | 卡片表单 UI |
| LangGraph `interrupt` | 开发者插入暂停 | `__interrupt__` 人机确认 | 高 | LLM agent 不可逆前确认 |
| ReAct / plan-and-execute | LLM 判定 | 模型发问 / `ask_clarification` | 低–中 | 开放任务、灵活澄清 |

---

## 3. 差距与落地建议（落到 openedu 架构）

现状归类：**"尽力提取 + 一句通用兜底"**，不是 slot filling。对照用户问题，缺口有三层：

1. **必填槽无确定性校验**：学科/年级/题型应作为 `required slots` 显式声明（参考 Rasa `required_slots` 或 Pydantic 必填字段），缺哪个问哪个，而不是"全缺才说一句"。
2. **知识点被静默留空**：出题脱离教学目标（kp=""）。应改为"从对话/课件推断并声明假设"或显式追问"想练哪个知识点？"。
3. **多学科组卷意图缺失**：当前完全没有。需新增 `subjects: list[{subject, grade, count}]` 槽，并询问"是否要多学科合卷"。
4. **半成形意图不跨轮保存**：追问后直接 `return`，用户要重发整条。应保存已收集槽位（对应 interrupt / required_slots 的"未完成表单"语义），避免重复输入。
5. **不可逆写操作无确认**：`task_generate → from-generated` 是落库写操作，但无确认步骤，可在关键动作前加 `confirm`。

与现有架构的契合点：`agent_core` 已是业务无关内核 + 确定性路由，最适合的落点是**在 `question` 子代理内部引入"required slots + 逐槽追问"的确定性层**（不污染 `agent_core` 内核），复用既有语义化 SSE 帧（`ASSISTANT_MESSAGE`）下发追问文案，或在 `SubAgentContext.extra` 引入 `slots` 契约支持跨轮累积。

---

## 4. 引用

- 主流实现详述与一手官方文档链接：`docs/research/slot-filling-mainstream.md`
- 本仓库关键证据：
  - `app/features/assistant/service.py`（会话编排、ctx 构造、无 specs）
  - `agent_core/router.py`（确定性路由，无槽位概念）
  - `app/ai/subagents/question/agent.py`（出题入口、唯一兜底文案、parse_specs_from_text）
  - `app/features/tasks/service.py:1121-1140`（结构化任务路径，表单驱动）
  - `app/ai/subagents/tutor/agent.py:21-26`（`detect_subject` 返回空串）
  - `tests/ai/test_intent_routing_contract.py`（task_generate → question 契约）
</content>
</invoke>
