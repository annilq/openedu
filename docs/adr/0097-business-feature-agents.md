# ADR-0097 业务 agent 化：按能力域重组 subagent，业务 tool 管 CRUD

- 状态：已实现
- 日期：2026-10-16
- 关联：ADR-0033（工具出参按角色剥答案 / 结论必须有据）、ADR-0024（出题子代理，**执行模型被本 ADR 改变**）、ADR-0081（结构化动作）、ADR-0087（guide 写意图引导，**被本 ADR 删除**）、ADR-0079（capability 自述，**清单改生成**）、ADR-0095（slot filling，business 分组键不变）、ADR-0042（卡片契约）、ADR-0043（推理与正文分流）

## 1. 背景

AI 子代理一直按**能力类型**划分：`query`（只读查询）兜住 5 个业务域的 8 个工具、`question`
（AI 出题，约束解码）、`tutor`（伴学答疑）、`guide`（写意图引导）、`capability`（能力自述）。
这个切法在能力只有「查」时够用，四个后果随功能增长显现：

1. **query 一个 agent 兜 5 个域**：handler 各自 import `app.features.{tasks,review,questions,
   mastery,students}.service`——域边界在工具层是清的，在 agent 层是糊的，新增能力往
   `query/tools/` 一挂了事。
2. **上下文按最贵情况付费**：8 个工具 schema 每轮随请求下发，实测 3934 字符 ≈ 2000 token，
   学生问「今天有什么作业」也付全额，guide / capability 这些零 LLM 轮次的白请求也带着。
3. **能力知识四处手抄**：manifest 声明（只被路由器消费）、各 agent system prompt、
   capability 两份固定清单、前端空态文案——互不生成，必然漂移（实例：guide 的话术承诺
   「负责出题」但交付的是「请自己去表单出题」）。
4. **写意图没有执行出口**：guide（priority 20）拦下「创建一个任务」后只能给固定话术，而
   tasks feature 的 15 个写端点（from-bank / from-generated / confirm / assign…）早已存在。

用户诉求：subagent 按业务 feature 划分；去掉 query agent，功能移入对应业务 agent；业务 agent
的 tool 负责执行 CRUD。

## 2. 决策

### 2.1 新拓扑：三个业务域 agent + 两个保留

| business | 域 | 工具 | 执行模型 |
| --- | --- | --- | --- |
| `tasks` | 任务学情域（tasks + review + mastery + progress） | 读 6 + 写 1（create_draft） | tool loop |
| `questions` | 题库域（questions） | 读 1 + 写 4 + generate_questions | tool loop |
| `students` | 人群域（students） | 读 1 | tool loop |
| `capability` | 能力自述 | 无（清单从 manifest 生成） | 零 LLM |
| `tutor` | 伴学答疑 | 无（TutorService 流式） | 服务流式 |

`query` 解散、`guide` 删除。粒度取「助手能力域粗切」而非按 `app/features/` 一级目录细切：
后者会得到 9-10 个 agent，triggers 子串匹配竞争加剧，且「小明最近怎么样」这类跨域聚合问题
（错题 + 掌握度）无处路由。域内工具共享 `LOCATOR_PROPS`（student_id / student_name 定位），
与工具层现状一致。

### 2.2 出题降级为流式 tool（含 agent_core 扩展）

用户明确选择「AI 出题与题库 CRUD 合并为一个 agent，出题降级成 tool」——顾问曾建议分开
（约束解码 `run()` 与 tool loop 在 `run_with_tools` 里互斥：tools 非空走 tool loop，为空才转
`run()`），判断依据是流式体验与 slot filling 交接会受损。本 ADR 接受合并方向，用
**agent_core 流式 tool result 扩展**把代价兜住：

```python
class ToolOutcome:            # 哨兵：流式 handler 的末帧，data 即回灌 content
    def __init__(self, data): ...

ToolSpec.stream_handler       # 可选：async generator，逐帧 yield 中间帧，
                              # 最后 yield ToolOutcome(...)
```

`run_with_tools` 见到 `stream_handler` 走流式分支：中间帧（THINKING / DATA / STEP）原样
yield 给前端，收到 `ToolOutcome` 后进入既有的 `tool_result` + 回灌 + `render_tool_result`
路径。约束：

- **流式 handler 不得产出 `ASSISTANT_MESSAGE`**——收尾话术由 tool loop 第二轮模型生成，
  否则与 loop 的收尾轮职责重叠。
- 流式分支同样受 `max_turns` 与两类硬失败（TOOL_UNSUPPORTED / PROVIDER_ERROR）约束。
- 扩展是 **opt-in**：存量同步工具与测试零影响。

`generate_questions` 的 stream_handler 内部搬移 `question/pipeline.py`（build_question_prompts
+ stream_question + translate_stream + 安全闸门 + 题卡帧）。slot filling 的 specs 从
`ctx.extra["specs"]` **直达 handler**（预检层对 `business == "question"` 完整轮注入，ADR-0095
现状不变）——比原来 `run()` 读 specs 少一次模型传话，反而更可靠。`business` 键保持
`question`：契约测试的动作归属（`task_generate` → question）、slot filling 分组键、历史会话
`kind` 字段全部不变，改动面压到最小。

### 2.3 写操作：AI 起草 + 确认卡，确认走 REST

`tasks.create_draft` 调 `tasks_service` 的 from-bank 路径建**草稿任务**（draft 态，不派发）。
`render_tool_result` 发 `task_draft_card` DATA 帧（`{task_id, title, subject, grade,
question_count, students}`），前端「确认发布 / 取消」按钮**直接调现有**
`POST /tasks/{id}/confirm` 与 `/assign`——不新造 AI 确认机制，发布决定权与任务页按钮同权。
这守住 ADR-0087 当初的产品立场（「发布任务要由你亲自定题并确认发布」）：AI 的代劳止于起草。

guide 删除后，写意图 triggers（「创建任务 / 布置作业」类完整短语）移入 `tasks`
（priority 14，接住 guide 原来的拦截位）；「出题」归 `questions`（12）。

### 2.4 优先级表与角色可见性

`classify` 按 priority 降序查 triggers：`capability` 16 > `tasks` 14 > `questions` 12 >
`students` 10 > `tutor` -10（兜底）。竞争样例：「出几道任务题目」含 question triggers 且
tasks 未含「出题」→ questions；「我有哪些任务」→ tasks；「创建任务」→ tasks（guide 词表
迁入）。

`requires_tool_data=True` 继承给两个业务 agent（结论必须有据，ADR-0033）；元问题
（「你能做什么」）由 capability 在路由层接走。**学生端只读**：写工具 handler 内部按
`caller_role` 拒绝（`list_bank_questions` 已有先例），越权防护与 REST 同源（service 层
`core.guard`）。

### 2.5 capability 清单从 manifest 生成

`capability_catalog(role)` 改为遍历 `runtime.manifests`：按 role 过滤可见 business，取
`name` + `description` + 工具名列表。边界文案随 CRUD 开放重写：「我可以帮你起草任务与题目；
发布前会请你确认」。能力知识的第二份手抄（固定清单）消除，只剩 manifest 一处。

## 3. Considered Options

| 选项 | 收益 | 代价（否决 / 采纳理由） |
| --- | --- | --- |
| 维持 query 单 agent，只把写工具加进去 | 改动最小 | 拒绝：正是要消除的「按能力类型划分」；上下文与手抄问题照旧 |
| 按 `app/features/` 一级目录细切 5+ agent | 每个 agent 工具最少 | 拒绝：9-10 个 agent 的 triggers 竞争不可控，聚合问题无处路由；新人要在十多个文件夹间找 |
| 出题与题库分两个 agent（question 保持约束解码） | 执行模型不冲突，slot filling 零改动 | 拒绝（用户拍板合并）：两个名字相近的 agent 语义分叉，违背「一个域一个 agent」的心智模型；流式体验损失用 agent_core 扩展兜住 |
| LLM 兜底路由替代规则路由 | paraphrase 不漏 | 拒绝：儿童产品要确定性路由（ADR-0033 同款理由），且本次不动路由机制本身 |
| 确认卡走新 AI 动作键（task_confirm 直配） | 链路全在 AI 内 | 拒绝：REST 确认/派发已存在且带归属校验，复用它比新造机制少一套要维护的语义 |

## 4. 后果

**收益**：

- 上下文按域付费：tasks 轮只带任务域 schema，questions 轮只带题库域（各域 schema 实测数记入
  INDEX.md）。
- 能力知识收敛为「manifest + tool schema」双源且 tool schema 对 LLM 可见——「让 agent 知道
  自己有哪些能力」从手抄变为生成。
- 写意图闭环：「创建任务」→ 追问 → 建草稿 → 确认卡 → REST 发布，guide 固定话术的体验缺口消除。
- guide / query 两个目录删除，agent 总数 5 个（原 7 个）。

**代价**：

- `agent_core` 增加流式 tool 分支（`ToolOutcome` 哨兵 + `stream_handler`），内核多一条要维护
  的路径——用 opt-in 与「不得产出 ASSISTANT_MESSAGE」契约控制爆炸半径。
- `question` business 的语义从「出题助手」扩大为「题库与出题助手」，manifest name 与目录名
  （仍叫 question/）不再字面对应——用 SPEC §Implementation Decisions 明示这个不对称。
- 纯文本路由回归表重写：新优先级下「任务题目」「创建任务」等历史样例的归属变化，由契约测试
  逐条钉死。
- 题库写操作（delete / archive）经 AI 执行，误删风险靠「起草-确认」模式缓解（delete 也走
  确认卡），但比纯 REST 多一层模型误判面——handler 内 `caller_role` + service 层 guard 双闸。

**历史数据**：`Conversation.kind` 为 `query` 的旧会话回放不依赖 business，不受影响；
`Conversation.slots` 里的 `query` 分组键成为死键，无害（新 agent 不读）。
