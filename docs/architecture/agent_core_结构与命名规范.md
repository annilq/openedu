# agent_core 结构与命名规范

> 目标：把 `backend/` 的 Agent 层按 **ports-and-adapters（六边形）** 共识重新划分文件与命名，
> 让「内核 / 适配器 / 集成」三层职责清晰、命名可被外部工程师一眼读懂。
> 配套文档：`docs/architecture/agent_core_执行计划.md`（ADR-0031 落地计划）、`docs/decisions/娃娃学习App_ADR.md`（ADR-0031）。
> 状态：**第 1、2、3、4 阶段已落地**（① `seams.py` → `ports.py`；② 建 `agent_core/adapters/genkit.py` 并迁入 `segment.py`；
> ③ genkit SDK 构造收进适配器工厂 `build_genkit_engine`，`app/ai/engine.py` 退化为纯配置解析；
> ④ **Q3 拆分**：出题专属（`generation.py` + `parsers/question.py`）收进 `app/ai/subagents/question/`，
> `GradeSchema` 归 `app/domain/grader.py`，共享工具下沉 `app/domain/{prompts,structured}.py`，出题统一走 `LLMProvider`）。
> `pytest` **166 passed / 2 skipped**，`ruff` 干净；不变量已校验：内核零 `app.*`、**全后端唯一 `import genkit` 在适配器内**、
> **`app/ai` 顶层已无任何教育出题内容**。
> 其余阶段按项目纪律「先文档/ADR 后代码」，待拍板后执行。

---

## 0. 一句话

内核（`agent_core`）只放**协议 + 端口 + 编排**；具体引擎（genkit）实现放**适配器**（`adapters/`）；
教育业务放 **`app/`**。文件命名对齐六边形架构的 ports / adapters 共识。

---

## 1. 三层职责与依赖规则

| 层 | 目录 | 职责 | 允许依赖 |
|---|---|---|---|
| **内核 Kernel** | `backend/agent_core/` | 协议、端口（抽象）、编排、注册、路由、工具 | 仅标准库；零第三方、零 `app.*` |
| **适配器 Adapter** | `backend/agent_core/adapters/` | 把具体引擎（genkit）接到端口；**引擎 SDK 的唯一落点** | 内核 + 引擎 SDK（工厂内延迟导入） |
| **集成 App** | `backend/app/` | 教育业务（subagents / prompt / schema）+ 引擎解析（DB / 密钥 / 配置） | 全部 |

依赖方向**单向**：`app → adapters → kernel`。内核不知道任何人的存在。
这保证「换引擎只动适配器」「换业务只动 app」「内核是稳定基座」。

> 现状核对：`agent_core/` 内核 9 个模块**确实零 `app.*`**，且**零第三方 import**
> （其 `pyproject.toml` 里声明的 `pydantic>=2.0` 是**没人用的陈旧依赖**，建议删除）。
> 适配器（`adapters/`）用**工厂内延迟导入**持有 genkit：模块级仍零第三方依赖，未装 genkit 也能 import。
> 内核比文档写的还干净——这正是要守住的资产。

---

## 2. 关键概念解释

### 2.1 `segment` 是什么（现在在 `app/ai/segment.py`）

**它是一台「流式解码器」。**

大模型流式返回的不是整段文本，而是一串 **chunk**。genkit 的 chunk 结构是
`content: list[Part]`，其中 Part 按类型区分：`ReasoningPart`（原生思维链，如 DeepSeek-R1）
/ `TextPart`（正文）。上层解析管线不该知道这套厂商细节。

`segment.py` 把 genkit 的 chunk **归一化**成与厂商无关的 `Segment(kind, text)` 流：

```
genkit chunk 流  ──decode_stream()──▶  Segment(kind=REASONING|TEXT, text) 流
   （厂商形状）                          （中性形状，上层只认这个）
```

- `SegmentKind` = 语义通道（`REASONING` 思考 / `TEXT` 正文）。
- `decode_stream()` = 第 1 层解码，属于「解析管线的第 1 层」。
- **关键性质**：它用 duck-typing（`getattr(chunk, "content", ...)`）读字段，
  **根本不 import genkit** → 已经引擎无关，可脱离 genkit 单测。

**业内叫什么**：这是适配器的**流解码器 / 反腐蚀层**（anti-corruption layer）。
`segment` 是自造词；但类型名 `Segment` 可保留，模块本身按下面的方式归位。

**它该放哪**：它服务的是 **genkit 适配器**（引擎细节），不是教育业务。
现在放在 `app/ai/`（业务集成层）是**错层**——一个引擎无关的解码器待在业务包里。
→ 归 `agent_core/adapters/genkit.py`（与它的服务对象在一起）。

### 2.2 `contrib` 是什么（我上一轮的提案 → 现在改用 `adapters`）

`contrib` 是 Django 等框架的惯例：**随核心一起发布、但明确不属于核心契约的第一方可选扩展**。
我上一轮提议 `agent_core/contrib/genkit.py`，意思是"agent_core 官方附带的 genkit 适配器"——
让内核保持纯净，又不必让每个业务工程自己重写 genkit 胶水。

**但 `contrib` 不够精确，改用 `adapters/`。** 理由：
- 它是六边形架构里 **adapter** 的标准名——"坐落在端口上、满足接口的具体实现"。
- 与 `ports.py`（端口）天然成对：`ports` 定义接口，`adapters` 提供实现。一眼看懂。
- `contrib` 只表达"附带"，不表达"角色"；`adapters` 表达角色。

所以最终建议：`agent_core/adapters/genkit.py`，**不用 `contrib`**。

---

## 3. 目标目录树

```text
backend/
├── agent_core/                          # 内核 Kernel — 业务无关、引擎无关（稳定基座）
│   ├── __init__.py                      # 公共 API 再导出            [保持]
│   ├── protocol.py                      # 事件信封（AG-UI 线协议+构造器） [保持]
│   ├── ports.py                         # 端口：LLMProvider/Retriever/Safety/RuntimeDeps
│   │                                    #                            [← seams.py 改名]
│   ├── runtime.py                       # 编排：发现+路由+事件流        [保持]
│   ├── router.py                        # 意图路由                    [保持]
│   ├── registry.py                      # subagent 发现/注册          [保持]
│   ├── subagent.py                      # BaseSubAgent+Context+tool loop [保持]
│   ├── tools.py                         # ToolSpec/ToolRegistry       [保持]
│   ├── errors.py                        # 公共异常                    [保持]
│   └── adapters/                        # 第一方适配器（引擎 SDK 唯一落点）
│       ├── __init__.py                  # 再导出适配器公共符号          [已完成]
│       └── genkit.py                    # build_genkit_engine + GenkitLLMProvider + decode_stream/Segment
│                                        #   [已完成；← app/ai/segment.py + genkit_provider 纯分支 + engine.py 的 SDK 构造]
│
└── app/                                 # 教育业务集成层
    ├── ai/                              # ← 只留 genkit / DB 桥接（出题业务已全部归位 subagents）
    │   ├── engine.py                    # 模型引用→中性参数（ModelConfig/解密/settings），构造委托适配器
    │   │                                #   （app 层已无 `import genkit`）  [已完成]
    │   ├── model_catalog.py             # 服务商预设（产品配置）        [保持]
    │   │                                # （原 debug_log.py 于第 5 阶段删除：零调用方死代码）
    │   └── subagents/                   # 业务 SubAgent（发现即注册）
    │       ├── question/                # 出题子包 = 出题业务的完整归宿（ADR-0032 Q3）
    │       │   ├── pipeline.py          #   出题管线：prompt 组装 + step_label + stream_question
    │       │   │                        #   + generate_question（provider 非流式）  [新；← generation.py]
    │       │   ├── parsers.py           #   契约 QuestionSchema + SchemaQuestionParser
    │       │   │                        #   [← app/ai/parsers/question.py，已 git mv]
    │       │   ├── agent.py / manifest.py / translate.py + skills/
    │       ├── tutor/{agent,manifest}.py + skills/
    │       └── tasks/{agent,manifest}.py
    └── domain/
        ├── provider.py                  # EducationLLMProvider（LLMProvider 的教育扩展）
        ├── prompts.py                   # EDU_SYSTEM_PROMPT（出题/批改共享系统提示）  [新]
        ├── structured.py                # schema_field / coerce_dict（结构化产出读取，跨业务共用）[新]
        ├── grader.py                    # Grader + GradeSchema（批改契约，← generation.py 归位）
        └── ...                          # tutor/retriever/quota/safety/mastery/review_scheduler
```

---

## 4. 命名对照表（旧 → 新，含业内依据）

| 现名 | 建议 | 业内依据 | 风险 |
|---|---|---|---|
| `agent_core/seams.py` | `agent_core/ports.py` ✅ **已完成** | 六边形架构「端口」；与 `adapters` 成对。"seam" 是测试词汇，非框架词汇。 | 低（纯改名，13 处 import） |
| `app/ai/segment.py` | `agent_core/adapters/genkit.py` ✅ **已完成**（`segment.py` 已删） | 引擎适配器的流解码器，归适配器层。 | 低（4 处 import） |
| （我上轮提案的 `contrib`） | `agent_core/adapters/` | 六边形「适配器」，比 `contrib` 更精确表达角色。 | — |
| `app/ai/debug_log.py` | `app/ai/observability.py` | 业内「可观测性」通用词。 | 低 |
| `app/domain/genkit_provider.py` | **拆分**：genkit 纯胶水 → `agent_core/adapters/genkit.py` ✅ **已完成**；教育方法（`tutor`/`grade_open`）→ 留 app | 端口实现（适配器）vs 业务。 | 中（见 §7） |
| `app/ai/generation.py` | **删除**，内容按归属拆走 ✅ **已完成** | 它同时混了「出题业务」与「批改 schema」，两个都不该待在共享 AI 层。 | 中（见 Q3 分析） |
| `app/ai/generation.py` 的 `GradeSchema` | `app/domain/grader.py` ✅ **已完成** | 它是**批改**的 schema，不是出题的。 | 低 |
| `app/ai/generation.py` 的出题管线（prompt/`stream_question`） | `app/ai/subagents/question/pipeline.py` ✅ **已完成** | 出题业务归出题子包。 | 低 |
| `app/ai/parsers/question.py` | `app/ai/subagents/question/parsers.py` ✅ **已完成**（`git mv`） | 出题契约 + 解析器同源，归出题子包；`parsers/` 本就是单文件伪通用包。 | 低 |
| `schema_field` / 出题·批改共享系统提示 | `app/domain/{structured,prompts}.py` ✅ **已完成** | 跨业务共用件下沉共享内核，避免 domain → 业务子包的反向依赖。 | 低 |

**建议改名但非必须**（可后议）：
- `agent_core/subagent.py`：内含 `BaseSubAgent` + `SubAgentContext` + `run_with_tools`（其实是一个 **agent loop**）。
  更"深"的切法：拆 `agent.py`（基类+上下文）与 `loop.py`（`run_with_tools`）。**暂不改**，避免无谓抖动。
- `app/ai/tools/` 与 `app/ai/subagents/*/tools/`：ADR-0030 已删 `manifest.tools`，这些是**普通 helper 函数**，
  `tools/` 名已名不副实（是"工具"命名的遗留谎）。若短期不引入真 tool loop，建议改 `helpers/` 或并入对应 subagent。

---

## 5. 明确不改的（已符合业内共识）

`protocol.py` / `runtime.py` / `router.py` / `registry.py` / `tools.py` / `errors.py` / `subagents/` 目录结构
（`<business>/{agent,manifest}.py + skills/`）——这些命名就是业界通用叫法，保持。

---

## 6. 迁移影响（精确 blast radius）

### `seams` → `ports`（13 个文件）
- 内核内部 3 处：`agent_core/__init__.py:27`、`runtime.py:33`、`subagent.py:23`
- app 侧 4 处：`app/domain/safety.py:14`、`app/domain/genkit_provider.py:19`、`app/domain/provider.py:18`、
  `app/ai/generation.py:29`、`app/features/assistant/router.py:34`
- 测试 5 处：`tests/domain/test_tutor.py:5`、`tests/utils/fake_provider.py:21`、
  `tests/ai/{test_question_subagent_stream,test_subagents_seam,test_agent_runtime}.py`
- 文档字符串引用：`genkit_provider.py:3`、`provider.py:1,3` 等（同步改）。

### `segment` 移位（4 个文件）
- `app/ai/generation.py:39`、`app/ai/parsers/question.py:22`、`app/domain/genkit_provider.py:27`
- `tests/ai/test_generate_question_stream.py:19`（含 `Segment`/`SegmentKind`）

### 打包 ✅ **已定（见 §8 第 3 项）**
- 原状：`backend/pyproject.toml` 的 `[tool.hatch.build.targets.wheel] packages = ["app"]` **不含 `agent_core`**；
  且 `agent_core` 另有独立 `agent_core/pyproject.toml`（含无人使用的陈旧 `pydantic>=2.0` 声明）。
- **现决定：随 app wheel 一起打包、不单独发布** —— `packages = ["app", "agent_core"]`，
  **并删除 `backend/agent_core/pyproject.toml`**（一个产物只留一份构建定义）。

---

## 7. 落地顺序（分阶段，每阶段独立可验证）

1. ✅ **`seams.py` → `ports.py`（已完成）**：`git mv` 改名 + 全量 import 替换（13 处）+ 文档串同步。
   零逻辑改动；`pytest` **155 passed / 2 skipped**，`ruff` 干净（7 处 import 排序自动修正）。
2. ✅ **建 `agent_core/adapters/`（已完成）**：新增 `adapters/__init__.py` + `adapters/genkit.py`
   （`Segment`/`SegmentKind`/`decode_stream`/`_chunk_text`/`_as_dict` + `GenkitEngine` + `GenkitLLMProvider`）；
   `app/ai/segment.py` 已删（4 处 import 改指适配器）；`GenkitProvider.stream` 改为**委托适配器**
   （`tutor`/`grade_open` 留 app）。新增 `tests/ai/test_genkit_adapter.py`（7 例）钉住所适配器契约 + app 委托。
   **适配器 import 期零第三方依赖**：genkit 在工厂函数体内**延迟导入**，未装 genkit 时模块仍可 import；
   `GenkitLLMProvider` 以 duck-typing 调用 `genkit.generate_stream`。内核零依赖不变量保持。
3. ✅ **`app/ai/engine.py` 瘦身（已完成）**：新增适配器工厂 `build_genkit_engine`（构造 Genkit 实例 +
   provider 前缀 + 实例缓存，genkit 的唯一落点）；`engine.py` 只解析 ModelConfig / 解密 / settings →
   中性参数后委托工厂，**删掉 `from genkit import ...` 等三行**，`EngineResolution` 形状不变（`genkit` 字段改 `Any`）。
   新增 4 例适配器工厂/不变量测试（AST 级校验 engine 无 genkit import、适配器仅函数内 import）。
   全后端 `import genkit` 仅剩适配器 3 行；`pytest` **166 passed / 2 skipped**，`ruff` 干净。
4. ✅ **Q3 拆分（已完成）**——`app/ai` 只剩 genkit/DB 桥接：
   - 新增 `app/ai/subagents/question/pipeline.py`：收纳出题 prompt 组装（`build_question_prompts`）、
     `step_label`、`stream_question`，并新增 **provider 版非流式** `generate_question`（内部 drain `stream_question`）；
   - `git mv app/ai/parsers/question.py → app/ai/subagents/question/parsers.py`（`parsers/` 伪通用包已删）；
   - `GradeSchema` → `app/domain/grader.py`；共享件下沉 `app/domain/structured.py`（`schema_field`/`coerce_dict`）
     与 `app/domain/prompts.py`（`EDU_SYSTEM_PROMPT`，原文照搬零行为变更）；
   - **废弃 engine 版出题**：`_generate_question(_stream)` / `generate_question_stream` 删除，
     `app/features/tasks/router.py`（落库重生成）改走 `build_provider(engine=…)` + provider 版 `generate_question`，
     出题自此**只依赖 `LLMProvider`**；`app/ai/generation.py` 已删。
   `pytest` **166 passed / 2 skipped**，`ruff` 干净；`app/ai` 顶层零出题内容、零 `import genkit`。
5. ✅ **删除 `app/ai/debug_log.py`（已完成，偏离原计划）**：原计划是改名 `observability.py`，
   动手前查证发现它是**零调用方死代码**——`start_agent_run` / `log_agent_message` / `finish_agent_run`
   在后端无任何引用；其 docstring 里引用的 `flows._log_tutor`（`app/ai/flows.py`）早已删除；
   其职责（运行观测落库）已由 `app.features.assistant` 承担（ADR-0026 废除 `debug_log`）。
   读路径 `/ai/debug/conversations` 走的是 `app/features/ai/repository`，与本文件无关。
   故**删除**而非改名。`app/ai/__init__.py` docstring 同步清理。
   `pytest` **166 passed / 2 skipped**，`ruff` 干净。

**连带清理（已完成）**：`app/features/ai/repository.py` 的
`create_conversation` / `add_message` / `finish_conversation` 三个写函数，唯一调用方就是被删的 `debug_log.py`，
属连带死代码，已一并删除；保留只读的 `list_conversations` / `get_conversation_messages`
（`/ai/debug/conversations` 在用），模块文档改注为「只读回放」。

每阶段结束跑：`cd backend && CODEBUDDY_BROKERED_FS_HOOK_ENABLED=0 CODEBUDDY_SAFE_DELETE_SANDBOX=0 /opt/homebrew/bin/uv run pytest -q` + `ruff check .`。

---

## 8. 待决问题

1. ~~**`ports.py` 还是 `contracts.py`？**~~ **已定：`ports.py`**（第 1 阶段落地）。
2. ~~**适配器放包内还是独立包？**~~ **已定：(a) 包内** `agent_core/adapters/`（第 2、3 阶段落地）。
   若日后内核要与引擎**彻底剥离发布**，再迁 `agent_core_genkit/`（独立包，依赖 `agent_core`）。
3. ~~**`agent_core` 是否随 `app` wheel 一起打包？**~~ **已定：随 app wheel 一起打包，不单独发布**
   （`backend/pyproject.toml` → `packages = ["app", "agent_core"]`）。随之**删除 `backend/agent_core/pyproject.toml`**
   （一个产物只留一份构建定义）。实测 wheel 含 `agent_core/` 全部 11 个文件、隔离安装可用。
   取代 ADR-0031 执行计划第 7 步的「发布到内部 PyPI」；若日后要独立分发，再另建独立仓/pyproject。
4. ~~**是否把本提案固化为 ADR-0032？**~~ **已定：是** —— 已写入 `docs/decisions/娃娃学习App_ADR.md`（正文「ADR-0032 `agent_core` 分层边界与命名收敛」，承接 Q1/Q2/Q3/Q4 四个判断 + 五阶段落地）。

---

## 附：与 ADR-0031 的关系

ADR-0031 抽出了内核并**刻意保持引擎无关**。本规范是该决定的**命名与目录落细**，
并回答「genkit 该放哪」：**放 `adapters/`，不放内核、也不放业务包**。
它与 ADR-0031 的"零 `app.*` 依赖"一致，同时补上"零引擎依赖 → 引擎走适配器"的边界。
