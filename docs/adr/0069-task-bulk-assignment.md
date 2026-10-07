# ADR-0069 作业批量派发（TaskStudent 关联表）

- 状态：提案（待评审）
- 日期：2026-10-07
- 关联：ADR-0068（班级实体，本 ADR 的分组来源）、ADR-0070（任务列表与导航）、ADR-0065（Task 生命周期 draft→ready→assigned→done）

## 1. 背景（Context）

当前派发模型是**严格的 1 对 1**：

- `POST /tasks/{task_id}/assign`（`features/tasks/router.py:333`）只接收**单个** `student_id`。
- `Task.student_id` 是单值可空列（`db/models/task.py:17`），`ready → assigned` 时绑定。

后果：教师带一个 60 人的班，给全班布置同一份作业要**点 60 次派发**，产生 60 条任务记录。这在 ADR-0068 引入班级之前是「可忍受的低效」，引入班级之后成为**必须解决的结构问题**——班级如果不能批量派发，就只是一个显示用的标签。

### 1.1 为什么改造成本可控

关键观察：`AnswerRecord` / `Checkin` / `WrongQuestion` **都已自带 `student_id`**，它们不依赖 `task.student_id` 定位归属。派生链路——答题、打卡、错题归集、复习队列、进度、掌握度——**全部按学生维度取数，不需要改动**。

需要改的只有「任务 ↔ 学生」这一层关系，以及 `answer` 的身份校验。

## 2. 决策（Decision）

新增 `TaskStudent` 关联表，`Task` 由「一个学生的派发容器」升格为**作业模板**（一次派发给多个班级 / 多个学生）。

### 2.1 数据模型

| 变更 | 内容 |
|---|---|
| 新增 `TaskStudent` 表（`db/models/task.py`） | `id`、`task_id` FK→`task.id`、`student_id` FK→`user.id`、`assigned_at`、`completed_at`（可空）；唯一约束 `(task_id, student_id)` |
| `Task.student_id` | **保留列，但不再是派发事实源**。读取一律走 `TaskStudent`；存量数据迁移期回填，新写入只走关联表 |

> ⚠️ **加列 ≠ 加约束**（ADR-0061 §R）：`TaskStudent` 的 `(task_id, student_id)` 唯一必须写在 `CREATE TABLE` 里；禁止事后用 `ALTER TABLE ADD COLUMN` 补约束（SQLite 静默忽略）。
>
> ⚠️ **不做双写**：单学生派发也只写 `TaskStudent`。`Task.student_id` 保留仅为兼容旧客户端读路径，**新代码禁止读它**。保留一列读不到值的列是有意为之的过渡态，需在 ADR-0069 完全落地后单独立项移除。

### 2.2 派发语义

| 项 | 决策 |
|---|---|
| `POST /tasks/{tid}/assign` | body 由 `student_id: UUID` 改为 `{class_ids: [], student_ids: []}`；服务端**展开 + 按 student_id 去重**（同一学生可能既来自班级又来自显式列表）后批量 upsert `TaskStudent`。空集合 → 422 |
| `Task.status` 语义 | 从「一个学生的状态」变为「**作业整体**状态」：`ready → assigned`（首次派发）；全部 assignee 有 `completed_at` 时自动转 `done` |
| 单学生完成态 | 学生答完该作业全部题目 → 写 `TaskStudent.completed_at` |
| 新增端点 | `GET /tasks/{tid}/assignees` —— 返回每个 assignee 的 `completed_at`，即「谁交了 / 谁没交」 |
| 取消派发 | `DELETE /tasks/{tid}/assignees`（`{student_ids}`）；全部取消则回退 `assigned → ready` |

### 2.3 答题身份校验改造

`answer`（`features/tasks/router.py:354`）当前按 `task.student_id` 定位作答者。改造为：

> 查 `TaskStudent(task_id=…, student_id=current_user.id)`，不存在即 403（该作业未派发给当前学生）。

这是**必须改**的一处，否则批量派发后所有非首个学生都无法作答。

### 2.4 迁移

启动期幂等（ADR-0053 纪律）：

1. `CREATE TABLE IF NOT EXISTS taskstudent`（含唯一约束）。
2. 回填：`INSERT … SELECT` 自 `task WHERE student_id IS NOT NULL`，`assigned_at = task.created_at`；`status='done'` 的补 `completed_at = task.created_at`（无更精确的历史数据）。
3. 回填后 `Task.student_id` **不清除**（过渡期保留）。

## 3. 影响面

| 位置 | 是否要改 | 说明 |
|---|---|---|
| `AnswerRecord` / `WrongQuestion` / `Checkin` / `TutorLog` | ❌ 不改 | 已自带 `student_id` |
| 复习队列 `review`（`GET /review/due`、`POST /review/answer`） | ❌ 不改 | 按 student 取错题 |
| `mastery`（`GET /tasks/students/{sid}/mastery`） | ❌ 不改 | 按 student 聚合 |
| `GET /tasks/students/{sid}/progress` | ❌ 不改 | 路径已是 student 维度 |
| `POST /tasks/{tid}/answer` | ✅ 必改 | 身份校验改走 `TaskStudent` |
| `POST /tasks/{tid}/checkin` | ✅ 必改 | 打卡须校验该学生在 assignee 内 |
| `GET /tasks/today`（学生端） | ✅ 必改 | 从「我的 assigned 任务」改为 JOIN `TaskStudent WHERE student_id = me` |
| `GET /tasks`（教师端） | ✅ 改 | 一份作业一条，条数**下降**；新增 `class_id` / `assignee_count` 字段 |
| `export`（导出练习卷） | ⚠️ 复核 | 若按 task 导出，需确认是「整卷」还是「按学生分卷」 |
| 前端「布置任务」页 | ✅ 改 | 见 ADR-0070：派发对象改为表单内显式选择 |

## 4. 后果（Consequences）

**正**
- 一次派发给全班，教师操作从 60 次降到 1 次。
- 可回答「谁没交」——这是当前模型完全无法提供的信息。
- `GET /tasks` 列表条数从「学生数 × 作业数」降为「作业数」，长列表压力（ADR-0053）显著缓解。

**负**
- `Task.status` 语义变化是**破坏性**的：任何前端按 `status='done'` 判断「不可再作答 / 已完成」的逻辑都要复核——现在是「全班都完成」才 done，个别学生完成后仍须能继续作答。
- 过渡期存在 `Task.student_id` 与 `TaskStudent` 两套数据，回填前建的任务与回填后建的任务行为必须一致，须有测试钉住。
- 「作业整体完成」的自动判定依赖 `completed_at` 的准确写入，答一半就走的学生会永久卡住 `assigned`；v1 接受，教师可手动作废。

## 5. 验证（Verification）

- `cd backend && uv run ruff check . && uv run pytest -q --basetemp=/tmp/<新目录>`。
- `cd frontend && flutter analyze` + `flutter test`（关代理）。
- 必测用例：单班级派发（N 人）、班级 + 显式学生交集去重、取消派发、非 assignee 答题应 403、全员完成后 `status` 自动转 `done`、老库回填幂等。
- **端点级验证**：派发后逐个 assignee 账号调用 `POST /tasks/{tid}/answer` 确认可作答（项目纪律：只改 service 不落端点是无效的）。
- 须跑 `tests/ai/test_layering_invariants.py`（分层不变量 9 全仓 AST 扫描）。

## 6. 明确不做（Out of Scope）

- 跨班级共享作业模板（作业仍属单个教师）
- 同一作业对不同学生出**不同题**（v1 一份作业 = 一份题集）
- per-student 截止时间覆盖
- 作业批改回流到掌握度（ADR-0065 §7 维持关闭）
