# AI Agent 分层抽象设计分析：本项目 vs `pi`

> 分析日期：2026-09-10 · 视角：deep module / seam / 渐进式组合
> 参照：[pi_tutorial（annilq fork）](https://gist.github.com/annilq/4fc974da06bbb7ccbadeebad404b7877)

---

## 0. 一句话结论

**`pi` 是「能力栈」分层：每层可独立消费，组合出 agent。本项目是「数据流管线」分层：串在一条 SSE 管道上的处理阶段，不可独立消费。**

更尖锐一点：本项目叫 `AgentRuntime` 的那个东西，语义上是 **Router（派发器）**，不是 Runtime（运行时）——它没有 agent loop，模型从未见过工具声明，每个 SubAgent 是一次性手写的 async generator。**名字撒了谎，这是当前设计最大的认知负债。**

---

## 1. 两套分层的对照

| 层 | `pi` | 本项目 | 是否真等价 |
|---|---|---|---|
| LLM 通信 | `pi-ai`：`getModel` + `streamSimple`，归一化成 `text_delta`/`thinking_delta`/`toolcall_*`/`done` | `app/ai/engine.py:resolve_engine()` → `EngineResolution(genkit, model, supports_reasoning)` | ❌ 半等价 |
| 生成抽象 | `streamFn(model, context, opts)`（消息级） | `app/domain/provider.py:LLMProvider`（业务语义级） | ❌ **关键分叉** |
| 流式解析 | 无（由 provider SDK 承担） | `segment.py`(Decode) → `parsers/question.py`(Parse) → `runtime/translate.py`(Translate) | 本项目独有 |
| 事件协议 | `agent_start`/`message_update`/`tool_execution_*`/`agent_end` | `AssistantEvent`（AG-UI 式，10 种 eventType） | ✅ 等价 |
| Agent 循环 | `pi-agent-core:Agent` 真 loop（模型决策 → 调工具 → 回灌 → 再调） | **无** | ❌ 缺失 |
| 业务体 | `pi-coding-agent`：7 内置工具 + session + compaction + extensions | `app/ai/subagents/<business>/`（agent.py + manifest.py + tools/ + skills/） | ⚠️ 形似神不似 |
| 编排 | 应用层（OpenClaw per-channel agent） | `app/ai/runtime/AgentRuntime`（发现 + 意图路由 + 角色过滤） | ⚠️ 本项目下沉进内核 |
| 呈现 | `pi-tui`（差分渲染 / markdown / editor） | `frontend/lib/features/assistant/`（SSE client + notifier + 悬浮按钮 + 弹窗） | ✅ 等价 |

---

## 2. 本项目分层实况（自底向上）

```
L7  呈现层    frontend/lib/features/assistant/          ← 消费 SSE 帧，渲染
L6  端点层    app/features/assistant/router.py          ← SSE + 鉴权 + 配额 + 落库
L5  编排层    app/ai/runtime/{runtime,manifest,intent_router}.py
L4  业务层    app/ai/subagents/{question,tutor,tasks}/
L3  协议层    app/ai/runtime/{protocol,translate}.py    ← 语义事件 → AG-UI 帧
L2  生成层    app/ai/{generation,segment}.py + parsers/ ← prompt + Decode/Parse
L1  引擎层    app/ai/engine.py  →  Genkit  →  厂商 SDK
L0  抽象层    app/domain/provider.py  （LLMProvider ABC）
```

有几处做得好，值得点名：

- **错误处理不静默。** `QuestionFailed` 显式成事件，前端能看到「这题为什么没出来」；`translate.to_frames` 对未知语义事件直接 `raise TypeError`，拒静默丢弃。这是 deep module 的正确姿势。
- **思维链帧聚合。** `translate.py` 按 16 字符攒批，帧数降一个量级而打字机观感不变。这是把「性能不变量」藏进模块内部的正确做法，调用方零感知。
- **`_tool()` 句柄收口。** `ToolCall` 把 `tool_call`/`tool_result` 的同名对不变量收进基类，调用方写不出错位帧。
- **发现即注册。** ADR-0030 干掉了手工登记表，新增 subagent = 丢一个文件夹。
- **测试 seam 干净。** `build_provider` 单一替换点，打桩后全套件 22s → 6.5s。

---

## 3. 三个真正的架构问题

### 3.1 `LLMProvider` 是泄漏的抽象（最大杠杆）

```python
async def generate_question_stream(
    self, *, subject, grade, knowledge_point, qtype, difficulty,
    interests, focus_interest, rag_context, persona_hint, history,   # ← 9 个业务参数
) -> AsyncIterator[QuestionStreamEvent]
```

LLM 层认识了「年级」「知识点」「学科 Persona」「兴趣池」。对比 `pi`：`streamFn(model, context, options)` 只认识 messages + model。

**代价是双向的：**
- 加业务（比如「学情诊断」）→ 必须给 `LLMProvider` 加方法、加参数 → 改共享内核。
- 换 provider（比如上 Anthropic 原生）→ 新实现必须理解全部教育业务语义。

ADR-0021 已经写了「RAG / 学科 Persona 在调用方注入」，但只做了一半：`rag_context` 和 `persona_hint` 仍然作为参数透传进了 provider，prompt 组装散落在 `generation.py`（出题）和 `genkit_provider.py`（答疑/批改/出题）两处。**这个 seam 切错了位置。**

### 3.2 「工具」是谎言

`manifest.py` 自己承认：

> 注意：**当前没有运行时 tool 调度器**——调用由 SubAgent 硬编码，本字段仅作文档与未来接线点。

实测三个 `subagents/*/tools/` 目录**全是空的**（只有 `__init__.py`）。`app/ai/tools/__init__.py` 里的 `list_tasks`/`search_knowledge` 是普通函数，不是 LLM 可调用的工具声明。

所以 `TOOL_CALL` / `TOOL_RESULT` 帧是**装饰性的**：模型从来没见过 schema，从来没做过选择，调用顺序是 `QuestionSubAgent.run()` 里手写的 for 循环。这不是 agent，这是**带进度条的脚本**。

### 3.3 层不可独立消费

`pi` 的纲领是 *"Use as much or as little as you need"*——可以只用 `pi-ai` 调 LLM，或只用 `pi-tui` 做 UI。

本项目的层做不到：不能只用 protocol 不用 runtime，不能只用 subagents 不带 endpoint。它们是同一条 SSE 管道的切段。**这不一定是错**（ADR-0029 明确定位为 Decode→Demux→Parse→Translate 管线），但要清醒：这套分层的价值是**管线的可替换段**，不是**能力的可选组合**。别拿 `pi` 的渐进式组合叙事套它。

---

## 4. 与 `pi` 的其余差异（中性或各有取舍）

| 维度 | `pi` | 本项目 | 判断 |
|---|---|---|---|
| **skills 语义** | extension = 生命周期钩子（`context`/`before_compact`/`tool_call`），**在模型上下文之外**改行为，LLM 看不见 | `skills/*.md` 全文拼进 prompt，**喂给模型** | 名字撞车，语义相反。本项目是「数据面」，`pi` 是「控制面」。两者都需要，本项目缺控制面 |
| **session 持久化** | JSONL 树，append-only、可 branch、crash-safe、显式 compaction | `Conversation`/`Message` 关系表，扁平、无分支、**无 compaction** | 关系表对儿童产品是对的（家长可见、审计、配额计数）。但 compaction 是空白——`history[-6:]` / `history[-10:]` 是硬截断 |
| **意图路由** | 无（单 agent；多 agent 在应用层 per-channel 隔离） | 下沉进 runtime：`manifest.triggers`(规则) + `hints`(启发式) + `priority` | 本项目场景合理（一个对话框服务双角色三业务）。但规则路由脆：「练习」命中 question，「任务题目」要靠 priority 抢。ADR-0030 删 LLM 插槽的理由（确定性 + 省一次往返）成立，代价是能力被词表锁死 |
| **依赖注入粒度** | `streamFn`（函数级，可拦每次请求，OpenClaw 用它加 header / prompt caching） | `build_provider(engine=)`（对象级，构建后固定） | `pi` 的 seam 更细。本项目 ADR-0030 收口「引擎单一解析链」方向对，但粒度粗 |
| **拦截/中间件** | extensions + streamFn 包裹，位置明确 | 无统一拦截点。安全闸门散在 `runtime.decide`(输入) + `TutorService`(输出) + `parsers`(产出) 三处 | 本项目缺一个「控制面」挂载点 |
| **provider 数量** | 2000+ 模型目录，`getModel(provider, id)` | 单实现 `GenkitProvider`；`resolve_engine` 三级（ModelConfig → BUILTIN → 全局） | 本项目够用。但 `LLMProvider` ABC 只有 1 个实现 = 抽象成本 > 收益，除非按 3.1 收窄接口 |

---

## 5. 改进建议（按性价比排序）

### P0 — 收窄 `LLMProvider` 到消息级接口

```python
# 现在：业务语义泄漏进 LLM 层
await provider.generate_question_stream(subject=..., grade=..., persona_hint=..., ...)

# 改成：provider 只认识 prompt + schema + 历史
async for ev in provider.stream(
    system=..., prompt=..., output_schema=QuestionSchema, history=...
) -> AsyncIterator[TextDelta | StructuredDone>
```

配套动作：把 `generation.py` 的 prompt 构造（`_build_question_prompt`）整体搬进 `subagents/question/`，`persona_hint`/`rag_context` 由 SubAgent 拼好再传。

**收益：** 加业务不改 provider；换 provider 不懂教育。这一步做完，`LLMProvider` ABC 才真正值回票价。

### P0 — 给「工具」一个说法，二选一

- **不做 tool loop（推荐）：** 删掉 `manifest.tools` 字段，`_tool()` 改名 `_step_begin()/_step_end()`，`TOOL_CALL`/`TOOL_RESULT` 帧改名 `STEP_START`/`STEP_END`。别再叫 tool。
- **做 tool loop：** `BaseSubAgent` 加 `tools: list[ToolSpec]`，runtime 里实现 loop。

**我的判断：选前者。** 当前三个业务都不需要 loop——出题是「生成一次」，答疑是「检索+生成一次」，查任务是纯 DB 查询。为了像 agent 而上 agent，是纯粹的负债。等真有「先查错题本 → 再决定出什么题」这种多步决策业务时再上。

### P1 — 加 compaction

`history[-6:]` / `history[-10:]` 硬截断是定时炸弹。最小方案：`Conversation` 加 `summary` 字段，消息数超阈值时用一次模型调用压缩，历史 = summary + 最近 N 条。

### P1 — 路由改「业务自带置信度」

不要回到 LLM 分类。让 `BaseSubAgent` 暴露 `can_handle(message, ctx) -> float`，manifest 的 triggers 只作为默认实现。路由规则随业务走（延续 ADR-0030 的「去硬编码」方向），且保持确定性。

### P2 — 消掉新的双源真相

`router._get_runtime()` 的模块级单例 与 `registry._CACHE` 的进程缓存，是**两处独立的发现结果**。ADR-0030 刚消灭了一处双源真相，这里又长出一处。让 registry 直接读 runtime 单例，或反过来。

---

## 6. 一句话给决策者

本项目的分层**在「数据流管线」这个定位下是自洽且扎实的**——错误不静默、解析分层清晰、发现即注册、测试可打桩。真正欠的债只有两笔：**`LLMProvider` 泄漏了业务语义**，以及 **`AgentRuntime`/`TOOL_CALL` 这两个名字承诺了不存在的 agent loop**。

先还这两笔，其余（compaction、路由置信度）按业务压力排期。
