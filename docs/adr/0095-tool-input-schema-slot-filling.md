# ADR-0095 工具输入 schema 与缺槽追问

- 状态：草稿（待评审）
- 日期：2026-10-15
- 关联：ADR-0081（结构化动作）、ADR-0089（判断题闭环下沉）、ADR-0061（JSON 列 `none_as_null` 纪律）、ADR-0053（迁移纪律）；现状分析见 `docs/research/slot-filling-analysis.md` 与 `docs/research/slot-filling-mainstream.md`

## 1. 背景

上一轮核查（`docs/research/slot-filling-analysis.md`）确认：当前 AI 会话在用户缺参数时不会逐项追问。证据如下。

- `question/agent.py:389` 只有一条粗粒度兜底：连学科都抽不到才提示「请告诉我科目、年级和题型」，且不区分缺哪个槽。
- `grade` 静默默认 0（`question/agent.py:225`），`knowledge_point` 静默默认空串（`question/agent.py:259`）。
- 追问后不跨轮累积，用户必须重发整条才能继续。
- `ctx.extra["specs"]` 只在结构化 `POST /tasks/generate` 路径注入（`tasks/service.py`），助手聊天路径 100% 走自由文本分支，因此上述兜底对聊天路径无效。

用户诉求：给每一个工具（subagent 业务）定义输入 schema，用户查询缺参数时持续提醒输入。本 ADR 据此设计 schema 承载方式、缺槽循环、跨轮记忆与追问契约。

## 2. 决策

### 2.1 承载单元：每个 subagent 在 manifest 声明 input_schema

每条 `MANIFEST` 新增 `input_schema` 字段，作为槽位定义的唯一事实源。结构化 `actions`（ADR-0081 的 `manifest.actions`）复用所属业务的槽位定义，不在 action 层另写一份。schema 与现有 manifest 结构一致，路由、角色、技能仍各司其职，互不串味。

槽位定义字段：

| 字段 | 含义 |
|---|---|
| `name` | 内部字段名，与现有 spec / 上下文字段对齐（如 `subject` / `grade` / `knowledge_point`） |
| `type` | `enum` / `int` / `bool` / `string` |
| `required` | 是否阻塞追问 |
| `prompt` | 缺该槽时向用户说的话术 |
| `enum` | `type=enum` 时的可选项列表 |
| `enum_ref` | 可选项引用某常量（如 `question.SUBJECTS`），避免重复与漂移 |
| `min` / `max` | `type=int` 时的取值范围 |
| `default` | `required=False` 时的默认值 |
| `source` | 从哪抽取：`text`（自由文本）、`context`（`ctx.extra` 透传）、`both` |

### 2.2 缺槽循环：确定性预检层（引导用户输入）

在 subagent 生成前插入 `slot_filling` 预检层，不靠模型随机发挥。步骤：

1. 按 business 载入 `input_schema`，解析 `enum_ref`。
2. 从 `Conversation.slots` 读已持久化的槽位。
3. 从本轮 `message` + `ctx.extra` 抽取槽位（出题复用 `parse_specs_from_text`；其余 subagent 用轻量启发式或模型）。
4. `merge(持久化, 本轮抽取)`。
5. 校验 `required`：有缺则产出澄清帧、写回已知槽位、return（不生成）。
6. 无缺则进入生成；生成前先发一条「已确认规格」汇总（覆盖被默认填充的槽），再出 DATA 帧。

澄清帧走「普通消息 + 标记」：用一条助手消息帧承载，文本为各缺槽 `prompt` 拼接，`extra` 带 `clarify: {"missing_slots": [{"name","prompt","type","enum","min","max"}]}`。不新增 eventType（沿用 `agent_core/protocol.py:37` 的 `AssistantEvent`，业务字段走 `extra`，见 `protocol.py:55`）。

### 2.3 跨轮记忆：Conversation.slots 持久化

新增 `Conversation.slots` 列，类型 JSON（`none_as_null=True`，遵循 ADR-0061），存放按 business + intent 累积的槽位字典。追问时写回已知槽位；规格解析完成后清空或保留至会话结束。迁移为加列、幂等 DDL（ADR-0053 纪律）。

这样用户下一轮只需补说缺失项（如「三年级」），预检层合并后继续，无需重述整条。

### 2.4 追问策略：最小阻塞

只阻塞 `subject` + `grade`，出题业务再加 `qtype`。其余槽（`count` / `knowledge_point` / `difficulty` / `semester` / `multi` / `judge` / `multi_subject`）一律 `required=False`、带默认，不逐个追问，只在生成前汇总里声明被默认填充的项。`query` / `tutor` / `guide` 不阻塞（读操作与问答，过度追问反而干扰）；`capability` 无输入。

多学科组卷（用户提到的「是否需要多学科组卷」）建模为 question 的 optional 槽 `multi_subject`：自由文本出现多科目时由既有 `_subject_summary` 自动识别并分别出规格；单科目场景下不作为必问项，仅在汇总里提示「可切换多学科」。

### 2.5 各 subagent 的 input_schema（初版，铺全字段）

下列 dict 即落地时要写入各 manifest 的内容。

**question（出题助手）**

```python
"input_schema": [
    {"name": "subject", "type": "enum", "required": True,
     "prompt": "请问要出哪个科目？", "enum_ref": "question.SUBJECTS", "source": "both"},
    {"name": "grade", "type": "int", "required": True,
     "prompt": "几年级？（1-9）", "min": 1, "max": 9, "source": "both"},
    {"name": "qtype", "type": "enum", "required": True,
     "prompt": "要什么题型（选择/填空/计算/解答）？",
     "enum": ["choice", "fill", "calc", "open"], "source": "text"},
    {"name": "count", "type": "int", "required": False, "default": 1,
     "min": 1, "max": 5, "source": "text"},
    {"name": "knowledge_point", "type": "string", "required": False, "default": "",
     "prompt": "有指定的知识点吗？（可留空按教材随机）", "source": "both"},
    {"name": "difficulty", "type": "enum", "required": False, "default": "medium",
     "enum": ["easy", "medium", "hard"], "source": "text"},
    {"name": "semester", "type": "enum", "required": False, "default": "",
     "enum": ["", "上", "下"], "source": "text"},
    {"name": "multi", "type": "bool", "required": False, "default": False, "source": "text"},
    {"name": "judge", "type": "bool", "required": False, "default": False, "source": "text"},
    {"name": "multi_subject", "type": "bool", "required": False, "default": False,
     "prompt": "是否需要多学科组卷？（是则按科目分别出题）", "source": "text"},
]
```

**query（学情查询）**

```python
"input_schema": [
    {"name": "scope", "type": "enum", "required": False, "default": "tasks",
     "prompt": "想查什么？",
     "enum": ["tasks", "wrong", "review", "mastery", "bank"], "source": "text"},
    {"name": "target", "type": "string", "required": False,
     "prompt": "查哪个学生或班级？（教师端；学生端默认查自己）", "source": "context"},
    {"name": "subject", "type": "enum", "required": False,
     "enum_ref": "app.domain.subjects.SUBJECTS", "source": "both"},
    {"name": "grade", "type": "int", "required": False, "min": 1, "max": 9, "source": "both"},
    {"name": "knowledge_point", "type": "string", "required": False, "source": "both"},
    {"name": "time_range", "type": "enum", "required": False,
     "enum": ["today", "week", "month", "all"], "source": "text"},
]
```

**tutor（伴学答疑）**

```python
"input_schema": [
    {"name": "question_text", "type": "string", "required": True,
     "prompt": "你想问什么？（把问题发给我）", "source": "text"},
    {"name": "subject", "type": "enum", "required": False,
     "enum_ref": "app.domain.subjects.SUBJECTS", "source": "both"},
    {"name": "grade", "type": "int", "required": False, "min": 1, "max": 9, "source": "both"},
    {"name": "knowledge_point", "type": "string", "required": False, "source": "both"},
]
```

**guide（任务引导）**

```python
"input_schema": [
    {"name": "task_type", "type": "enum", "required": False, "default": "homework",
     "enum": ["homework", "practice", "exam"], "source": "text"},
    {"name": "subject", "type": "enum", "required": False,
     "enum_ref": "app.domain.subjects.SUBJECTS", "source": "both"},
    {"name": "grade", "type": "int", "required": False, "min": 1, "max": 9, "source": "both"},
]
```

**capability（能力自述）**

```python
"input_schema": []
```

## 3. 后果

- 用户缺参数时被逐项引导，而非收到一条笼统「请告诉我科目年级题型」后还要重发整条。
- schema 单一事实源在 manifest，前端按 `enum_ref` / `enum` 渲染选项，后端按 schema 校验，二者不再各写一套。
- 代价：新增 `Conversation.slots` 列与迁移；`assistant` 编排层在 `subagent.run` 前新增预检步；前端需识别 `extra.clarify` 渲染引导输入卡（复用现有消息流，改动量小）。
- 代价：澄清帧作为普通消息落库，历史回放里是正常气泡，不会新增不可辨识的帧类型。
- 不破坏现有：manifest 仅加新键，旧代码不读它；结构化 `POST /tasks/generate` 路径（注入 `specs` 的那条）不受影响。

## 4. 备选

- LLM 强制抽取（`request_clarification` 工具调用）：灵活但非确定，模型可能漏问或乱问。否决，改确定性预检。
- 不持久化、每条重抽：最简单但非「持续输入」。否决（用户明确要跨轮）。
- 新增 CLARIFY 事件类型：契约更清晰，但前端改动大。用户选「普通消息 + 标记」，否决新增类型。
- 全槽阻塞：收集最全但打扰多。否决，改最小阻塞。

## 5. 实施门票（tickets，按依赖）

1. schema 落地：5 个 manifest 加 `input_schema`（本 ADR 附带写入）。
2. `slot_filling` 模块：载入 / 解析 schema、`merge`、校验、澄清帧构造。
3. 持久化：`Conversation.slots` 列 + 迁移脚本 + 读写。
4. 预检接入：`assistant/service.py` 在 `subagent.run` 前调预检；question 先接，其余 subagent 跟进。
5. 前端：识别 `extra.clarify` 渲染引导输入卡；确认汇总展示。
6. 测试：缺槽追问、跨轮合并、最小阻塞边界、空消息处理。
