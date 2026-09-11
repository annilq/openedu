# 题库即 Question 表，题目与任务解耦

题目作为可复用内容单元独立存储，任务只持有派发快照。这是领域数据模型的根基决策（原 ADR-0004）。

- **D1 归属隔离**：`Question` 通过 `parent_id` 做家庭隔离，娃娃端仅可见 `assigned`/`done` 态任务（`backend/app/features/tasks/repository.py:456` `get_child_tasks_today`），`draft`/`ready` 对娃娃不可见。
- **D2 题库=Question 表**：删除「题目绑 task_id」的独立实体，题目可跨 Task 复用（`backend/app/db/models/question.py:11`）。
- **D3 派发快照**：题目派发到任务时落 `TaskQuestion` 快照，作答提交与错题归集用 `TaskQuestion.id` + 源 `Question.id`（`backend/app/db/models/task.py:33`、`frontend/.../models.dart:82`）；娃娃端 `answer` 恒为 null 防作弊。
- **D4 多学科一卷**：`TaskSpec` 表达多学科批量生成的一条规格（`backend/app/features/tasks/schemas.py:10`）。
- **D6 字段可变性**：题干/选项/答案/解析/知识点可改，`qtype` 锁定（防娃娃端 UI 渲染崩）。
- **D7 任务生命周期**：`draft → ready`（家长确认成卷）→ `assigned`（绑 child_id 派发）→ `done`。

**Consequences**：题目复用与多家庭隔离天然成立，但「改一题是否影响历史任务」需靠 `TaskQuestion` 快照隔离——快照一旦生成，源题后续编辑不回灌已派发任务。
