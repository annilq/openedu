# 业务 agent 化：按能力域重组 subagent · Spec

> 来源：ADR-0097（本轮权威决策记录，冲突以它为准）。
> **[INDEX.md](INDEX.md)**：依赖链 + 共同纪律。tickets 是垂直切片。
> 本地 `.scratch`（gh 未认证，未建 GitHub issue）。

## Problem Statement

当前 subagent 按**能力类型**划分（查询 / 出题 / 讲题 / 引导 / 自述），不按**业务域**划分。后果有四，均有实测证据：

1. **query 一个 agent 兜了 5 个业务域的 8 个只读工具**（`query/tools/registry.py:19-28`）。handler 各自 import `app.features.{tasks,review,questions,mastery,students}.service`——域边界在工具层是清的，在 agent 层是糊的。
2. **上下文按最贵情况付费**：每轮随请求下发全部 8 个工具 schema，实测 3934 字符 ≈ 2000 token（`docs/research/` 记录）。学生问「今天有什么作业」也付全额。
3. **能力知识四处手抄**：manifest 声明（只被路由器消费）、各 agent system prompt、capability 两份固定清单（`capability/agent.py:24-34`）、前端空态文案（`assistant_chat_page.dart`「可以出题、查学情、看错题」）——互不生成，必然漂移。
4. **写意图没有执行出口**：guide（priority 20）把「创建一个任务」整句拦下后只能给固定话术（`guide/agent.py` 的 `_FINISH`），而 tasks feature 的写端点（from-bank / from-generated / confirm / assign… 15 个）早已存在。AI 承诺「只负责出题」，交付的却是「请自己去表单出题」。

用户诉求：subagent 按业务 feature 划分；去掉 query agent，功能移入对应业务 agent；业务 agent 的 tool 负责执行 CRUD。

## Solution

按**助手能力域**粗切为 3 个业务 agent，与保留的 2 个零 LLM/服务型 agent 组成新拓扑：

| business | 域 | 工具 | 执行模型 |
|---|---|---|---|
| `tasks` | 任务学情域（tasks+review+mastery+progress） | 读 6（今日/我发布的/错题本/进度/待复习/掌握度）+ 写 1（create_draft，from-bank 组草稿） | tool loop |
| `questions` | 题库域（questions） | 读 1（list_bank）+ 写 4（create/update/delete/archive）+ 出题 1（generate_questions，**流式 tool**） | tool loop |
| `students` | 人群域（students） | 读 1（list_students） | tool loop |
| `capability` | 能力自述 | 无工具，**清单从 manifest 生成** | 零 LLM |
| `tutor` | 伴学答疑 | 无工具（TutorService 流式） | 服务流式 |
| ~~`query`~~ | 解散，8 工具按域迁入上述三个域 | | |
| ~~`guide`~~ | 删除，写意图 triggers 并入 `tasks` | | |

关键设计：

- **出题降级为 tool（用户拍板，违反顾问技术判断的选项）**：`question` 的约束解码 `run()` 改造成 `generate_questions` 流式 tool。为此给 `agent_core` 加**流式 tool result** 扩展：`ToolSpec.stream_handler` 返回 `AsyncIterator`，runtime 逐帧 yield（THINKING / DATA / STEP 中间帧），末帧 `ToolOutcome` 作为回灌 content。流式体验（逐 token 思考、题卡帧、STEP 进度锚点）不丢；slot filling 的 specs 经 `ctx.extra["specs"]` 直达 handler，比现在 `run()` 读 specs 少一次模型传话。契约：流式 handler 不得产出 `ASSISTANT_MESSAGE`（收尾由 tool loop 第二轮做）。
- **确认卡走 REST，不新造 AI 确认机制**：`create_draft` 的 `render_tool_result` 发 `task_draft_card` DATA 帧（草稿摘要 + task_id），前端「确认发布 / 取消」按钮直接调现有 `POST /tasks/{id}/confirm` 与 `/assign`。AI 只起草，发布决定权与任务页按钮同权。
- **guide 删除后写意图有着落**：「创建任务 / 布置作业」类 triggers 随 guide 移入 `tasks`（priority 14，接住 guide 原来的位），追问槽位 → `create_draft`（from-bank 从题库选题组草稿）→ 确认卡。「出几道题」仍归 `questions`（priority 12）。
- **优先级表**（`classify` 按 priority 降序查 triggers）：`capability` 16 > `tasks` 14 > `questions` 12 > `students` 10 > `tutor` -10。
- **`requires_tool_data=True` 继承给两个 tool-loop 业务 agent**（结论必须有据，ADR-0033）；元问题（「你能做什么」）由 capability 在路由层接走，不进 tool loop。
- **学生端只读**：写工具的 handler 内部按 `caller_role` 拒绝（`list_bank_questions` 已有先例），不给 student 角色可见。学生可用的 tasks 工具：today / progress / mastery / 错题本（剥答案）。
- **共享层安置**：`query/tools/_shared.py`（282 行，envelope / project_for_role / resolve_students / LOCATOR_PROPS 等跨域复用）迁至 `app/ai/shared/`。不进 `agent_core`（零业务依赖纪律）。

## User Stories

1. As a 教师, I want 说「我有哪些任务」时只加载任务域的工具（而不是题库/掌握度全量）, so that 响应更快、上下文更省。
2. As a 教师, I want 说「帮我创建一份四年级数学练习」时系统追问缺失参数（年级/科目/数量）, so that 不用去表单手动填。
3. As a 教师, I want AI 从我的题库选题组成**草稿**任务并在会话内给确认卡, so that 我点「确认发布」才真正派发、误操作可挽回。
4. As a 教师, I want 在会话里管理题库（新建/编辑/删除/归档题目）, so that 不用离开对话去题库页。
5. As a 教师, I want 说「出几道四年级数学题」时仍获得流式出题体验（思考逐 token、题卡、进度锚点）, so that 出题降级为 tool 不损失体验。
6. As a 学生, I want 问「今天有什么作业」只带学生可见的工具, so that 不会看到题库管理/任务派发等教师能力。
7. As a 学生, I want 尝试让 AI 改数据时被明确拒绝, so that 边界清晰而非静默失败。
8. As a 用户, I want 问「你能做什么」时拿到与真实能力一致（从 manifest 生成）的清单, so that 不会看到已删能力的过时描述。
9. As a 维护者, I want 每个工具的业务域归属在目录结构上一目了然, so that 新增能力知道该放哪个 agent。
10. As a 维护者, I want 流式 tool 扩展是 opt-in 的, so that 现有同步工具与测试不受影响。

## Implementation Decisions

- **business 键**：`tasks` / `questions` / `students` / `capability` / `tutor`。`question` 键**保留但语义扩大**为题库域——契约测试的动作归属（`task_generate` → question）、ADR-0095 slot filling 的分组键、历史会话的 `kind` 字段全部不变，把改动面压到最小。目录名 `app/ai/subagents/question/` 不改（避免 import 路径大规模翻修），manifest 的 `name` 改「题库与出题助手」。
- **流式 tool 协议**（agent_core 增量，不影响存量）：

  ```python
  class ToolOutcome:  # 哨兵：流式 handler 的末帧，data 为回灌 content
      def __init__(self, data): ...

  class ToolSpec:
      ...
      stream_handler: Callable[..., AsyncIterator[Any]] | None = None
  ```

  `run_with_tools` 见到 `stream_handler` 即走流式分支：逐帧 yield（约定仅 THINKING / DATA / STEP / TOOL_CALL 中间帧），收到 `ToolOutcome` 后按其 `data` 走既有的 `tool_result` + 回灌 + `render_tool_result` 路径。流式分支同样受 `max_turns` 与两类硬失败约束。
- **slot filling 衔接**：预检层对 `business == "question"` 完整轮写 `ctx.extra["specs"] = [merged]`（现状不变）；`generate_questions` 的 stream_handler 优先读 `ctx.extra["specs"]`（结构化规格），为空则从模型传来的 args 取。`tasks` 域新增轻量 input_schema（subject/grade/count/student_target，读操作不阻塞、写操作必填前两项）。
- **确认卡契约**：DATA 帧 `data.type = "task_draft_card"`，载荷 `{task_id, title, subject, grade, question_count, students}`。前端渲染器按 kind 分派（ADR-0042）；按钮动作走 REST，载荷不带任何 AI 会话状态。
- **capability 清单生成**：`capability_catalog(role)` 改为遍历 `runtime.manifests`，按 role 过滤后取 `name` + `description` + 工具名列表。边界文案重写：「我可以帮你起草任务与题目；发布前会请你确认」。
- **写工具的越权防护**：handler 内部先 `caller_role` 检查（学生拒），再走 `app.features.*.service`（service 层已有 `core.guard` 归属校验，与 REST 同源）。
- **目录结果**：

  ```
  app/ai/subagents/
    tasks/     agent.py manifest.py tools/{6 读 + create_draft}.py
    question/  agent.py manifest.py tools/{list_bank, create, update, delete, archive, generate_questions}.py
    students/  agent.py manifest.py tools/{list_students}.py
    capability/  (清单改生成)
    tutor/     (不动)
    shared/    (原 query/tools/_shared.py)
  ```

- **删除清单**：`query/` 整个目录（agent + render + tools）；`guide/` 整个目录。`render.py` 的卡片投影按工具名分派逻辑拆入各域 agent 的 `render_tool_result`。
- **既有测试**：`tests/ai/test_intent_routing_contract.py` 的动作归属断言不变（task_generate → question）；纯文本路由回归表（`test_agent_runtime.py`）按新优先级表重写；query 的工具单测迁入各域；新增流式 tool 的 agent_core 单测与三域 agent 测试。

## Out of Scope

- classes 域的 AI 化（建班/改班/删班维持纯 REST——重表单管理，AI 助手价值低，SPEC 边界明示）。
- 学生端写权限（answer / checkin 走作答页，不进 AI 通道）。
- LLM 兜底路由（上一轮架构评审的 B 方案，另立票）。
- 前端「修改槽位」入口在回放卡的既有行为（ADR-0095 已闭环，不动）。
