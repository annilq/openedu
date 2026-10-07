# ADR-0072：AI 学习助手推荐操作与知识点聚焦入口

状态：草案（Proposed），待评审与实施排期。

## 背景与问题

用户希望给 AI 学习助手（ADR-0036 单入口 / ADR-0047 整页 / ADR-0024 单 SSE 端点）
增加三层能力：

1. **推荐操作（suggested actions）**：点开 AI 助手时，底部出现一组「能干嘛」的快捷操作，
   提醒当前 AI 包含的能力（问答、出题、查错题、看学情等）。
2. **知识点上下文聚焦**：从 `课件 › 图形的运动（轴对称） › 讲课` 这类页面进助手时，
   传入知识点，使会话与返回的 action 都围绕该知识点（举例、出题、讲解）。
3. **出题-判断-引导闭环**：点「出一道题」→ AI 随机出当前知识点判断题（如「平行四边形是
   轴对称图形，对吗？」）→ 用户 yes/no → 结构化判定 + 答错积极引导 → 要讲解时下发
   `interactive_scene` 或文字。

### 现状事实核查（读代码确认，非推断）

- **上下文通道已存在**：前端 `AssistantCoursewareContext`（ADR-0067 §3.6）经
  `AssistantChatReq.courseware` 透传到后端；后端 `CoursewareContext`（`schemas.py:19`）
  已含 `knowledge_point`（**name 串**）、`subject`、`grade`、`semester`、`courseware_id`、
  `section_id`。**但无 `knowledge_point_id`**——用户说的「知识点 id」当前并不在协议中。
- **后端已消费 courseware**：`service.chat`（`service.py:86`）把 courseware 透传给 SubAgent，
  并按 `courseware_practice` 路由（出题→`guide`、答错提示→`tutor`）。
- **已有同类入口但语义不同**：`SectionPractice`（`courseware/.../section_practice.dart`）
  是 *教师带队* 的课堂练习（教师点「对/错」、按 `hint_level` 给分级提示），**不建任务、
  不记录作答**，且用 `knowledgePoint: kpName`（name 串）。本 ADR 要的是 *学习者自主*、
  *AI 自动判定* 的浮层入口，与之互补而非重复。
- **`actions` 语义是导航跳转**：`AssistantCardAction`（`assistant_card.dart:143`）的
  `target` 是 `ShellDestination.fromTarget` 的受控枚举（`teacher_create_task` 等），
  **不是「在会话里发 prompt」**。用户的推荐操作需要 *prompt 类* 语义，必须另立概念。
- **判定纪律**：项目坚持「结构化工具、不靠 LLM 自由判定」（ADR-0042/0040），且错题/出题
  已有 `grader` 与 `question` 管线（ADR-0061）。闭环判定必须确定性，复用既有能力。

### 四决策（已与用户拍板）

| # | 决策点 | 结论 |
|---|---|---|
| 1 | 推荐操作由谁生成 | **服务端按上下文从固定目录组装**（全局 + 知识点两套），不靠 LLM 即时生成 |
| 2 | action 语义 | 新增独立的 **`suggested_actions`**（prompt 类 + 导航类），与现有 `actions` 分两套 |
| 3 | 出题-判断-引导 实现 | **复用 `question` 管线 + `grader` 做结构化判定**，不新建自由对话判定 |
| 4 | 知识点上下文粒度 | 新增 **`knowledge_point_id`**（精确、无同名漂移），保留 `knowledge_point` name 兼容 |
| 5 | 课件页浮球 vs ADR-0036 单入口 | **复用同一 `AssistantLauncher`**，仅附加 `coursewareContext`（同入口的上下文变体） |
| 6 | 举例/讲解 的可交互场景 | 直接复用 ADR-0061 的 `interactive_scene` 卡（reflection 等 kind），不新造渲染通道 |

## 决策

### 1. 推荐操作 = 服务端目录组装的 `suggested_actions`

推荐操作**不走 LLM 生成**，而由后端一个固定「目录」按上下文装配：

- **全局目录**（无知识点）：问答、出几道题练练、看看孩子错题、查学习进度。
- **知识点目录**（带 `knowledge_point_id`）：举例说明轴对称图形、出一道相关题目、
  讲解这个知识点。

每条目 `{label, kind, payload}`：

- `kind='prompt'`：`payload` 是**预置的提示文本**（服务端定，如「请为『图形的运动（轴对称）』
  出一道判断题，只展示题目」），前端点击即 `notifier.send(payload, courseware: ctx)`。
- `kind='navigate'`：`payload` 是既有 `ShellDestination` 枚举（如 `teacher_question_bank`），
  点击走 `_handleCardAction` 既有落点分发。

**不污染 ADR-0042 的 `actions`**：`actions` 仍是纯导航枚举；`suggested_actions` 是会话空态的
*建议入口*，两类各司其职。目录是服务端**配置/纯函数**（Python dict 或 registry 函数），
零延迟、可控、可单测。

**落点（读端点）**：新增 `GET /assistant/suggested-actions?knowledge_point_id=...`，返回
`list[SuggestedAction]`。该端点是只读目录查询，不违反 ADR-0024（ADR-0024 约束的是 AI 会话
那条 SSE 端点，本端点是静态目录）。前端在 `_WelcomeHint` 区域渲染 chips；`knowledge_point_id`
为空时回全局目录，非空时按知识点目录（并叠加全局能力）。

### 2. 知识点上下文加 `knowledge_point_id`

- 前端 `AssistantCoursewareContext` 加 `knowledgePointId`（可空，与 `knowledgePoint` name 并存）。
- 后端 `CoursewareContext`（`schemas.py:19`）加 `knowledge_point_id: UUID | None = None`，
  其 `toJson` 仅当非空时下发。
- 后端解析优先级：`knowledge_point_id` 优先——按 id 查 `KnowledgePoint` 拿到精确
  `(subject, grade, semester, name)`，再复用 ADR-0061 的 `find_knowledge_point` /
  `resolve_scene_spec_for_question` 的精确匹配口径；id 缺失时回落现有 name 口径
  （`SectionPractice` 仍只发 name，不破坏）。
- 归属校验：查 KP 时走 `core.guard.require_owned`（ADR 分层不变量 9），不内联比对 `parent_id`。

### 3. 出题-判断-引导闭环 = 复用 question + grader 的结构化测验

闭环分两种题型的落地，均**复用既有能力、不做自由判定**：

- **选择题（多选/单选）**：`出一道相关题目` 触发 `question` 管线出当前知识点题 → 经现有
  `question` 卡（`assistant_question_card`）呈现选项 → 用户作答 → **既有 `grader` 判定**
  （已落地，无需新建）。这条路径今天就能跑，本 ADR 只把它接到「推荐操作」入口。
- **判断题（用户举例的「平行四边形是轴对称图形」）**：新增一层 *verbal true/false* 闭环，
  因为用户答案是自然语言 yes/no，不是选项点选。
  1. 推荐操作 `出一道相关题目` 发送预置 prompt → 后端用 `question` 管线生成 *判断题*
     （stem + 已知 `answer` 布尔）→ 下发题面气泡，**并把 `(conv_id, answer)` 写入
     `Conversation.pending_quiz`（JSON 列，可空）**。
  2. 用户下一条消息是 yes/no → 后端对该会话检测到 `pending_quiz` 状态 → **确定性解析**
     （是/对/yes→`True`；不是/错/no→`False`，小词典，无 LLM）→ 与已知 `answer` 比对。
  3. **答对** → 积极鼓励气泡（不泄题，强调思考过程）。
  4. **答错** → 复用 `SectionPractice` 的分级提示文案（`hint_level`：方向/条件/下一步），
     经 `tutor` 下发*支架式*引导，**不直接给答案**。
  5. 用户「我要讲解」/ 求讲解 → 下发 `interactive_scene`（ADR-0061 `reflection` kind，
     学生可拖轴自验）或 `tutor` 文字讲解。

**跨轮状态**：`pending_quiz` 存于 `Conversation`（启动期幂等 ALTER，JSON、可空、不建外键，
沿 ADR-0055/0061 纪律），保证无 `session_id` 归属校验失败另建会话时也不丢判定上下文；
用户回答后消费并清空。

### 4. 课件页浮球 = 同一 `AssistantLauncher` 的上下文变体（ADR-0036 兼容）

- `AssistantLauncher`（已有，见 `floating_assistant.dart`）**不新建第二套按钮**；
  课件信息页（`课件 › 图形的运动（轴对称） › 讲课` 所在页）复用同一个浮球组件，仅多传一个
  `coursewareContext` 参数（`AssistantCoursewareContext(coursewareId, knowledgePointId,
  knowledgePoint, subject, grade, semester)`）。
- `AssistantChatPage` 新增可选 `coursewareContext` 参数：非空时顶栏显示**知识点徽标**
  （如「图形的运动（轴对称）· 数学 4年级下」），并把该上下文作为每次 `send()` 的默认
  `courseware`，使会话聚焦该知识点、返回的推荐操作走知识点目录。
- 视为「同一入口的上下文变体」：`AssistantLauncher` 组件唯一，只改调用点传参，不新增入口类型，
  不违反 ADR-0036「每角色恰好一个 AI 入口」。

### 5. 不推翻任何既有决策

- 推荐操作目录是**只读配置**，不引入 GenUI（ADR-0042）。
- 判定复用 `grader`/`question`，不靠 LLM 自由判定（ADR-0040/0042）。
- 场景下发复用 `interactive_scene`（ADR-0061），不新造渲染通道。
- 浮球复用 `AssistantLauncher`（ADR-0036/0047）。
- 上下文透传复用 `AssistantCoursewareContext`（ADR-0067 §3.6）。

## 协议增补（线协议，前后端双登记）

### 5.1 后端 `SuggestedAction` 响应模型 + 读端点

```python
class SuggestedAction(SQLModel):
    label: str                                   # 人可读按钮文案
    kind: str                                     # 'prompt' | 'navigate'
    payload: str                                  # prompt→预置提示文本；navigate→ShellDestination 枚举

# GET /api/v1/assistant/suggested-actions?knowledge_point_id=<可选>
# 返回 list[SuggestedAction]：无 id→全局目录；有 id→知识点目录(并叠加全局能力)
```

目录为服务端纯函数：`build_suggested_actions(knowledge_point_id: UUID | None) -> list[SuggestedAction]`。

### 5.2 `CoursewareContext` 加字段

```python
class CoursewareContext(SQLModel):
    courseware_id: UUID | None = None
    section_id: str | None = None
    knowledge_point: str | None = None          # 保留：name 口径兼容（SectionPractice）
    knowledge_point_id: UUID | None = None       # 新增：精确、无同名漂移
    subject: str | None = None
    grade: int | None = None
    semester: str | None = None
```

### 5.3 `Conversation` 加 `pending_quiz`（启动期幂等 ALTER）

```python
pending_quiz: dict | None = None   # {'answer': bool, 'kp_id': str, 'question': str}
```

## 实现落点（文件级）

**后端**
- `app/features/assistant/schemas.py`：加 `SuggestedAction`、`CoursewareContext.knowledge_point_id`。
- `app/features/assistant/router.py`：加 `GET /suggested-actions`；`service.py:chat` 优先用
  `knowledge_point_id` 解析 KP、把 `pending_quiz` 判定逻辑接入对话流。
- `app/features/assistant/service.py`：新增 `build_suggested_actions`；判断题闭环的
  `pending_quiz` 写入/比对/清空（确定性 yes/no 解析 + `grader` 复用）。
- `app/features/materials/repository.py`（或 `knowledge_points`）：按 id 查 `KnowledgePoint`
  （`require_owned`）。

**前端**
- `features/assistant/domain/assistant_courseware_context.dart`：加 `knowledgePointId`。
- `features/assistant/domain/assistant_requests.dart`：`toJson` 下发 `knowledge_point_id`。
- `features/assistant/presentation/widgets/assistant_chat_page.dart`：空态渲染
  `AssistantSuggestedActions`（chips）+ 顶栏知识点徽标（coursewareContext 非空时）。
- `features/assistant/presentation/widgets/floating_assistant.dart`：`AssistantLauncher`
  加可选 `coursewareContext`，课件信息页复用同一组件。
- `features/assistant/presentation/widgets/assistant_suggested_actions.dart`（新建）：chips 组件，
  prompt 类→`send(payload, courseware: ctx)`，navigate 类→`ShellDestination.fromTarget`。

## 与既有 ADR 关系一览

| 既有 ADR | 本 ADR 关系 |
|---|---|
| ADR-0036 单入口 / ADR-0047 整页 | 复用 `AssistantLauncher` 与 `AssistantChatPage`，仅加上下文参数 |
| ADR-0024 / 0025 单 SSE 端点 + 帧契约 | 推荐操作走独立只读端点（静态目录），不新增 AI 会话端点 |
| ADR-0042 类型化卡片协议 | 新增 `suggested_actions` 概念，不污染既有 `actions` 导航枚举 |
| ADR-0061 交互式场景 | 讲解复用 `interactive_scene`（reflection），判定复用 `question`+`grader` |
| ADR-0067 §3.6 课件上下文 | 扩展 `AssistantCoursewareContext` 加 `knowledgePointId` |
| ADR-0054 写意图走 guide | 出题/讲解的预置 prompt 仍命中既有路由规则，不另立写意图通道 |

## 术语（glossary）

- **推荐操作 / suggested_actions**：会话空态下方的一组快捷入口，由服务端按上下文从固定目录
  装配；分 `prompt` 类（点击发预置提示）与 `navigate` 类（点击跳转既有页面）。
- **知识点聚焦会话 / knowledge-point-scoped session**：携带 `knowledge_point_id` 进入助手，
  使会话系统提示、推荐操作、出题范围都围绕该知识点。
- **结构化测验闭环 / structured quiz loop**：AI 出题（已知答案）→ 用户作答 → 确定性判定
  （`grader` 或 yes/no 小词典比对）→ 答错支架式引导、答对鼓励、求讲解下发场景/文字。
- **`knowledgePointId`**：知识点目录行的 UUID，比 `knowledge_point` name 串更精确、无同名漂移。
- **prompt 类动作 vs 导航类动作**：前者在会话内发送预置提示，后者跳转壳内既有页面；前者是本
  ADR 新增，后者沿用 ADR-0042 的 `ShellDestination` 枚举。

## 验证判据

- 后端：`tests/.../test_suggested_actions.py`（全局/知识点两套目录装配、id 缺失回落 name、
  `knowledge_point_id` 命中精确 KP）；`tests/.../test_quiz_loop.py`（判断题 `pending_quiz`
  写入→yes/no 确定性判定→答错引导文案不含答案→讲解答发 `interactive_scene`）；
  `ruff check app` 全清。
- 前端：`test/assistant_suggested_actions_test.dart`（chips 渲染、prompt 类发消息、navigate
  类落点、`knowledgePointId` 随 `courseware` 下发）；`test/assistant_chat_page_test.dart`
  （coursewareContext 非空→顶栏徽标 + 空态显示知识点目录）；`flutter analyze lib` 零 issue；
  分层不变量（`feature_boundaries_test`、`file_size_guard_test`）仍成立。
- 端到端：从 `课件 › 图形的运动（轴对称） › 讲课` 点浮球 → 进入聚焦会话 → 点「出一道相关题目」
  → 答「平行四边形不是轴对称」→ 判定正确鼓励；答「是」→ 引导不泄答案；点「我要讲解」
  → 出现可拖轴验证的 `reflection` 场景。

## 已知遗留 / 待办

1. 判断题闭环的 `pending_quiz` 跨请求一致性：需确认 `Conversation` 幂等 ALTER 在历史库
   （SQLite/Postgres 双分支）与 ADR-0061 §R 的「加列≠加约束」教训对齐。
2. 推荐操作目录的**角色分叉**：教师端「看看孩子错题」可落 `teacher_task_list`，学生端应改为
   「查看我的错题」（后端 `visible_businesses(role)` 已是唯一真相源，目录需按 role 过滤）。
3. 选择题出题范围聚焦：`question` 管线出当前知识点题需把 `knowledge_point_id` 解析出的
   `(subject, grade, semester, name)` 注入出题 prompt（复用 ADR-0061 的 `find_knowledge_point`
   精确口径），避免同名漂移。
4. 推荐操作在会话非空后是否常驻：本 ADR 默认仅空态显示；若产品要常驻底部条，需另议宽度/遮挡。
5. 数据来源：本章节所述交互均基于现有 `AssistantCoursewareContext` / `SectionPractice` /
   `CoursewareContext` 代码与设计意图，**未实际新增实现**；落地前以 `git status` + 上述文件为据。
