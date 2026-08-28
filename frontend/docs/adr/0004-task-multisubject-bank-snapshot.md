# ADR-0004: Task 扩展多学科 + 题库快照隔离

- **Status**: Draft
- **Date**: 2026-08-27
- **Supersedes**: —
- **Affected**:
  - `backend/app/models.py`
  - `backend/app/api/routes/tasks.py`
  - `backend/app/crud.py`
  - `backend/app/domain/question_generator.py`
  - `frontend/lib/features/home/presentation/widgets/parent/parent_task_form_view.dart`
  - `frontend/lib/shared/domain/models/models.dart`

## Context

当前 `POST /tasks` 单学科、单组参数循环 `count` 次生成题目（[tasks.py:94-103](file:///Users/yunqi/Documents/develop/openedu/backend/app/api/routes/tasks.py)），`Question` 强绑单一 `task_id`（[models.py:84](file:///Users/yunqi/Documents/develop/openedu/backend/app/models.py)），家长无法在派发前审阅、编辑、收藏题目。AI 生成质量不稳，F-103 出题闭环缺少草稿审阅中间态——家长一键生成后即跳转娃娃做题页（[home_screen.dart:54-66](file:///Users/yunqi/Documents/develop/openedu/frontend/lib/features/home/presentation/screens/home_screen.dart)），无任何筛选/编辑/组卷能力。

用户期望："先建试卷 → 设计多科目题量 → 批量生成 → 审阅编辑收藏 → 确认成卷"。经 grill 收敛，本 ADR 落地"扩 Task + 题库快照隔离"路线，**不引入 Paper 命名**，题库层即 `Question` 表本身（删 `task_id` 独立实体），化解"深拷贝需要原题层"的矛盾。

## Decision

1. **Task 表瘦身 + 加状态机**
   - `Task` 删除 `subject/grade/knowledge_point/qtype/difficulty/count` 单值字段（学科下沉到题），仅保留 `title/status/parent_id/child_id/created_at`。
   - `Task.status` 扩展为 `draft | ready | assigned | done`：
     - `draft`：可加/删/改/重生成题，娃娃不可见
     - `ready`：家长确认锁定，可派发
     - `assigned`：已派发给娃娃，只读快照
     - `done`：娃娃完成打卡

2. **`Question` 表本身即题库层（不引入 `QuestionBank` 表）**
   - `Question` 删除 `task_id` 字段，改为独立实体（题库里的一道题），可跨 Task 复用。
   - `Question` 仅在引用它的 Task 处于 `draft` 态时可编辑。
   - "题库" = 所有 `Question` 行的虚拟集合，未来若需按学科/年级分库或多对多，再加 `QuestionBank` 表。

3. **新增 `TaskQuestion` 表（派发快照层）**
   - 派发（`ready → assigned`）时，深拷贝 `Question` 的 `stem/options/answer/explanation/qtype/knowledge_point/subject` 到 `TaskQuestion`。
   - `assigned` 后娃娃做题、批改、错题归集全部读 `TaskQuestion` 快照，不读 `Question`。
   - 家长编辑 `Question` 不影响任何已派发任务的快照（快照隔离）。

4. **多学科一卷批量生成端点**
   - 新增 `POST /tasks/batch-generate`，接收多规格数组：
     ```json
     {
       "child_id": "...",
       "title": "...",
       "specs": [
         {"subject": "数学", "grade": 2, "knowledge_point": "...", "qtype": "calc", "difficulty": "medium", "count": 5},
         {"subject": "语文", "grade": 2, "knowledge_point": "...", "qtype": "fill", "difficulty": "easy", "count": 3}
       ]
     }
     ```
   - 后端逐科循环调 `QuestionGenerator.generate()`，逐题入 `Question`（题库层）+ 挂 `TaskQuestion` 草稿项，返回 `Task` 草稿态。
   - 保留原 `POST /tasks` 单科端点作为兼容入口（内部转调批量端点）。

5. **多科表单：混合形态**
   - 前端按"学科行"配置：每行 = 学科 + 知识点 + 题型 + 难度 + 题量，可加多行。
   - 提供"一键均分题数"快捷按钮：输入总题数 + 选 N 个学科，自动等分到各行。
   - 默认填充一行数学（兼容旧习惯），家长可加/删行。

6. **题目编辑字段范围**
   - `draft` 态可编辑：题干、选项文本、解析、知识点、**`answer`**。
   - **仅禁止编辑 `qtype`**（防娃娃端 UI 渲染崩——calc 无 options / choice 必须有 options）。
   - 安全保证：`Question.answer` 改动只影响题库层与未派发草稿；已派发任务读 `TaskQuestion.answer` 快照，派发即冻结，不受编辑污染。无需"答案版本 + 历史重判"机制。
   - 改 `qtype` 走"重生成该题"（题型变更会破坏 UI 渲染契约）。

7. **派发动作分离**
   - 家长"确认成卷" = `draft → ready`（锁定题集）。
   - 家长"派发给娃娃" = `ready → assigned`（深拷贝快照 + 绑 child_id）。
   - 两动作分离，家长可"先成卷晚点派"。

## Consequences

- **正面**
  - 家长获得草稿审阅能力，F-103 闭环补全。
  - 题库可跨 Task 复用，一卷天然支持多学科混合。
  - 派发快照隔离，家长改题库不污染已派发/在做的任务。
  - 不引入 Paper 命名，Task 表保留，现有 `/tasks/today`、`/tasks/{id}/answer`、`/tasks/{id}/checkin` 改读 `TaskQuestion` 即可，路由结构不动。
  - 数据模型最简：不引入 `QuestionBank` 表，`Question` 删一列即题库层。

- **负面**
  - 新增 1 张表（`TaskQuestion`）+ `Question` 删除 `task_id` 一列，需数据迁移：现有 `Question` 行变为独立题库题，并为每个旧 Task 生成 `TaskQuestion` 快照行。
  - **不支持一卷多派**（简化取舍）：一份 Task 仍绑单一 `child_id`，要派给两娃就生成两份独立 Task，AI 生成重复调用成本可接受。
  - `Question` 仅禁改 `qtype`；改 `answer`/题干等走编辑（draft 态安全），改 `qtype` 走"重生成"。

## Alternatives considered

- **方案 Y 完整题库层（叫 Paper）**：否决。用户明确"不要 Paper"，且 Paper 与"题库层"是同构概念（`Question` 即题库），换名即可。
- **方案 X 极简（不引入题库层，靠状态锁代替深拷贝）**：否决。状态锁无法满足"题库跨 Task 复用"诉求，且家长编辑草稿题时若已派发同题任务仍会污染。
- **废 Task 表、Paper 直接绑 child_id**：否决。破坏性最大，需迁移现有 Task 数据 + 改所有 `/tasks/*` 路由。
- **引入 `QuestionBank` 实体表**：否决。当前家庭私用、单家长，无需题库分组/多对多，`Question` 表本身即可承担题库层，多一张表徒增语义缠绕（"Question 属于 QuestionBank"= 废话）。未来真需分库再加。

## Open Questions

- **O1（已决）**：不引入题库表。`Question` 表本身即题库层（删 `task_id` 独立实体）。未来若需按学科/年级分库或多对多，再加 `QuestionBank` 表。
- **O2（已决）**：`Question.answer` 在 `draft` 态可改，派发时（`ready → assigned`）深拷贝到 `TaskQuestion.answer` 即冻结。已派发任务读快照不受污染，**不需要**"答案版本 + 历史重判"机制。仍禁改 `qtype`。
- **O3**：一卷多派后续是否补？当前不支持，需复用就再生成一份。
- **O4**：现有 `Task` 数据迁移策略——旧 `Task.subject/grade/...` 字段值下沉到其 `Question` 行，`Question` 删除 `task_id` 改为独立实体，并为每个旧 `Task` 生成 `TaskQuestion` 快照行。

## Addendum（2026-08-28）：题库「读取 + 复用」侧落地

ADR-0004 决策 #2 确立 `Question` 表即题库层（可跨 Task 复用），但原决策只覆盖**写入**侧（`batch-generate` 入 `Question`）。本次补齐**读取 + 复用**侧，使题库真正闭环（此前 `Question` 为"只写不读"的死库）。

### 新增端点
- `GET /questions`：家长作用域（按 `Question.parent_id`）列出题库题，支持 `subject/grade_segment/qtype/keyword` 过滤 + 分页；返回每项 `usage_count`（被多少 `TaskQuestion` 引用，用于级联安全提示）。
- `POST /tasks/from-bank`：选项 A——`{title, child_id, question_ids[]}` 直接组新任务，将 `Question` 深拷贝为 `TaskQuestion` 草稿项（回填 `question_id` 实现复用追溯）。落到现有 draft 审核页。
- `POST /tasks/{task_id}/questions/from-bank`：选项 B——把选定 `question_ids` 追加到现有 `draft` 任务（去重，`question_id` 已存在则跳过）。
- `GET /tasks?status=draft`：供选项 B 的草稿选择器列出可追加的草稿任务。

### owner 隔离
- `Question.parent_id` 指向归属家长；多家庭题库不互通（启动期 `run_migrations()` 在 `Question` 加列并回填：经 `task_question → task` 溯源找归属家长；sqlite/postgres 分支，`OperationalError` 降级）。

### 级联安全
- 单任务"换一题 / 删除该题"前查引用计数：仅当 `len(ref) <= 1`（即该题只被当前任务引用）才物理删除源 `Question`，否则仅解绑当前 `TaskQuestion`，避免误删被其他任务共享的题库题（`crud.remove_task_question` / `regenerate_one_task_question` 守卫）。
- 错误码：`TASK_20014`（题库题不存在 / 404）、`TASK_20015`（题库题越权访问其他家长 / 403）。

### 前端入口
- 家长端侧边栏 index 6 新增「题库」入口 → `ParentQuestionBankView`：年级 segment（全部 / 1~9 年级）+ 学科/题型筛选 + 关键词（300ms 防抖）+ 多选 + 底部双动作（「用这些题生成任务」→ 选项 A；「加入已有草稿」→ 选项 B 草稿选择器）。成功后复用 `ParentTaskReviewScreen`（specs 为空时隐藏「整卷重生成」）。

### 关联文档
- 详细方案见 `实施文档_题库复用闭环_后端.md` / `实施文档_题库复用闭环_前端.md`。
