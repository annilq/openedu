# ADR-0098 二执行体拓扑：question 并入 tasks，students 先行吸收

- 状态：已实现
- 日期：2026-10-19
- 关联：ADR-0097（五域拓扑，**被本 ADR 收敛**）、ADR-0033（结论必须有据）、ADR-0024（出题子代理，**执行模型再变**）、ADR-0095（slot filling，**business 分组键改为意图分组键**）、ADR-0079（capability 自述）、ADR-0089（判断题闭环）、ADR-0081（结构化动作）、ADR-0073/0080（交互场景 / 知识点聚焦）

## 1. 背景

ADR-0097 落地后拓扑为 5 个 subagent：capability / tasks / question / students / tutor。随后做了一轮
主流框架调研（`docs/research/subagent-frameworks.md`：Genkit / Pydantic AI / LangChain），
结论是本项目的拆分没拿到框架列为核心收益的上下文隔离（`agent_core/subagent.py` 全量共享
对话历史），只买到指令分化、路由精度与 `requires_tool_data` 闸门；而官方示例一律
「1 编排 + 1~3 专家」，5 个已超规格。其中两个域不构成「专家」：

1. **students 只有一个工具**（`list_students`）——框架视角下这是一个工具，不是一个 agent；
   它独立存在的理由是路由边界（防 tasks 学情词表抢走纯人群问题），该理由可由 triggers
   归属表达，不需要一个 agent 实例。
2. **capability 零工具零 LLM**——它是路由层的一条固定回复分支，不是执行体。

同时 question 与 tasks 的同构性被低估：两者都是 tool loop + `requires_tool_data=True`，
system prompt 共享大半规则（「只依据工具数据」「list_students 拿 id」「不要只反问」），
question 的 prompt 甚至已经在引用不归它管的 `list_students`（`question/agent.py:46-47`，
ADR-0097 后该工具在 students 域，是一处指向不存在工具的悬空指令）。

用户决策：执行体收敛为 2 个——**tutor（独立引擎）+ tasks（吸收 question）**；
capability 定位为路由层固定回复（保留零 LLM 实现，不计入执行体）。

## 2. 决策

### 2.1 目标拓扑

| 层 | 键 | 形态 | 工具 |
| --- | --- | --- | --- |
| 路由层固定回复 | `capability` | 零 LLM subagent（清单从 manifests 生成） | 0 |
| 执行体 | `tasks` | tool loop，`requires_tool_data=True` | 12（学情读 7 + 名单 1 + 草稿写 1 + 出题 1 + 题库 3） |
| 执行体 | `tutor` | TutorService 独立引擎（安全闸门 + RAG + persona） | 0 |

`question` 与 `students` 两个 business 键消失。**tutor 不合并**：它是另一套执行引擎
（双层安全闸门包在服务外、RAG 在引擎内、零工具答题），`requires_tool_data=False` 与
tasks 的 `True` 是机械互斥的布尔，单 agent 无法同时表达（详见 §2.5 被否方案）。

### 2.2 域合并：students → tasks → 含 question

三波合并，每波独立可验证：

1. **students → tasks**：`list_students` 工具与名单 triggers 并入 tasks（priority 10 的域
   消失）。tasks 的 hints 仍不收「学生」类泛词，纯人群问题由 triggers 精确短语接住。
2. **question → tasks**：4 个工具（generate_questions 流式 / list_bank_questions /
   archive_questions / delete_questions）并入 tasks/tools/；出题支撑模块
   （specs / pipeline / translate / parsers）移入 `tasks/generation/` 子包，与学情工具
   在目录层可分；`question_sop.md` 成为 tasks 的 skills；`task_generate` 动作键移入
   tasks manifest。
3. **system prompt 合并去重**：两套规则取并集并删重复项（「只依据工具数据」「昵称直接查
   明细」原是两份），出题规则（收尾话术据计数、题库两步模式）与学情规则（一次问题只调
   必要工具）同 prompt 共存。

### 2.3 slot filling 改按意图分组（本 ADR 最实质的机制变更）

ADR-0095 的预检按 `business` 分组存槽（`conversation.slots[business]`）、按 business 的
`input_schema` 决定阻塞、并硬编码 `business == "question"` 注入 specs。question 并入后
business 只剩一个，但两套槽位语义不同（出题要 subject/grade/qtype 必填并产 specs；学情
全 optional 不阻塞），**不能合成一个 schema**（必填槽会把「今天有什么作业」也拽进澄清）。

方案：manifest 新增 `intent_schemas`，按子意图声明「触发词子集 + 槽位 schema」：

```python
"intent_schemas": {
    "generate": {
        "triggers": ["出题", "出几道", ...],   # 出题触发词子集（⊆ 顶层 triggers）
        "schema": [subject/grade/qtype required, ...],
    },
},
```

- 路由器 `_rule_match` 返回**命中的触发词**（不再只返回 business）；`RouteDecision` 增
  `trigger` 字段。纯确定性，不加 LLM 路由。
- service 预检按「business + 命中词落哪个 intent」选 schema；槽位存储键从 `business`
  改为 `business`（默认意图）/ `business:intent`（子意图），两本账互不冲。
- specs 注入条件从 `business == "question"` 改为 `intent == "generate"`，汇总帧
  （「已确认规格」）与跨轮槽位记忆行为不变。
- 契约测试守护：`intent_schemas[*].triggers ⊆ MANIFEST["triggers"]`（防声明了子集却
  路由不中的漂移）。

### 2.4 派生影响

- **capability 清单自动跟随**：manifest 从 5 变 3，清单少了两条、tasks 条目描述改为
  双域表述；学生端清单不再出现题库管理（工具层本就拒绝，话术终于对齐）。
- **kind 审计变粗**：`Conversation.kind` 的取值从 5 种收敛为 3 种（出题会话的历史
  `question` 行保留原值，前端 `runKindLabel` 保留历史映射）。这是用户确认接受的代价：
  轨迹页按 kind 的维度从「业务」退化为「执行体」。
- **`POST /tasks/generate`**：`generate_task_stream` 显式传的 `business="question"`
  改为 `"tasks"`（端点行为不变，仍走 specs 结构化路径）。
- **`app/ai/__init__.py` 公共导出不变**：`generate_question` / `QuestionSchema` 改从
  `tasks.generation` 再导出，外部 import 面零迁移。

## 3. 被否方案

| 方案 | 否决理由 |
| --- | --- |
| 单 agent（tutor 也并入） | `requires_tool_data` 布尔互斥（True 则零工具答疑硬失败 / False 则真机编造事故重开）；tutor 双层安全闸门拆成工具后从「必然执行」退化为「模型自觉」；三套 SOP 同 prompt 互渗（出题给完整解 vs 答疑启发不给答案） |
| question 保持独立 business、仅共用 agent 类 | manifest 不减少，reader-load 零收益；slot filling 的 business 分组仍要两本账 |
| 合并后出题槽位并入 tasks 全 optional schema | 「出 2 道数学题」不再确定性澄清，缺年级/题型时靠模型转问，多轮槽位记忆丢失（ADR-0095 建制的初衷就是消灭这个不确定性） |
| capability 从 subagent 搬进 service 层 | 要在 service 复刻 rt.run 的 SSE 帧序列（run_started / 双 thinking / done）与落库路径，等价性风险大于收益；其零 LLM 形态本就是「路由层固定回复」的实质 |

## 4. 后果

- 执行体 5→2，manifest 5→3；工具总数 12→12（无增减，只归置）。
- 每轮下发的工具 schema 从「最少 1 个（students 轮）」变为「tasks 轮恒 12 个」——
  小模型部署（家长手动 ModelConfig，常为本机模型）下面临更大的选型噪声，这是本次
  合并的主要运行时风险，靠 prompt 去重（规则并集）与契约测试兜住。
- 后续若对接第二个异质业务（calendar / email 式），从 2 执行体向外扩比从 1 个稀释的
  大 prompt 向外扩容易；框架拆分信号（多异质领域、子 agent 不直接对话）届时才成立。
