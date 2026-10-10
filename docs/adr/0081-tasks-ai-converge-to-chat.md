# ADR-0081 tasks 出题/换一题收敛到 `/assistant/chat` 结构化动作

- 状态：已采纳（待实现）
- 日期：2026-10-10
- 关联：ADR-0034（结构化出题端点 `/tasks/generate`）、ADR-0056（审阅闸门）、ADR-0057（停止生成）、ADR-0060 D4（weak_examples 反馈边）、ADR-0055 §10/§13（RAG 与溯源）、ADR-0048（会话历史）、ADR-0072（判定闭环）、ADR-0033（工具循环与角色裁剪，§2.8 覆盖其决策 8/9）、ADR-0008（契约测试兜底纪律，§2.8 同步反转其断言）、ADR-0082（题目 owner 维度与学生题库，§2.2 学生出题的落点）
- **Supersede**：本 ADR §2.2 显式覆盖 ADR-0026 的「非伴学生成在组织上不可达」（学生可出题）；§2.8 显式覆盖 ADR-0033 决策 8/9 的**服务端按角色裁剪**（改为一律全量下发，客户端控显）。其余部分不动。

## 1. 背景（Context）

「AI 走单一入口」此前只是**口号**：`/assistant/chat` 之外，tasks 域还有四条 AI 链路。读码核实（非凭记忆）：

| # | 入口 | 编排位置 | 走 `AgentRuntime`？ | RAG / Persona / 溯源 | 落库 | 前端在用 |
|---|---|---|---|---|---|---|
| 1 | `POST /tasks/generate` | `tasks/service.py:1513` | ✅ `rt.run(business="question")`，但**绕过 `rt.decide`** | ✅ 全有 | ❌ 两步法 | ✅ |
| 2 | `…/questions/{tq}/regenerate-stream` | `tasks/service.py:1060` | ❌ 直连 `question.pipeline.stream_question` | ❌ **全无** | ✅ `_swap_question` | ✅ |
| 3 | `…/questions/{tq}/regenerate`（同步） | `tasks/service.py:1045` | ❌ 同上，推理文本被 drain | ❌ | ✅ | ❌ 无调用方 |
| 4 | `POST /tasks/{id}/regenerate`（整卷，同步） | `tasks/service.py:1161` | ❌ 同上 ×N | ❌ | ✅ | ❌ 无调用方 |

**真正的缺陷不是 URL 分散，是编排分裂**：#2/#3/#4 绕过 runtime，因此拿不到资料库 RAG（ADR-0055）、学科 Persona、`question_sop`、`source_refs` 溯源、`weak_examples` 反馈边（ADR-0060）与 TOOL 信封——**「换一题」出的题客观劣于首次出题**，且与教师上传的资料完全脱节。这是用户可见的质量问题，不是代码摆放问题。

三条支撑事实：

- 前端早把 #1 当助手的一部分：`streamGenerate` 写在 `assistant_api_client.dart:71` 的 extension 上，与 `streamChat` 共用 `_streamSse`（line 27）；URL 挂 `/tasks` 只是历史包袱。
- 超时不构成分拆理由：两条路都走 `streamPost` 的 `_streamReceiveTimeout = 10min`（`dio_network_service.dart:178`）。#2 当初「长超时」的论据对 chat 同样成立。
- #3/#4 无前端调用方，各是一次同步 LLM 调用（>30s），是纯隐患面。

## 2. 决策（Decision）

### 2.1 物理单入口：`/assistant/chat` 增加结构化动作通道

`AssistantChatReq`（`assistant/schemas.py:56`）新增两个**互斥**可选字段，而非一个带判别式的 god-object：

```python
task_generate: TaskGenerateAction | None = None            # 结构化出题（不落库）
task_question_regenerate: TaskQuestionRegenerateAction | None = None  # 换一题（服务端落库）
```

- `TaskGenerateAction`：`specs` / `student_id` / `weak_example_ids`（原 `TaskGenerateReq` 整体迁入，`tasks/schemas.py:57`）。
- `TaskQuestionRegenerateAction`：`task_id` / `task_question_id`。
- 校验器：二者至多一个非空，否则 422；**二者都为空即普通对话，行为完全不变**。

删除 `POST /tasks/generate` 与 `POST /tasks/{id}/questions/{tq}/regenerate-stream`；保留两个同步端点（#3/#4）**原样不动**，但标注为 dead code：不再新增能力，新增能力只加在 chat 通道（避免同一件事两条路各自演进）。

### 2.2 学生可出题：**放行；写类动作靠归属校验兜底；题卡不做角色裁剪**

**本条 supersede ADR-0026 的「非伴学生成在组织上不可达」。** ADR-0026 由儿童意图收敛得出该结论，其守护测试为 `test_decide_student_question_forced_to_tutor`（`tests/ai/test_agent_runtime.py:79`，学生「帮我出几道数学题」→ `tutor`）。学生自主练习是合理诉求，故显式覆盖该条而非静默绕过——按项目纪律（矛盾 ADR 需显式提出），同步改动清单如下：

1. **`question.roles` 增列 `"student"`**（`question/manifest.py:16`）。不加的话只有结构化 action 能出题，而学生自由文本说「出几道题」仍被重定向到 `tutor`——同一件事两条路两种结果，是最难排查的那类割裂。
2. **题卡一律带 `answer` / `explanation`，学生端与教师端字节一致**（见 §2.8）。不像初稿那样按角色剥离。
3. **改 `test_agent_runtime.py:79` 那条守护**，并补「学生出题帧与教师端同源、字段集一致」的断言。

**不做角色门禁**，但 `task_question_regenerate` 天然仍是教师域——这不是角色门禁，是**归属校验**：它写的是教师草稿的 `TaskQuestion` 行，`_owned_task`（`tasks/service.py:757`）经 `core.guard.require_owned` 判定，归属不符一律报 404「任务不存在」（越权伪装成不存在，既有对外契约）。学生传任何 `task_id` 都只会拿到 404，无需额外判角色。

**学生出题的落点**：不建 `Task`——学生端没有 `/tasks/from-generated` 权限（该端点 `CurrentTeacher`），也不走教师的两步审阅法。但题**不是用完即弃**：ADR-0082 给 `Question` 加了归属列 `owner_id`，学生出的题直接落成 `Question` 行（`owner_id` 为该学生），从而接上错题本、掌握度与复习调度。`task_generate` 对学生的语义就是「给我出几道题练练」——不成卷、不派发，但**会沉淀**。

### 2.3 路由：动作类**仍走** `rt.decide`，以结构化信号命中 manifest 声明的 `actions`

> ⚠️ **本节已反转（2026-10-10，用户拍板「所有服务都走意图路由」）**。
> 原决策为「有 action 时不调 `rt.decide`，直接构造 `RouteDecision(business="question")`」。
> **原决策的动机经实测成立**（结构化规格让规则词去猜必然误判：实跑 `agent_core.router.classify`，
> `出 3 道四年级下学期数学题，知识点：轴对称` → `tutor`；`""` → `tutor`；`换一题` → `tutor`），
> 但**解法**从「绕过路由」改为「扩展路由输入」——绕过路由会让裁决点继续分裂
> （现状已是 1 个真路由 + 4 处旁路：`assistant/service.py:393/466/485`、`tasks/service.py:1590`）。

有 action 时**照常调 `rt.decide`**，但入参从「一段文本」升级为**结构化意图信号**
（`IntentSignal(text, action, context)`）：`action` 与各 manifest 新增的 `actions` 字段**等值**匹配，
命中即路由，**置于 `triggers` 文本匹配之前且不参与 `priority` 排序**。

- 动作→业务的映射**声明在 manifest**（`question/manifest.py` 加
  `actions: ["task_generate", "task_question_regenerate"]`），不在 `chat()` 里写 `if`。
- 动作命中但业务对当前角色不可见 → 返回显式 not-visible（端点转 403），
  **不得**沿用 `runtime.py:90-91` 的 `visible[0]` 静默改写（那会把越权变成答非所问）。
- 未知 action → 落回文本路由，不报错。

收益不是「路由更准」，而是**裁决点归一**：安全闸门、角色可见性、name 解析、将来的配额与观测
只在 `decide` 一处生效；顺带补上 `tasks/service.py:1532` `safety=None` 导致学生出题不设防的缺口；
且动作通道不参与优先级比较，终结 `guide`(20) 压 `query`(12) 压 `tutor`(-10) 这类军备竞赛。

实施细节、分批与验收见任务文档
[`docs/refactor/2026-10-10-ai-intent-routing-unification.md`](../refactor/2026-10-10-ai-intent-routing-unification.md)，
其 **P0 是本节的前置**（先有动作通道，action 字段才有落点）。

### 2.4 消息：服务端按 action 合成 canonical message（唯一事实源）

`AssistantChatReq.message` 是 `min_length=1`（`schemas.py:59`），而结构化出题没有自然语言（现状 `generate_task_stream` 里 `message=""`，`tasks/service.py:1574`）。

- **由服务端合成**，不由前端拼：前端各拼一套必然漂移，且规格的唯一权威解释在服务端。
- 合成文案即落库的首条 user 消息 → 会话 title 由它截断而来（ADR-0048），历史列表里读得懂（例：「按规格出题：数学 4 年级 · 轴对称 · 选择题 ×3」「换一题：数学 4 年级 · 轴对称（草稿）」）。
- router 的空消息校验在 action 非空时跳过。

这一个决定同时解决了「必填校验」「title 可读性」「会话混入后可辨识」三件事——也是「照常落会话」能成立的前提。

### 2.5 会话：照常落，但用 `ref_task_id` + `origin` 留下判别痕迹

- 动作类会话照常建 `Conversation` / `Message`（与对话无差别），`kind` 仍取 business。
- **复用既有 dormant 列 `Conversation.ref_task_id`**（`conversation.py:26`，当前只在删任务时被置空，`questions/repository.py:174`，从无写入方）：换一题写 `task_id`，出题在第二步 `/tasks/from-generated` 落库后由前端回传 `session_id` 回填。不新增列就有了「这段会话对应哪个任务」的可追溯性。
- **新增 `origin` 列（`chat` 默认 / `action`）**，启动期幂等 DDL（同 ADR-0053 迁移纪律）。本轮**不在列表/回放契约里暴露它**（不加进 `AssistantConversationResp`，故前端契约零变更），只为将来「历史里筛掉出题会话」留数据口。

### 2.6 落库：维持两条动作各自的现状语义

- `task_generate`：**不落库**，DATA 题卡由前端收齐后走 `/tasks/from-generated`（ADR-0056 审阅闸门、两步法不变）。
- `task_question_regenerate`：**服务端落库**，沿用 `_swap_question`（`tasks/service.py:980`），校验沿用 `_regenerate_one_inputs`（归属 + draft 态 + 引擎解析），`scene_spec` 融合（ADR-0061 §M）留在服务端——前端拿不到也不该拿这部分。

**依赖方向**：动作的业务校验与落库留在 `tasks/service.py`，`assistant/service.py` 只做「解析 action → 调 tasks 服务 → 把结果包成帧」。chat 编排层不写 tasks 的 ORM。

### 2.7 前端：换 URL，不换解析器

`AssistantApiClient` 的 extension 改为构造带 action 的 `AssistantChatReq` 走 `streamChat`；SSE 分帧器（`_streamSse`）与 `AssistantEvent` 本就共用，无需新解析器。

需回归的两处 fold：

- 出题页 `QuestionGenFold`（`home_notifier.dart:204`）：现在会多收 `USER_MESSAGE` 与两条 routing `THINKING`（runtime 产出，`runtime.py:116-119`），须确认被忽略而不打断 live 态。
- 草稿审核页（换一题，`teacher_task_review_notifier.dart:120`）：帧从「裸 pipeline」升级为「subagent 帧」——新增 `TOOL_CALL`/`TOOL_RESULT`（携带 `requested/failed` 计数）与不同的 STEP label，`stream_reasoning_panel` 共用 seam 需一并回归。

### 2.8 答案可见性：服务端一律全量下发，唯一裁定点在客户端

**本条 supersede ADR-0033 决策 8/9 的「服务端按角色裁剪」。** 用户拍板：学生端与教师端**返回完全一致**的载荷，由客户端按角色决定答案是否渲染。

原机制：`project_for_role`（`query/tools/_shared.py:215`）在学生角色下递归剥掉 `ANSWER_FIELDS = {answer, explanation}`（`_shared.py:27`），且由契约测试兜底「新增工具忘记裁剪会被拦下」（ADR-0008 纪律）。改后：

- **服务端不再按角色投影**，题卡与工具出参一律全量。
- **客户端（Flutter）按角色决定答案区是否渲染**——教师端照常显示，学生端默认折叠/隐藏，需要时（如「看解析」）由交互触发。
- 帧结构一致带来一个直接好处：学生端与教师端**共用同一套题卡解析与卡片组件**，不需要为「少两个字段」维护一条分支。

**同步改动清单（不做会在实现时撞成回归失败）**：

| 位置 | 现状 | 改为 |
|---|---|---|
| `query/tools/_shared.py:215` `project_for_role` | 学生角色剥 `ANSWER_FIELDS` | 全量透传（保留函数签名与调用点，内部不再裁剪，便于将来单点回退） |
| `tasks/service.py:331` 注释 | 「由 `project_for_role` 统一裁剪（ADR-0033 决策 9）」 | 改为指向本 ADR §2.8 |
| `tests/ai/test_query_tools_contract.py:275` | 断言学生视角**不含** `ANSWER_FIELDS` | 反转为断言学生视角**与教师端字段集一致**（含 `answer`/`explanation`） |
| `tests/ai/test_query_tools_contract.py:279` | 「教师对照组看得到答案」 | 保留，但语义从「对照」变为「学生/教师一致」的一侧 |
| `tests/ai/test_query_tools_contract.py:293` `test_project_for_role_strips_nested_answer_fields` | 单测剥字段行为 | 改为断言不再裁剪 |

**边界：流程性剥离保留，不在本条范围内。** `assistant/service.py:277-281` 在判断题出题时把 `answer`/`explanation`/`reasoning` 清空、正确答案存入 `pending_quiz`——这是**答题流程**需要（先给题、答完再揭示，答案要留给 LLM 判定用），教师端走同一路径同样被剥，与角色无关。不要把它和角色裁剪一并删掉。

**⚠️ 代价（必须知道）：客户端控显不是安全边界。** 答案随 SSE 帧落到客户端进程，抓包、改客户端或调接口都能拿到。UI 遮挡防的是「无意瞥见」，防不住「主动取用」。本轮接受此代价（教学场景，非保密数据）；若将来出现需要真正保密的载荷，正确做法是在服务端按**权限**（而非这里讨论的角色）裁剪，并把该字段从帧里彻底移除——而不是靠客户端不渲染。

**附带收益**：取消裁剪后，答案也回到了 `TOOL_RESULT` 进 history 的内容里，模型在学生答疑时能看到正确答案——学生问「我错的那道题怎么做」时，讲解可以基于真实答案而非模型自行推测。

### 2.9 建议（非强制）：换一题按 task 复用同一 session_id

前端按 task 维度缓存一个「出题会话 id」并在换一题时回传，历史列表里一个草稿只留一行，而不是每换一题新增一行。这是 UI 侧的可选优化，不影响后端契约。

## 3. 后果（Consequences）

- **能力归一（本次最大收益）**：换一题从此拿到与首次出题完全相同的 RAG、Persona、SOP、溯源、`weak_examples` 反馈边与 TOOL 信封——教师上传的资料会真正影响重生成的题。
- AI 入口唯一：模型解析、观测、将来的配额/审计只需加在 `chat` 一处；CONTEXT.md「AI 学习助手 = 唯一 AI 入口」的措辞由口号变为事实。
- **学生自主练习成立**：学生可用结构化规格或自由文本出题，作答闭环复用 ADR-0072（判定由 LLM 产出）。副作用是教师能在会话历史里看到学生练了什么（会话 `student_id` 非空，ADR-0048 既有能力），无需新接口。
- **ADR-0026 的收敛底线被放宽**：「非伴学生成不可达」不再成立。放宽仅限出题，学生端与教师端拿到同一份载荷（§2.8）。
- **ADR-0033 决策 8/9 被覆盖**：服务端不再按角色裁剪答案，`project_for_role` 退化为全量透传。代价是答案在网络层对学生可见——**客户端控显不是安全边界**（§2.8），仅防无意瞥见；收益是学生端不再需要为「少两个字段」维护题卡分支，且模型答疑时能基于真实答案讲错题。
- **⚠️ 学生出题会检索其归属教师的资料库**：`chat` 里学生的 `teacher_id = caller.user.teacher_id`（`service.py:355-357`，非空），而 `build_retriever` 在 `(session, teacher_id)` 都非空且 `RETRIEVER_PROVIDER=vector` 时检索该教师私有资料库（`domain/retriever.py:143`），`source_refs`（资料名 + 80 字摘要，`question/agent.py:102`）会随题卡下发到学生端。**注意 `assistant/service.py:384` 的注释「学生端 teacher_id 为 None → 回落 mock」已与代码不符（stale）**，别拿它当依据。本轮**默认允许**（资料本就是该班教学素材，且溯源只是 80 字摘要）；若判定不可接受，则学生端强制传 `teacher_id=None` 走 mock。
- **代价：出题/换题会进入会话历史**（用户已确认接受）。缓解见 §2.4/§2.5：合成 title 可读、`ref_task_id` 可追溯、`origin` 为将来筛选留口。
- **代价：动作类请求把写副作用带进对话端点**——换一题会改 `TaskQuestion` 行，但气泡里只有题卡。回放无法解释「这题替换了哪道」。缓解：落库的 DATA 帧带 `task_question_id`，气泡 payload 自描述（沿用 ADR-0042 纪律）。
- 后端可单测：动作互斥校验、学生出题帧与教师端**字段集一致**（含 `answer`/`explanation`）、学生传他人 `task_id` 换一题 → 404「任务不存在」、合成 message 的内容、换一题后 `ref_task_id` 与落库一致、帧序（RUN_STARTED → USER_MESSAGE → THINKING×2 → TOOL_CALL → STEP/DATA → TOOL_RESULT → DONE）。
- 前端需新增：题卡组件的**角色分支渲染**（学生端答案区默认折叠，「看解析」交互后展开）——这是 §2.8 把裁定点移到客户端后唯一新增的 UI 责任。
- 测试迁移：`tests/api/routes/test_tasks_generate.py`、`test_task_regenerate_stream.py` 改为打 `/assistant/chat`；两个同步端点的用例保留不动。

## 4. 备选（Considered Options）

- **编排单核、端点保留**：抽出统一 `run_agent_stream`，三个 tasks 端点退化为薄壳。AI 能力同样归一、REST 资源语义更干净。否决原因：用户明确要物理单入口；且前端早已把出题当助手能力看待。
- **只迁 `generate`，regenerate 系列不动**：最小改动。否决：绕过 runtime 的能力缺失（换一题质量低于首出）不解决，而那是本次的真实缺陷。
- **动作类请求做教师门禁（403）**：本轮最初的写法。否决：学生自主练习是合理诉求，且门禁只挡住 action 挡不住自由文本（除非同时锁 `question.roles`），做一半的门禁比不做更危险。现改为 §2.2「放行 + 归属兜底」。
- **维持 ADR-0026 不动、出题仍限教师**：学生的「练一练」走已有 quiz 判断题闭环（ADR-0072），本 ADR 的动作保持教师域。改动最小、不碰安全底线。否决：学生想要的是「按规格出几道我薄弱的题」，判断题单题闭环覆盖不了。
- **保留服务端角色裁剪（`project_for_role` 不动，只让题卡全量）**：改动面最小，且守住「学生查错题看不到答案」。否决：会在同一条会话里造成新割裂——题卡带 `answer`、而 `query` 工具出的错题不带，前端要按**数据来源**而非角色写两套渲染；且 ADR-0008 的「新增工具忘记裁剪会被拦下」契约测试会持续把裁剪当作不变量钉住，与 §2.8 的原则打架。故一并反转（§2.8 清单）。
- **不加 `origin` 列**：少一次迁移。否决：历史列表无法区分「出的卷」与「问的问题」，将来要筛只能再猜一次 `kind` 字符串。
- **前端拼 message**：否决。规格的唯一权威解释在服务端，多端各拼一套必然漂移，且 title 会不一致。
