# agent_core 重构执行计划（ADR-0031 落地）

> 配套：ADR-0031（Agent 抽象层抽取为通用框架 `agent_core`）。
> 模式：一步到位大重写（用户决策）。本计划只描述「做什么 / 改哪些文件」，不在此阶段改代码。
> 原则：教育业务**零断流**——抽前冻结契约、契约测试守护、抽完一次性切换 + 全量回归（见「前置」与「回滚」）。

---

## 目录结构目标

```
backend/
  agent_core/                 # 新：业务无关通用框架（独立可安装包，零 app.* import）
    pyproject.toml
    __init__.py               # 导出 AgentRuntime / BaseSubAgent / AssistantEvent / seams / ToolSpec
    protocol.py               # AssistantEvent 信封 + 便捷构造器（泛型化，去掉 DATA.type/blocked 特例）
    seams.py                  # LLMProvider(消息级) / Retriever / Safety 抽象基类 + 通用数据类
    registry.py               # 文件夹发现 + SubAgentManifest + build_subagent（合并现有两套）
    router.py                 # 规则+启发式 classify + 可插拔 llm_classify
    runtime.py                # AgentRuntime：发现/路由/真实 tool loop/统一事件流（seam 注入）
    tools.py                  # ToolSpec + 执行器
    subagent.py               # BaseSubAgent + SubAgentContext（去掉教育字段）+ ToolCall
    errors.py                 # AgentError 等
  app/
    ai/                      # 改为「教育集成层」，仅依赖 agent_core（删光通用代码）
      __init__.py            # 清理惰性导出（仅留教育相关兼容 shim）
      engine.py              # 保留（教育引擎解析，仅集成层用）
      segment.py             # 保留（genkit 解码，教育特定）
      debug_log.py           # 保留（观测，教育特定）
      model_catalog.py       # 保留
      subagents/
        base.py              # 删除（→ agent_core/subagent.py）
        registry.py          # 删除（→ agent_core/registry.py）
        subject_personas.py  # 保留（教育特定）
        question/            # 重写：自有 prompt 组装 + provider.stream + 解析 + 翻译帧
          agent.py  manifest.py  skills/  tools/
          generation.py      # 从 app/ai/generation.py 迁入（prompt 组装归 subagent）
          parser.py          # 从 app/ai/parsers/question.py 迁入
        tutor/  tasks/       # 重写：实现 agent_core.BaseSubAgent，自选 tool loop
    domain/
      provider.py            # 删除 LLMProvider ABC（→ agent_core.seams）；教育结构体迁出
      genkit_provider.py     # GenkitProvider 改为继承 agent_core.seams.LLMProvider（实现 stream）
      llm_provider.py        # 新增：re-export agent_core.seams.LLMProvider + 教育结构体
    features/assistant/router.py  # 改用 agent_core，注入 seam，保留鉴权/配额/落库
```

---

## 前置（必做，先于任何改动）

1. **冻结教育端契约快照**，作为回归基线：
   - SSE 帧结构（`eventType` 枚举、`AssistantEvent` 字段名）、`RouteDecision(business/name/subject)`、`BaseSubAgent.run(message, ctx)` 签名、三个 subagent 的 `manifest` 路由词。
   - 落盘到 `tests/contracts/edu_assistant_baseline.json`（或文档段落），后续契约测试对照。
2. **建契约测试骨架** `tests/agent_core/`，先于实现写好「应得行为」用例（见各步验收点），实现完成时即跑通。

---

## Step 1 — 建 `agent_core` 包骨架 + 抽象 seam + 信封

**目标**：独立包就位，零业务依赖，定义全部抽象 seam 与通用信封。

| 动作 | 文件 | 说明 |
|---|---|---|
| 新建 | `agent_core/pyproject.toml` | name=`agent_core`；requires-python≥3.11；**不依赖 app**；可选 pydantic |
| 新建 | `agent_core/__init__.py` | 导出 `AgentRuntime, BaseSubAgent, AssistantEvent, ToolSpec, LLMProvider, Retriever, Safety` |
| 新建 | `agent_core/protocol.py` | 从 `app/ai/runtime/protocol.py` 搬 11 种 eventType + `to_sse()`；**泛型化**：`data_event(payload, *, status=None, extra=None)` 去掉 `type` 位置参；`assistant_message(text, *, blocked=None, extra=None)` 保留 `blocked` 顶层（前端依赖，且非教育专有） |
| 新建 | `agent_core/seams.py` | `LLMProvider(ABC)` 仅 `stream(system, prompt, schema=None, history=None) -> AsyncIterator[TextDelta\|StructuredDone]`；`Retriever(ABC)` 仅 `retrieve(query, *, top_k=5) -> list[Chunk]`；`Safety(ABC)` `check_input(text)->SafetyResult`；数据类 `Chunk/TextDelta/StructuredDone/SafetyResult` |
| 新建 | `agent_core/errors.py` | `AgentError` |

**验收**：`python -c "import agent_core"` 成功；`agent_core` 内 `grep -rn "app\."` 为空；seam 接口可被 fake 实现。

---

## Step 2 — 迁 registry / router / runtime（去业务依赖，改注入 seam）

**目标**：通用三件套搬进 `agent_core`，不再 import `app.domain/app.features/app.db/app.core`。

| 动作 | 文件 | 说明 |
|---|---|---|
| 新建 | `agent_core/registry.py` | 合并 `app/ai/runtime/manifest.py`（`SubAgentManifest` + `discover_subagent_manifests`）+ `app/ai/subagents/registry.py`（`build_subagent`）。发现路径由参数传入（不再硬编码 `app.ai.subagents`） |
| 新建 | `agent_core/router.py` | 从 `app/ai/runtime/intent_router.py` 搬 `classify`，签名改为 `classify(message, available, manifests, *, llm_classify=None)`；默认规则+启发式，弱意图可注入 LLM 分类器 |
| 新建 | `agent_core/runtime.py` | 从 `app/ai/runtime/runtime.py` 搬 `AgentRuntime`/`RouteDecision`；**删除** `from app.domain import build_provider, build_retriever`、`from app.domain.safety import check_input`、`from app.ai.engine import resolve_engine`；改为构造注入：<br>`AgentRuntime(manifests, deps: RuntimeDeps)`，`RuntimeDeps(provider, retriever=None, safety=None, llm_classify=None)` |
| 修改 | `agent_core/runtime.py` `decide()` | 用 `self._deps.safety.check_input` 替 `check_input`；**删除 `_detect_subject`**（教育特定，下放到集成层）；`RouteDecision` 去 `subject` 字段，加 `confidence`/`extra` |
| 删除 | `app/ai/runtime/` 整目录 | 全部迁出后删除 |
| 删除 | `app/ai/subagents/base.py`、`app/ai/subagents/registry.py` | 迁出后删除 |
| 修改 | `app/ai/subagents/__init__.py` | 移除 `build_subagent` 导出（改由集成层组装） |

**验收**：`AgentRuntime` 用全 fake seam 可发现 + 路由 + 产出事件流；`grep` 确认 `agent_core` 无 `app.` 依赖；`RouteDecision` 不再含 `subject`。

---

## Step 3 — 真实 tool loop + `BaseSubAgent.tools`

**目标**：框架具备「模型选型→执行→回灌→循环」能力；subagent opt-in。

| 动作 | 文件 | 说明 |
|---|---|---|
| 新建 | `agent_core/tools.py` | `ToolSpec(name, description, schema: dict, handler)` + `ToolExecutor`（`execute(name, args)`）；异常转 `ERROR` 帧 |
| 新建 | `agent_core/subagent.py` | 从 `app/ai/subagents/base.py` 搬 `BaseSubAgent`+`ToolCall`；`SubAgentContext` **只留通用字段** `role, message, history, model, skills, extra`（删 `subject/grade/knowledge_point/allowed_subjects/focus_interest`，教育字段进 `extra`）；新增类属性 `tools: list[ToolSpec] = []`（默认空=不走 loop） |
| 修改 | `agent_core/runtime.py` `run()` | 若 `agent.tools` 非空：首轮把 tool schema 随请求发给 provider → 收到 `tool_call` 帧→`ToolExecutor` 执行→`tool_result` 回灌历史→再请求，循环至 `done`；每步 yield `TOOL_CALL`/`TOOL_RESULT`（真实模型决策，非硬编码） |
| 删除 | `app/ai/subagents/base.py` | 已迁出 |

**验收**：契约测试——fake provider 先回 `tool_call` 再回终态文本，`run()` 必须执行 handler 且事件序为 `…TOOL_CALL→TOOL_RESULT→ASSISTANT_MESSAGE…`；`tools=[]` 时直接一次性生成，无 loop。

---

## Step 4 — 收窄 `LLMProvider` 到消息级 + 搬 prompt 组装

**目标**：通用 provider 不认识「年级/知识点」；教育 prompt 组装归 subagent。

| 动作 | 文件 | 说明 |
|---|---|---|
| 修改 | `agent_core/seams.py` | `LLMProvider` 已仅 `stream(...)`；**不含** `generate_question/tutor/grade_open` |
| 修改 | `app/domain/genkit_provider.py` | `GenkitProvider(agent_core.seams.LLMProvider)`，实现消息级 `stream`；删除 `generate_question_stream/tutor/grade_open` 方法 |
| 新建 | `app/domain/llm_provider.py` | re-export `agent_core.seams.LLMProvider` + 教育结构体（`GeneratedQuestion` 等迁此） |
| 删除 | `app/domain/provider.py` | 旧 `LLMProvider` ABC 与 `QuestionStreamEvent` 等迁走后删除（避免双真相） |
| 移动 | `app/ai/generation.py` → `app/ai/subagents/question/generation.py` | `_QUESTION_SYSTEM_PROMPT`/`_build_question_* `/`generate_question`/`generate_question_stream` 全部归 question subagent 自有 |
| 移动 | `app/ai/parsers/question.py` → `app/ai/subagents/question/parser.py` | `QuestionSchema`/`QuestionSpec`/`SchemaQuestionParser` 教育特定，随 subagent |
| 修改 | `app/ai/subagents/question/agent.py`（重写，见 Step 6） | 用自有 `generation` 组装 prompt → `provider.stream(...)` → 自有 `parser` 解析 → 翻译帧 |

**验收**：`GenkitProvider` 满足 `isinstance(x, agent_core.seams.LLMProvider)`；`grep` 确认 `app/domain` 无 `generate_question_stream` 旧签名；出题 subagent 端到端可调通（mock provider）。

---

## Step 5 — 翻译/解析下沉，core 只留信封↔SSE

**目标**：`agent_core` 领域无关，只负责信封与传输。

| 动作 | 文件 | 说明 |
|---|---|---|
| 删除 | `app/ai/runtime/translate.py` | 其 `QuestionCard→DATA` 翻译是教育语义，迁入 question subagent |
| 移动 | 翻译逻辑 → `app/ai/subagents/question/agent.py` | subagent 自行把 `QuestionCard` 翻成 `data_event(payload, extra={"type":"question"})`；思维链攒批 helper 可留 `agent_core` 作通用工具（如 `agent_core/protocol.py:coalesce_thinking`） |
| 确认 | `agent_core` 无 `parsers`/`translate`/`domain` 引用 | core 仅 `protocol` + SSE |
| 删除 | `app/ai/parsers/` 仅留 question，已迁（见 Step 4） | 空目录删除 |

**验收**：`agent_core` 不含任何业务语义类型（`QuestionCard` 等不得 import）；出题 subagent 自己产出正确 `DATA` 帧。

---

## Step 6 — 教育仓作为首个接入方重写 + 端点改用 agent_core

**目标**：三个 subagent 重写为 `agent_core.BaseSubAgent` 实现；端点保留鉴权/配额/落库。

| 动作 | 文件 | 说明 |
|---|---|---|
| 重写 | `app/ai/subagents/question/agent.py` | `class QuestionAgent(agent_core.BaseSubAgent)`；`tools=[]`（一次性生成）；内部用 `generation`+`parser`+翻译帧；`run()` yield `THINKING`(推理)→`DATA`(题卡)→`ASSISTANT_MESSAGE` |
| 重写 | `app/ai/subagents/tutor/agent.py` | 包 `domain.tutor.TutorService`；`tools=[]` 保持一次性伴学（与现状一致）；subject 检测移到 `app/ai/subagents/tutor/detect.py`，供端点配额复用 |
| 重写 | `app/ai/subagents/tasks/agent.py` | **采用真实 tool loop 作示范**：声明 `tools=[list_tasks_tool, search_knowledge_tool]`（`ToolSpec` 包装现有 `app/ai/tools` 的 `list_tasks`/`search_knowledge`，handler 调 `app.features.tasks.repository`）；证明框架能力端到端 |
| 移动 | `app/ai/tools/__init__.py` 内容 → `app/ai/subagents/tasks/tools.py` | 业务 helper 归 tasks subagent；`ToolSpec.handler` 包裹之 |
| 重写 | `app/features/assistant/router.py` | `from agent_core import AgentRuntime, RouteDecision`；构造 `AgentRuntime(discover_subagent_manifests(EDU_DIR), deps=RuntimeDeps(provider=GenkitProvider(...), retriever=..., safety=EduSafety(...), llm_classify=None))`；删除 `decision.subject` 直接用法，配额所需 subject 由 `detect_subject`（tutor 域）在端点内单独算；保留配额/TutorLog/落库/会话持久化 |
| 清理 | `app/ai/__init__.py` | 删除 `generate_question`/`QuestionSchema`/`resolve_engine` 惰性导出（或改为指向集成层新路径的 shim） |
| 新增 | `app/agent_integration/` 装配模块（可选） | 集中构造 `RuntimeDeps`（provider/retriever/safety 实现装配），端点一行注入 |

**验收**：`uv run pytest` 教育相关用例全绿（含出题/伴学/查任务三类）；`uv run fastapi dev` 跑通 `/assistant/chat`；真机验证出题流式、伴学、查任务工具调用。

---

## Step 7 — 发布 + 契约测试 + 全量回归

| 动作 | 文件 | 说明 |
|---|---|---|
| 发布 | `agent_core/pyproject.toml` | 语义化版本 + CHANGELOG；`uv build` → 内部 PyPI（`uv publish` / `twine`，配 `[[tool.uv.index]]`）；教育仓改 `pip install agent_core` 或维持 editable |
| 测试 | `tests/agent_core/` | 契约测试：fake seam 下发现/路由/一次性生成/真实 tool loop/安全拦截/异常兜底全覆盖 |
| 测试 | `tests/conftest.py` + `tests/utils/fake_provider.py` | `FakeLLMProvider` 改为实现消息级 `stream`（与 ADR-0030 mock 红线一致，不接真模型） |
| 回归 | 全仓 | `uv run pytest`（目标 146 passed 2 skipped）、`uv run ruff check .`、`flutter analyze`、`flutter test`（前端见下） |

---

## 前端影响（协议变更面）

核查 `frontend/lib/features/assistant/`：仅消费 `ev.blocked`（floating_assistant.dart:298、assistant_event.dart:32）与 `ev.data` 字典（assistant_notifier.dart:146，**无 `data['type']` 依赖**）。

- **保留** `AssistantEvent.blocked` 顶层字段（非教育专有，前端依赖）→ 前端零改动。
- **`DATA.type` 教育语义移到 `extra`**：前端未读，无影响。
- 若需把教育业务标记传前端 UI，经 `extra` 字典透传（新增 `extra` 字段读取即可，非必须）。
- 结论：`lib/features/assistant/domain/assistant_event.dart` 加一个可选 `extra` 字段即可，其余文件不动。回归：`flutter analyze` + `flutter test`。

---

## 风险与回滚

- **大重写中途不可运行**（用户已知）。缓解：Step 2 完成后即跑通 fake-seam 契约测试；Step 6 才切端点；切前分支可整包回退（agent_core 新建、app/ai 改动集中在集成层，git 可独立 revert）。
- **`decision.subject` 移除影响配额**：端点内对 `business=='tutor'` 单独调 `detect_subject`（复用 tutor subagent 已有函数），不依赖 runtime 返回值。
- **真实 tool loop 多轮往返**：内置超时/重试/熔断；tool 执行同步可预期，异常转 `ERROR` 帧（沿用儿童产品确定性前提）。
- **双真相窗口**：旧 `app/domain/provider.py` 与 `agent_core.seams.LLMProvider` 并存期最长只跨 Step 4→Step 6，Step 6 完成后删除旧文件。
- **回滚开关**：端点注入 `RuntimeDeps` 处保留一行注释切换点；若新 runtime 异常，可临时指回旧 `app/ai/runtime` 副本（建议重构前 `git tag pre-agent-core`）。

---

## 执行顺序（依赖关系）

```
前置(冻结契约+契约测试骨架)
  → Step1(包+seam+信封)        ← 无依赖
  → Step2(registry/router/runtime 去依赖)  ← 依赖 Step1
  → Step3(tool loop)           ← 依赖 Step1,2
  → Step4(provider 收窄+搬 prompt) ← 依赖 Step1
  → Step5(翻译下沉)            ← 依赖 Step3,4
  → Step6(教育 subagent 重写+端点切换) ← 依赖 Step3,4,5
  → Step7(发布+回归)           ← 依赖 Step6
```

建议每完成一步即跑 `ruff` + 该步契约测试，Step 6 完成后做全量回归与真机验证（符合你「真机验证门禁」习惯）。
