# ADR-0070 教师端导航重构与学情统计

- 状态：提案（待评审）
- 日期：2026-10-07
- 关联：ADR-0068（班级，统计的分组来源）、ADR-0069（批量派发）、ADR-0059（单源导航）、ADR-0048（页内切模式）、ADR-0058（文件规模）、ADR-0064（题库硬删 → 孤儿错题）、ADR-0061 §U（读路径唯一入口）

## 1. 背景（Context）

教师端侧栏当前 8 项（`teacher_destinations.dart:35-81`）：概览 / 任务 / 布置任务 / 错题本 / AI 答疑记录 / 题库 / 资料库 / 模型管理，另有底部「我的」。

其中**错题本**与**AI 答疑记录**两项是**单学生维度**的（`teacher_wrong_questions_view.dart:87`、`teacher_tutor_logs_view.dart:25`，未选学生时直接返回空态「请先在侧栏选择学生」），它们依赖侧栏顶部学生选择器写入的 `selectedStudentProvider`。

`selectedStudentProvider` 是**全局学生上下文枢纽**，其 `select()`（`selected_student_provider.dart:20-27`）会在写入后立刻触发 4 个加载（进度 / 掌握度 / 错题 / 答疑日志），并同时被 6 处消费：

| 消费者 | 位置 | 用途 |
|---|---|---|
| 概览 | `teacher_overview_view.dart:40` | 该学生进度 + 掌握度 |
| 布置任务 | `teacher_task_form_view.dart:147/242/289` | **年级兜底 + 兴趣主题**；`selected == null` 时直接拒绝出题 |
| 错题本 | `teacher_wrong_questions_view.dart:67/87/171/188` | 取数 |
| AI 答疑记录 | `teacher_tutor_logs_view.dart:25` | 取数 |
| 题库 | `teacher_question_bank_view.dart:170` | 年级兜底 |
| 兴趣区块 | `teacher_task_interest_section.dart:37` | 学生 `interests` |

规模上来后这套「全局当前学生」模型失效：教师带 60 人时，顶栏浮层无搜索无分页，且「切换上下文」与「维护花名册」语义混杂（ADR-0068 已解决后者）。

## 2. 决策（Decision）

### 2.1 移除顶部学生选择器与 `selectedStudentProvider`

**整体移除**，不做降级保留。理由：保留一个「全局当前学生」会让「学生详情」和「全局上下文」变成两个事实源——一旦并列，必然出现「详情页显示 A 学生、出题却按 B 学生出题」的漏清 bug，且 `flutter analyze` 查不出来（ADR-0059 单源导航的核心教训）。

移除后各消费者的替代来源：

| 消费者 | 移除后 |
|---|---|
| 概览 | 从「该学生概览」改为**教师工作台**：待派发 / 待审核 / 谁没交（ADR-0069）+ 全班速览。**学生维度数据下沉到学生详情与统计页** |
| 布置任务 | 表单内新增**派发对象选择器**（班级多选 / 学生多选）。年级从派发对象推导：单选班级取 `Class.grade`；多选或跨年级取**众数**，平票则由教师手选。兴趣主题：多选时取 `interests` **交集**，交集为空则自动关闭兴趣模式并在 UI 说明原因 |
| 错题本 | 移入**学生详情页** tab |
| AI 答疑记录 | 移入**学生详情页** tab |
| 题库 | 教师**手选年级**，取消学生兜底 |
| 任务 | 按作业聚合（ADR-0069），可按班级过滤 |

> 「布置任务」的派发对象选择器**复用 ADR-0069 的 `TaskStudent` 语义**：出题表单收集的是派发对象，`confirm` 后 `assign` 时写入关联表。

### 2.2 侧栏改为 8 项

概览 / 任务 / 布置任务 / **学生** / 题库 / 资料库 / 模型管理 / **统计**（错题本、AI 答疑记录两项删除）。

- 学生管理页（ADR-0068）：班级分组 + 搜索 + 导入 + 批量分班 + 删除；**列表行直接展示错题数徽标**，并提供行内快捷入口直达该学生详情页的错题 tab——这是「去掉全局上下文」后对高频路径的补偿。
- 点学生 → **学生详情页**：页内 tab（概览 / 错题本 / AI 答疑记录）。

> **ADR-0059 单源导航**：`TeacherPage` 这个 `sealed` 仍是唯一导航状态，新增 `StudentManagementPage`、`StudentDetailPage(studentId)` 两个子类。学生详情内的 tab 是**局部**状态（页内切模式，符合 ADR-0048），**禁止**提升为全局 provider。

### 2.3 新增「统计」页

| 项 | 决策 |
|---|---|
| 作用域 | 三态：**单个学生 / 单个班级 / 全体学生**（依赖 ADR-0068 的 `Class`） |
| 维度 | 学科 / 年级 / 学期 / 知识点 |
| 指标 | 错题数（活跃 + 已毕业）、正确率、掌握度 |
| 端点 | `GET /stats/wrong-questions`、`GET /stats/accuracy`、`GET /stats/mastery`，共享 `?scope=&class_id=&student_id=&subject=&grade=&semester=` |

**数据来源（无需新表）**：`AnswerRecord(student_id, question_id, correct, score, source, created_at)` JOIN `Question(subject, grade, semester, knowledge_point)`；`WrongQuestion(student_id, question_id, wrong_count, review_stage, graduated_at)` JOIN `Question`。

### 2.4 四项必须钉死的统计口径

1. **年级取「题目」的 `grade`，不取学生的 `grade`。**
   统计的是错题分布，维度来自题；学生年级另有用途（按班级 / 年级筛选学生）。二者是**不同的东西**，UI 上必须分别标注为「题目年级」与「学生年级」，禁止混用同一个下拉。

2. **学期口径。** 学期**没有字典表**，是散落在 5 张表里的裸字符串，取值 `''` / `上学期` / `下学期`（知识点默认 `上学期`）。统计把 `''` **归入「整学年」，不单列空值组**；本 ADR 同时要求把取值收敛为常量，禁止各处再写新字面量。

3. **孤儿错题。** ADR-0064 支持题库硬删（`DELETE /questions`）；题删了 `WrongQuestion` 行仍在，而学科 / 知识点 / 学期全挂在 `Question` 上。统计把这些错题归入 **`未知` 分组并在 UI 显式标注数量**。v1 **不修改硬删行为**（那是独立议题）。

4. **掌握度跨学生必须走批量聚合。** `mastery` 目前是 **Python 内存分组**（`features/mastery/repository.py:43` 用 `dict` 分组，不是 SQL `GROUP BY`），逐学生调用 = N 次全量扫 `AnswerRecord`。统计页**必须新写 SQL 批量聚合端点**，**严禁**循环调用单学生 mastery。v1 **不引入掌握度快照表**。

**正确率定义**：`count(correct) / count(*)` 于 `AnswerRecord`；按 `source`（`practice` 练习 / `review` 复习）可分看，UI 提供切换。

## 3. 后果（Consequences）

**正**
- 侧栏从「8 项里 2 项是单学生维度、与全局上下文耦合」变得语义清晰。
- 消除「详情页显示 A、出题按 B」这类双事实源 bug 的可能性。
- 统计页首次提供跨学生视角，这是当前系统完全不具备的能力。

**负**
- **破坏性 UX 变更**：现有「切学生即看错题」的高频路径变成「学生 → 点人 → 点错题 tab」三层。缓解手段是列表行错题徽标 + 行内直达（§2.2），但退化客观存在。
- **概览页改造成「教师工作台」是全新设计**，不在既有代码里，需单独出原型后再实施。
- 移除 `selectedStudentProvider` 牵动 6 处消费方 + 4 个 provider 加载触发，是本批改动中回归面最大的一项。

## 4. 验证（Verification）

- `cd backend && uv run ruff check . && uv run pytest -q --basetemp=/tmp/<新目录>`。
- `cd frontend && flutter analyze`（`selectedStudentProvider` 移除后应为 0 error，若有残留引用即说明漏改）+ `flutter test`（关代理）。
- `test/teacher_nav_single_source_test.dart`（ADR-0059 守卫）须扩展覆盖新的两个页面状态。
- 统计口径回归：孤儿错题、`''` 学期、跨年级班级（班级自带年级但学生可跨年级）三类边界必须有测试。
- **端点级验证**（项目纪律）：统计数字必须打到 `GET /stats/*` 验，不能只改 service。

## 5. 明确不做（Out of Scope）

- 时间趋势（按周 / 月）—— 数据已具备（`created_at`），留作下一批
- 学生横向对比排行榜 —— K12 场景涉及学生排名，需产品与合规确认
- 统计结果导出（PDF / Excel）
- 掌握度历史快照表
- 修复题库硬删导致孤儿错题（独立议题，本 ADR 只做展示侧兜底）
