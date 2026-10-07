# ADR-0068 班级实体与学生管理（含 Excel 批量导入）

- 状态：提案（待评审）
- 日期：2026-10-07
- 关联：ADR-0065（**重开**其 §7 已关闭的「班级/学生组」分叉）、ADR-0069（批量派发）、ADR-0070（导航重构与统计）、ADR-0059（单源导航）、ADR-0055（知识点目录按教师隔离）、ADR-0061 §R（加列不等于加约束）

## 1. 背景（Context）

ADR-0065 把产品定位从「家长 / 儿童」重定位为「教师 / 学生」，并在 §7 明确关闭了「班级 / 学生组管理」，理由是当时锁定「归属仍 1 对少数、不加班级与共享」。该 ADR 的 Batch 1 / Batch 2 已于 2026-10-06 落地。

定位切换后真实使用规模暴露，当前学生维护入口是**侧栏顶部浮层**（`features/home/presentation/widgets/teacher/teacher_student_selector.dart`，挂载点 `home_screen.dart:416`），它同时承担三件事：切换当前学生、添加学生、编辑学生。三个结构性缺陷：

1. **浮层无法承载规模**：`GET /students`（`features/students/router.py:74`）一次返回当前教师的全部学生，**无分页、无搜索、无排序**；浮层全量渲染。
2. **无批量手段**：全仓无 Excel / CSV 导入能力，`openpyxl` / `csv` 在 `pyproject.toml` 与 `pubspec.yaml` 中均无依赖；后端 `/students` 只有 `POST` / `PUT` / `GET` 三个端点，**没有 DELETE、没有批量接口**。
3. **入口语义混杂**：高频操作（切换上下文）与低频操作（维护花名册）挤在同一个浮层里。

### 1.1 已关闭分叉的重开

本 ADR **正式重开 ADR-0065 §7 的「班级 / 学生组」分叉**。

理由：批量导入学生这一需求本身隐含「一个教师管一群学生」。班级不是可选的锦上添花，而是**派发**（ADR-0069：一次派发给全班）与**统计**（ADR-0070：按班级分组）的必需分组维度。用「年级」当天然分组无法替代——同一教师可能带同年级的多个班。

> ADR-0065 §7 的其余三条（批改回流、学生自主练习、parent/child 与 teacher/student 共存）**维持关闭**。

## 2. 决策（Decision）

引入 `Class` 实体，学生**单班归属**，班级**自带年级**；新增教师端「学生管理」页面承载花名册维护与 Excel 批量导入；侧栏顶部学生选择器**整体移除**（切换语义的去向见 ADR-0070）。

### 2.1 数据模型

| 变更 | 内容 |
|---|---|
| 新增 `Class` 表（`backend/app/db/models/class_.py`） | `id`、`teacher_id` FK→`user.id`、`name`、`grade`（1–9）、`created_at`；唯一约束 `(teacher_id, name)` |
| `User` 新增 `class_id` | **可空** FK→`class.id`；仅 `role=student` 时有意义 |
| 迁移 | 启动期幂等：`CREATE TABLE IF NOT EXISTS class` + `ALTER TABLE "user" ADD COLUMN class_id`；**不回填**既有学生，`class_id` 保持 NULL |

> ⚠️ **加列 ≠ 加约束**（ADR-0061 §R）：SQLite 的 `ALTER TABLE ADD COLUMN` 会**静默忽略** `UNIQUE` 子句，且没有 `ADD CONSTRAINT` 语法。因此 `(teacher_id, name)` 唯一**只在 `CREATE TABLE` 里声明**，老库将缺少该约束——本地测不出来（新建库正常）。服务端 `create_class` 必须做一次**显式查重兜底**，不依赖 DB 约束。
>
> ⚠️ `User` 表的实际表名是 `"user"`（SQL 保留字），迁移 SQL 必须加引号；真库在 `backend/app.db`，迁移脚本必须 `cd backend` 跑，根目录跑会静默建空库。

**未分班学生**：`class_id = NULL` 的学生在学生管理页归入「未分班」分组，可通过 `POST /students/move` 批量移入班级。v1 **不自动创建「默认班级」**——自动建班会掩盖教师尚未整理花名册这一事实。

### 2.2 学生账号与导入策略

学生是 `user` 表里的**真实账号**（`username` 全局唯一 + `hashed_password`，登录走 `POST /auth/login`，`features/auth/router.py:20`）。因此「导入学生」必须同时解决「登录账号从哪来」。

| 项 | 决策 |
|---|---|
| Excel 最小列 | `姓名` + `学号`。任一缺失即**整行拒绝**并回传行号，**不做猜测、不做半成功** |
| `username` | **= 学号原样**，不做拼音转换、不加前缀、不自动去重 |
| 初始密码 | 统一常量，走后端配置 `STUDENT_DEFAULT_PASSWORD`（默认 `123456`） |
| 冲突处理 | 学号已存在 → 该行落入 `skipped`，**不覆盖**既有账号 |
| 导入结果 | 返回 `{created, skipped, errors: [{row, reason}]}`，前端逐行展示失败原因 |
| 幂等 | 同一份文件重复导入应全部落到 `skipped`（按 `username` 判重），不产生重复账号 |
| 账号分发 | 提供**账号表导出**（xlsx：班级 / 姓名 / 学号 / 初始密码）供教师分发给学生 |

> ⚠️ `username` 是**全局唯一**（跨教师），不是按教师隔离。同校两位教师导入相同学号会撞车。v1 行为：报「该学号已存在」，由教师自行加前缀；**不做自动加后缀**（会生成教师无法预期的账号）。

### 2.3 后端端点

| 端点 | 说明 |
|---|---|
| `GET /classes` | 当前教师的班级列表，含 `student_count` |
| `POST /classes` | 建班；显式查重 `teacher_id + name`（不依赖 DB 约束，见 §2.1） |
| `PATCH /classes/{id}` | 改名 / 改年级 |
| `DELETE /classes/{id}` | 删班；班内学生 `class_id` 置 NULL，**不删学生账号** |
| `GET /students?class_id=&keyword=` | 增加班级过滤与姓名 / 学号搜索 |
| `DELETE /students/{id}` | **新增**。见 §3 级联风险 |
| `POST /students/import` | multipart 上传 xlsx，按 §2.2 策略执行 |
| `POST /students/move` | 批量移入 / 移出班级（`{student_ids, class_id}`，`class_id=null` 表示移出） |

> **归属判定只经 `core.guard`**（分层不变量 9）：继续用既有 `require_owned_student`，班级校验新增 `require_owned_class`。**禁止**内联 `x.teacher_id != y`——AST 守卫 `tests/ai/test_layering_invariants.py` 全仓扫，改完必须跑。
>
> **术语与列位**：ADR-0065 已把 `parent_id`→`teacher_id`、`child_id`→`student_id`。新增代码一律用新名，不得再引入旧名。

### 2.4 前端

- 新增 `features/students/presentation/screens/student_management_screen.dart`：班级分组 + 搜索 + 导入 + 批量移动 + 删除。
- 学生详情页承载该学生的错题本与 AI 答疑记录（ADR-0070）。
- **文件规模棘轮**（ADR-0058）：新文件 ≤400 行、一个文件只暴露一个公开物；列表 / 导入结果 / 批量操作条拆为独立 widget，并在 `test/file_size_guard_test.dart` 的 `_baseline` 里登记（该基线只许下调）。
- **禁用 Material 控件**（全仓纪律）：新页面须在**不套 Material** 的树里真构建一次（`flutter analyze` 查不出来，只有真机构建才炸）。

## 3. 后果（Consequences）

**正**
- 花名册首次可维护：增 / 删 / 改 / 查 / 批量导入 / 批量分班。
- 班级成为派发（ADR-0069）与统计（ADR-0070）的分组维度。
- 顶部浮层从「三件事挤一起」收敛为纯粹的上下文切换器（并随后整体移除）。

**负**
- **删除学生的级联面很大**：`WrongQuestion` / `AnswerRecord` / `Checkin` / `TutorLog` / `Conversation` / `Message` 都挂 `student_id`。v1 定为**硬删 + 级联清理**，必须在**一个事务**内完成，并在响应里回传各表的清理行数。
  备选是 `is_active=false` 软删——但那样登录、派发、统计、列表全部要加 `is_active` 过滤，污染面更大且极易漏，故不采用。
- **新增两个外部依赖**：后端 `openpyxl`（xlsx 解析与账号表导出）、前端 `file_picker`（选文件）。二者都是新增攻击面，须走依赖引入评审。
- `username=学号` 把「学号必须唯一」变成硬约束，跨教师冲突只能报错。

## 4. 验证（Verification）

- `cd backend && uv run ruff check . && uv run pytest -q --basetemp=/tmp/<新目录>`（沙盒里**必须**带 `--basetemp`，否则 `tmp_path` 用例集体 EEXIST 误判为回归）。
- `cd frontend && flutter analyze`（认 `No issues found!`，退出码常非 0）+ `flutter test`（**先关代理**：`no_proxy="127.0.0.1,localhost,::1"`）。
- 导入用例须覆盖：正常导入、学号冲突、缺列、重复导入幂等、大班（≥60 行）。
- 端点级验证（项目纪律：前端打的是 REST，**「下发了 X」必须打到端点验**）：`POST /students/import` 后 `GET /students?class_id=` 能查到且 `username` 可登录。
- 老库形状回归：手工造一个**缺 `class` 表 / `user` 表缺 `class_id` 列**的库，跑迁移确认幂等且服务端降级正常。

## 5. 明确不做（Out of Scope）

- 多班归属（学生可属多个班，如行政班 + 教学班）
- 班级间共享题库 / 资料（ADR-0065 §7 维持关闭）
- 学生自助注册 / 班级码加入
- 首次登录强制改密
- 学生头像、家长联系方式等扩展档案字段
