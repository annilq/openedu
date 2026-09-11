# 后端 Agent Core 与 AI 集成架构评审

> 依据参考链接（How to Build a Custom Agent Framework with PI / OpenClaw 的 agent stack）对照当前 `backend/agent_core` 与 `app/ai` / `app/features/assistant` 的集成设计。
> 评审日期：2026-09-11

## 0. 结论（结论先行）

**整体合理，分层方向正确，且约束是机制化守住的（不是靠纪律）。** 当前代码与参考链接的「分层可组合、避免抽象锁定、端口隔离、统一事件流、后台扩展不改 LLM 上下文」核心原则高度同构。

可以放心继续按这个骨架演进。但有三类偏差需要你拍板：

1. **缺少 context compaction（上下文压缩）** —— 长会话会直接打爆上下文窗口，参考架构把它列为生产必需。
2. **缺少后台扩展钩子（extension/hook seam）** —— 参考的 `pi-coding-agent` 有生命周期钩子；当前只靠 manifest 把 SOP 注入 system prompt（LLM 可见），没有 LLM 不可见的干预点。
3. **ADR 文档查无此物** —— 代码 docstring 大量引用 `ADR-0033 / 0021 / 0003 / 0031 / 0032 …`，但仓库里没有对应的 ADR 文件（只有 `docs/agents/*`，`CONTEXT.md` 仅 71 行）。决策被引用却未记录，是治理风险。

其余偏差（单引擎适配器、无 JSONL 分支会话树）在当前产品形态下是合理取舍，见第 5 节。

---

## 1. 参考架构要点（gist 提炼）

| 层 | 职责 | 关键原则 |
|----|------|----------|
| `pi-ai` | 统一 LLM 接口，多 provider，streaming / tool def / cost tracking | 切换 provider 只改一行 `getModel` |
| `pi-agent-core` | agent loop、tool 执行、事件流 | 用户只写 tools，loop 由框架跑 |
| `pi-coding-agent` | 完整 runtime：内置文件工具、JSONL 分支会话树、context compaction、extensions | 「用多少算多少」，默认从这里起步 |
| `pi-tui` | 终端 UI（differential render / markdown / editor） | 架构不变，只换渲染层 |

四条总原则：**(a) 分层可组合、避免抽象锁定；(b) 优先从 coding-agent 起步，仅不需内置工具时下沉到 agent-core；(c) 会话以 JSONL 分支树持久化；(d) 扩展置于后台，不改 LLM 上下文。**

---

## 2. 当前架构与参考的映射

| 参考层 | 当前落点 | 对应关系 |
|--------|----------|----------|
| `pi-ai`（统一多 provider） | `agent_core/ports.py:LLMProvider` + `agent_core/adapters/genkit.py` + `app/ai/engine.py` + `app/ai/model_catalog.py` | ✅ 端口 + 单适配器 + 模型目录 + 单一解析链 `resolve_engine` |
| `pi-agent-core`（loop/tool/events） | `agent_core/runtime.py` + `subagent.py:run_with_tools` + `protocol.py` | ✅ 真实 tool loop + AG-UI 事件信封 |
| `pi-coding-agent`（完整 runtime + 工具 + 会话） | `app/ai/subagents/{query,question,tutor}/` + `features/assistant/router.py`（SSE + 落库） | ✅ 文件夹化 subagent + 统一 SSE 入口 |
| `pi-tui`（UI 层） | `frontend/lib/features/assistant/*` | ✅ 独立前端消费 SSE |

**关键印证（代码级）**：
- `agent_core` 内核（`agent_core/` 除 `adapters/`）**零 `app.*` 依赖**、**零第三方依赖**（`ports.py:7`、`runtime.py:10`）。
- `import genkit` 全工程唯一落点是 `agent_core/adapters/genkit.py`，且全部延迟导入（函数体内）——未装 genkit 也能 import 内核（`adapters/genkit.py:9-20`）。
- 这些不变量被 `tests/ai/test_layering_invariants.py` 以 **AST 静态扫描**固化为 9 条测试（内核无 app 依赖、无三方依赖、genkit 唯一落点、已删模块零残留、service 不反向依赖 router/fastapi、query 工具只经 service 取数、归属判定只经 `core.guard`）。**这是本架构最扎实的地方：越界在 CI 直接红。**

---

## 3. 设计合理之处（亮点）

1. **六边形端口干净**：`LLMProvider` / `Retriever` / `Safety` / `RuntimeDeps` 全是抽象，业务无关（`ports.py:44-138`）。`build_subagent` 只认抽象，可独立发包。
2. **真实 tool loop + 硬失败边界**：`run_with_tools`（`subagent.py:116-213`）有 `max_turns`（默认 3）防死循环、`ToolUnsupportedError` 硬失败而非静默降级为纯文本、`assistant.tool_calls → tool 结果`成对不变量。这正是参考里「工具回灌丢失→模型反复重调」那个坑的显式封堵（ADR-0033）。
3. **统一事件信封 + SSE**：`protocol.py` 的 `AssistantEvent`（AG-UI 式）与 `to_sse()`，前端按 `eventType` 分发。出题为 `STEP/THINKING/DATA/ASSISTANT_MESSAGE` 多帧，体验层与传输层解耦（`question/translate.py`）。
4. **单一 SSE 入口收敛**：所有 AI 能力统一到 `POST /api/v1/assistant/chat`（`features/assistant/router.py:112`），旧 `/ai/tutor/ask`、`/ai/tasks/generate` 已废弃（docstring 已记）。符合参考「一个入口组合各层」。
5. **路由确定可解释**：`router.py` 规则优先 + 启发式兜底 + 可选 LLM 分类，且角色可见性是唯一真相源（`runtime.py:63-91`）。对儿童产品路由确定性是合理要求。
6. **文件夹化 subagent + 发现即注册**：`registry.py:discover_subagent_manifests` 扫目录自动注册，新增 agent = 丢一个文件夹，无需手工登记——对应参考「use as much or as little as you need」。

---

## 4. 需要你拍板的偏差（风险）

### 4.1 缺 context compaction —— 高中危
- **现状**：`features/assistant/repository.py:27 load_chat_history(..., limit=20)` 直接把最近 20 轮塞进 prompt。全程无 summarization/compaction 逻辑（grep `compact` 全工程零命中）。
- **参考**：`pi-coding-agent` 把 compaction 列为生产必需——接近窗口限制时自动压缩，全历史留 JSONL、仅内存上下文压缩。
- **风险**：错题本/伴学多轮长对话（"再出两道类似的""讲讲刚才那题"）会逐渐撑爆上下文，且每次全量回灌增加延迟与 token 成本。
- **建议**：在 `run_with_tools` 回灌前或端点 `load_chat_history` 处加一层摘要压缩（按 token 预算截断 + 周期性 summary 帧），复用现有 JSONL/DB 历史即可，不必照搬 JSONL 分支树。

### 4.2 缺后台扩展钩子（extension seam）—— 中危
- **现状**：可扩展性全靠 `manifest.skill_prompt` 把 SOP 注入 system prompt（LLM 可见）。`agent_core` 内 grep `extension|hook|lifecycle` 零命中。
- **参考**：`pi-coding-agent` 有 `context` / `session_before_compact` / `tool_call` / `before_agent_start` 等 LLM 不可见的钩子（如静默修剪超大 tool result、多阶段压缩管线）。
- **风险**：现在想做"工具结果过大自动截断""请求前注入租户级 system 约束""审计每轮 tool_call"这类 LLM 不可见的事，只能改内核或各 subagent，缺少统一挂载点。
- **建议**：在 `AgentRuntime.run` / `run_with_tools` 增加可选的 `hooks` 接口（至少有 `before_turn` / `after_tool` / `rewrite_messages`），保持可选、零默认行为。

### 4.3 ADR 文档缺失 —— 治理高危
- **现状**：代码 docstring 大量引用 `ADR-0033 / 0021 / 0003 / 0031 / 0032 / 0030 / 0024 / 0026 / 0022 / 008 / 0014 / 0015 / 0017`，但仓库 `find docs -type f` 只有 `docs/agents/{domain,triage-labels,issue-tracker}.md`，`CONTEXT.md` 仅 71 行、不含 ADR 正文。本应存在的 `docs/adr/` 为空。
- **重要限定**：项目采用**单 context 懒创建约定**（`AGENTS.md` 规定 `CONTEXT.md` + `docs/adr/` 按需创建，非强制预建），因此 `docs/adr/` 空目录本身可能符合约定、不算缺陷。
- **真正的风险**：代码 docstring 把 `ADR-0033/0021/0003/…` 当作**已存在的决策记录**来交叉引用，但这些决策在任何可检索处（CONTEXT.md 或 docs/adr/）都查不到正文。无论走"懒创建"还是"独立 ADR 文件"路线，被引用的决策应当有**唯一可定位的事实源**。
- **建议**：二选一即可——(a) 在 `CONTEXT.md` 内为高频引用的 ADR（至少 0003/0021/0031/0032/0033）补一段决策摘要；或 (b) 按需落成 `docs/adr/ADR-00XX.md` 并让 docstring 链接过去。低成本、消除"引用悬空"。

---

## 5. 合理的取舍（不是缺陷）

- **单引擎适配器（只有 genkit）**：`LLMProvider` 端口已抽象好，未来加 `OpenAIProvider`/`AnthropicProvider` 只需新增一个 `adapters/*` 模块，内核零改动。当前只接 genkit 是范围问题，不是架构缺陷。
- **无 JSONL 分支会话树**：参考用 JSONL 分支树是因为单用户 CLI/崩溃安全 append-only。当前是 **DB-backed（`Conversation`/`Message` 表）多用户产品**，用关系表做持久化 + 归属校验（`core.guard`）更合适。分支/回放需求若真出现，可在现有表上加 `parent_message_id` 实现，不必照搬文件树。
- **question/tutor 不跑真实 tool loop**：出题是单调用流式（`stream_question` + `QuestionSchema` 约束解码），伴学走 `TutorService.aexplain`——符合 ADR-0033「opt-in 工具、用多少算多少」。只有 `query` 因需多步取数才声明 `QUERY_TOOLS` 走 `run_with_tools`（`query/agent.py:48-51`）。这是对的，不是遗漏。
- **路由即业务概念**：参考把 classify 当作 OpenClaw 的扩展；当前把「亲子双角色 + 触发词 + 优先级」做成一等公民（`router.py` + `manifest.py`），契合教育产品"娃娃端仅伴学/查询、家长端可出题"的权限模型，属合理产品化偏离。

---

## 6. 顺带一提：出题流式"闪现"问题

内存里记的「生成任务 5 秒后推理消息闪现而非持续 streaming」——**后端侧事件流结构是连续的**（`question/agent.py` 逐题 `STEP → translate_stream → DATA → ASSISTANT_MESSAGE`，`translate.py` 还做了 THINKING 攒批降帧数）。后端没有"攒 5 秒再一股脑吐"的逻辑。

**最可能的根因在前端**：SSE 缓冲未逐帧 flush、或只渲染 `ASSISTANT_MESSAGE` 而把中间 `THINKING/STEP/DATA` 帧挂起到最后才统一挂载。建议前端先确认是否对所有 `eventType` 做了即时 setState，而不是等 `DONE` 才渲染。这个不在本次后端架构评审范围内，但定位方向明确。

---

## 7. 建议落点（按优先级）

| 优先级 | 动作 | 判据 |
|--------|------|------|
| P0 | 补 `docs/adr/` 中被引用的 ADR（至少 0003/0021/0031/0032/0033） | `find docs/adr -name "ADR-00*.md"` 有文件且被 docstring 交叉链接 |
| P1 | 加 context compaction（token 预算截断 + 周期 summary） | `load_chat_history` 或 `run_with_tools` 出现压缩分支；长会话 e2e 验证不爆窗 |
| P2 | 加可选 `hooks` 接口（before_turn/after_tool/rewrite_messages） | `AgentRuntime` 接受 `hooks` 参数且默认无行为 |
| 待定 | 前端验证 SSE 逐帧渲染 | 出题时 THINKING/STEP 帧实时出现，非 5 秒后闪现 |

---

## 8. 关键文件索引

- 端口与事件：`backend/agent_core/{ports,runtime,subagent,protocol,tools,registry,router}.py`
- 引擎适配器（唯一 genkit 落点）：`backend/agent_core/adapters/genkit.py`
- 模型解析与目录：`backend/app/ai/engine.py`、`backend/app/ai/model_catalog.py`
- SubAgent：`backend/app/ai/subagents/{query,question,tutor}/{agent,manifest}.py`
- 出题管线与转换：`backend/app/ai/subagents/question/{pipeline,parsers,translate}.py`
- SSE 端点与装配：`backend/app/features/assistant/router.py`
- 分层不变量测试：`backend/tests/ai/test_layering_invariants.py`
