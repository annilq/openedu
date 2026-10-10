# ADR-0082 题目 owner 维度与学生题库

- 状态：已采纳（待实现）
- 日期：2026-10-10
- 关联：ADR-0004 D2/D3（题库层 / 派发快照层 / 任务层三层结构）、ADR-0081（学生可出题，本 ADR 补其**落点**）、ADR-0053（游标分页与索引）、ADR-0060（错题与复习）、ADR-0052（导出）、ADR-0055（资料库与溯源）
- **Supersede**：§2.2 收窄 `Question.teacher_id` 的语义（由「归属」降为「所属教师域」）；§2.6 修复 `tasks/service.py:1467` 的 `question_id` 类型混用。**不动** ADR-0004 的三层结构，也不动「Task / TaskQuestion 是教师域」这条底线。
- 依赖：ADR-0081 让学生能出题；本 ADR 让那些题**有地方可去**。

## 1. 背景（Context）

### 1.1 现有三层结构（ADR-0004 D2/D3，核码确认）

`Question` 表**没有 `task_id`**——`question.py:17` 注释明写「删 task_id 独立实体，可跨 Task 复用」。与 `Task` 强绑定的是 `TaskQuestion`（`task_id` 外键 + 深拷贝快照 + ready/assigned 冻结）。沉淀回库的唯一入口是 `promote_task_question`（`tasks/repository.py:184`），owner 取 `Task.teacher_id`（`:198`）——**永远是教师**。

所以「题目」与「任务」是刻意解耦的，而「归属」目前只有一种：**教师**。

### 1.2 学生与题的关系是引用，不是拥有

CONTEXT.md 定义得很清楚：题库「按教师（teacher_id）做归属隔离」（`:21`）、「仅教师可用…**不与任何学生账户关联**」（`:25`）。三道闸门焊死：

- 题库端点全部 `CurrentTeacher`（`questions/router.py:36`）
- `promote_task_question` 取 `Task.teacher_id`（`repository.py:198`）
- `/tasks/from-generated` 是 `CurrentTeacher`（`tasks/router.py:63`）

学生侧只有引用：`WrongQuestion` 唯一约束 `(student_id, question_id)`（`progress.py:42-43`），`question_id` 外键**非空**（`:49`）；`AnswerRecord.question_id` 同样外键 `question.id`（`:11`）。

### 1.3 断点：ADR-0081 让学生出题，但题没有落点

ADR-0081 §2.2 定「学生可出题自己练」，但按现有结构这些题**无处可去**：

- 学生建不了 `Task`（`from-generated` 是 `CurrentTeacher`）→ 没有 `TaskQuestion` → 走不到 `promote`
- 没有 `Question` 行 → 进不了错题本（外键非空）、进不了掌握度、驱动不了复习
- 结论：学生练完什么都没留下

这不是 ADR-0081 的疏漏，而是**归属模型里没有学生的位置**。

### 1.4 顺带挖出的既存缺陷

`tasks/service.py:1467`：

```python
record_question_id = tq.question_id or question_id
```

未 promote 的题（`question_id` 为 None）会把 **`TaskQuestion.id` 当作 `question_id`** 写进 `AnswerRecord` 与 `WrongQuestion`。后果有两层：① 外键 `question.id` 的语义被破坏（SQLite 默认不强制外键，所以写得进去）；② 掌握度按 `question_id` join `Question` 取知识点统计，这些行 join 不到题 → **统计静默漏题**。注释（`:1445-1447`）把它描述为「review 新口径」的兼容，实则是类型混用。

## 2. 决策（Decision）

### 2.1 `Question` 增加归属列 `owner_id`（单一列，无 role）

新增一列（启动期幂等 DDL，同 ADR-0053 迁移纪律）：

| 列 | 类型 | 语义 |
|---|---|---|
| `owner_id` | UUID FK `user.id` | **归属与隔离的唯一依据**（教师或学生的 user.id） |

存量回填：`owner_id = teacher_id`（现有题必然都是教师的）。

**不需要 `owner_role`。** 初稿写过「`owner_role` 区分 teacher/student」，现删掉——它是 `owner_id → User.role`（`user.py:9`）的冗余反范式化：隔离时 `owner_id == me` 已经足够，因为 owner 是「我」时其角色必然是我的角色（`User.role` 是单一值，不存在既是教师又是学生的账号）。需要区分「我学生的题」时用 `teacher_id == me AND owner_id != me` 即可（§2.3），同样不必冗余一列。

索引：新增 `ix_question_owner_created (owner_id, created_at)` 承接游标分页（ADR-0053）。

> 命名说明：本列承担的是「归属」而非「操作账户」，故用 `owner_id`；口径与 CONTEXT.md 的「账户」概念一致（教师账户 / 学生账户都是 `User`）。若偏好 `account_id` 亦可，纯改名不影响本 ADR 任何结论。

### 2.2 `teacher_id` 语义收窄为「所属教师域」，不再等于归属

`Question.teacher_id` **保留**，但语义从「归属」降为「所属教师域」：

- 教师自有的题：`teacher_id = 自己`
- 学生的题：`teacher_id = 该学生的归属教师`（`User.teacher_id` 自关联，`user.py:16`）

这么留的理由：学生的题仍需能被其归属教师管理与统计（教师看得到学生练了什么，是既有诉求——ADR-0081 §3 已提到会话层面），且 AI 工具现有的 `teacher_id` 作用域不用重写。**它不是隔离依据**——隔离只看 `owner_id`。

⚠️ 实现时最容易错的一点：教师的题库查询必须改成 `owner_id == me`，**不能沿用 `teacher_id == me`**——否则会把自己学生的题混进教师题库。

### 2.3 隔离与可见性规则（唯一事实源）

| 场景 | 过滤条件 |
|---|---|
| 教师看自己的题库 | `owner_id == me` |
| 学生看自己的题库 | `owner_id == me` |
| 教师看本域全部（含学生） | `teacher_id == me` |
| 教师**只看自己学生的题** | `teacher_id == me AND owner_id != me` |
| AI 工具（如 `list_bank_questions`） | 按 caller 身份走「自己的题库」那条 |

前两行条件**字面相同**——这正是取消 `owner_role` 后的结果：隔离只看 `owner_id`，角色由 caller 自己携带，不进数据。

⚠️ **`core.guard.require_owned` 不能直接用于 `Question` 的归属校验。** 它判的是 `obj.teacher_id != owner_id`（`guard.py:44`，属性名硬编码）。而本 ADR 下学生的题 `teacher_id` 是其**归属教师**——教师会凭此通过校验，但按 `owner_id` 那道题属于学生本人。两者语义不同：前者是「所属教师域」访问（教师看学生的题，允许），后者是「拥有者」隔离（教师不能当成自己的题）。学生题库的归属校验须另走按 `owner_id` 的判定（扩展 `guard` 或用 `find_owned` 自行判定），不要直接调 `require_owned`。

### 2.4 学生题库写入口：学生出题即入库（与 ADR-0081 联动）

ADR-0081 的 `task_generate` 在**学生**场景下，直接写 `Question` 行：

- `owner_id = student.id`
- `teacher_id = student.teacher_id`（所属教师域）
- `origin = 'ai'`（ADR-0060 的来源标记，学生题恒为 AI 生成）

与教师路径的对称性差异是刻意的：教师走两步法（先出卡 → `from-generated` 建草稿任务 → `confirm` 时 promote），因为教师要审阅成卷；**学生没有审阅环节**，出的题即刻用于自练，故一步入库，不建 `Task`。

入库后错题本、作答记录、掌握度、复习调度全部自然可用——这正是 §1.3 断点的解法。

### 2.5 学生题库视图：默认只显示「练过的」

学生每次「出几道题练练」都会产生 `Question` 行，不做约束会把学生题库淹成生成日志。

**默认过滤 `practiced`**（存在 `AnswerRecord` 引用），可切换到「全部」。没练过的题仍然存在于库中（不丢数据），只是不占主视图。这一条是 UI/查询层的默认参数，不是数据删除。

### 2.6 修复 `question_id` 类型混用（`tasks/service.py:1467`）

`record_question_id = tq.question_id or question_id` 改为：**`question_id` 为空时先 `promote_task_question` 再记录**，拿到的 `Question.id` 才是合法值。

理由：教师路径下 `confirm()` 已自动 promote 全部草稿题（`:1229-1231`），正常作答时 `question_id` 非空，这个 fallback 是历史遗留；而学生路径（§2.4）入库即有 `Question.id`，同样不需要 fallback。留着它只会持续污染外键语义并让掌握度漏题。

### 2.7 明确不动的部分

- **三层结构不动**（ADR-0004）：`Question` 仍无 `task_id`，`TaskQuestion` 仍是派发快照。
- **`Task` / `TaskQuestion` 仍是教师域**：学生不建任务、不派发、不审阅。学生有的只是「自己的题 + 自己的练习记录」。
- **导出（ADR-0052）本轮不动**：题库来源导出仍按教师题库语义；学生题库导出列为后续议题。

## 3. 后果（Consequences）

- **ADR-0081 的断点被补上**：学生出题 → 有 `Question` 行 → 错题本 / 掌握度 / 复习调度全部接通，学生练习第一次有了沉淀。
- **归属模型从「只有教师」变为「教师 | 学生」**，且隔离依据单一（`owner_id`），不靠角色 if-else 散落各处。
- **掌握度统计会更准**：§2.6 修掉混用后，原本 join 不到题的作答记录重新纳入统计——这会**改变既有统计数字**（历史上漏统计的部分补回来）。属预期修正，需在发布说明里讲清。
- **代价：两处列语义变化需要全仓梳理**。`teacher_id` 从「归属」降为「所属教师域」，任何沿用 `teacher_id == me` 做 owner 隔离的地方都是潜在 bug（§2.2 已点出最典型的一处）。清单：`questions/repository.py`、`questions/service.py`、AI 工具 `list_bank_questions` 及其投影、导出取题、`analytics` 聚合。
- **代价：学生题库会增长**。缓解见 §2.5（默认只显示练过的）；若长期增长成问题，后续可加「学生题按 `archived_at` 定期归档」策略，本轮不做。
- **代价：新增一次迁移**（2 列 + 回填 + 1 索引）。幂等 DDL，老库新建库行为一致。
- 后端可单测：存量回填后 `owner_id == teacher_id`；学生看不到教师的题（`owner_id` 隔离）；教师题库查询**不含**自己学生的题（且 `teacher_id == me AND owner_id != me` 能查到）；学生出题落库后 `owner_id` 为该学生且 `teacher_id` 为其归属教师；作答后错题本可引用该题；`question_id` 不再出现 `TaskQuestion.id`。
- 前端需新增：学生端「我的题库」入口与 `practiced` 过滤切换（§2.5）。

## 4. 备选（Considered Options）

- **所有表统一加 `account_id` + `created_at` 通用属性**（用户提议）：**部分采纳，但不做全表改造。** 采纳的部分：它点出「归属应当单一、角色不必进数据」，据此 §2.1 删掉了 `owner_role`。不做的理由有四：
  1. **不是所有「人字段」都是归属。** `Task.student_id`（`task.py:21`）与 `TaskAssignment.student_id`（`task_assignment.py:26`）是**被派发对象**（参与者），`Conversation` 的 `teacher_id` + `student_id` 是「归属 + 触发者」二元（ADR-0048）。统一叫 `account_id` 会把「拥有者」与「参与者」压成同一个名字，制造比现在更难辩的歧义。
  2. **`created_at` 绝大多数表已有**（可空）。少数表用领域时间——`Checkin.checkin_date`、`WrongQuestion.first_wrong_at`——是刻意的：领域语义比「创建于何时」更有意义，不该被通用列取代。
  3. **现存两套命名承载的是不同语义，不是同一概念的两种叫法。** `teacher_id` 表示「教师拥有」，`student_id` 表示「学生相关」，合并成一名会丢掉这层信息，却换不来新的能力。
  4. **迁移面与收益不匹配**：十几张表、数十个引用点、各表回填逻辑互不相同，而收益是纯命名层面的。
  结论：归属统一只做在**真正的 owner 表**上（本 ADR 即 `Question`），不做全表无差别铺开。

- **不加 owner 维度，学生出题保持 ephemeral**（ADR-0081 §2.2 初稿）：改动为零。否决：学生练完无记录、不进错题本、不驱动复习，「自己练」的价值只剩当场那一轮。
- **只加 `student_id` 可空列，`teacher_id` 保持原义**：列更少。否决：会出现「两个 id 列谁代表归属」的二义——教师的题 `student_id` 为空、学生的题 `teacher_id` 填谁（归属教师还是自己？）必然歧义，且每个查询点都要写一遍二选一逻辑。
- **改列名 `teacher_id` → `owner_id`**（单一 owner 列，不留冗余）：模型最干净。否决：改动面更大（全仓引用点 + 迁移风险），且丢掉「所属教师域」这个教师管理学生题的抓手——而那正是本 ADR 想保留的能力。现改为新增两列 + 收窄旧列语义。
- **学生出题不入库，改错题本允许 `question_id` 为空并存题面快照**：避免题库膨胀。否决：`WrongQuestion` / `AnswerRecord` 的外键与非空约束都要放开，掌握度 join 从此要有「有题 / 无题快照」两条分支，学习闭环的核心轴被削弱；而题库膨胀用 §2.5 的视图过滤就能解决，代价小得多。
- **学生也能建 Task（走完整两步法）**：与教师完全对称。否决：任务语义是「教师派发给学生的作业」，学生自建任务会把派发、打卡、状态机（ADR-0069）引入学生端，远超本题需要。
