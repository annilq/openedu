# ADR-0086 班级管理前端（容器 + 下钻）

- 状态：提案（待评审）
- 日期：2026-10-11
- 关联：ADR-0068（班级实体与后端，已落地）、ADR-0059（单源导航）、ADR-0058（文件规模）、ADR-0045（自适应布局）、ADR-0047/0048（助手整页非浮层）、ADR-0069（批量派发）、ADR-0070（学情统计）

## 1. 背景（Context）

ADR-0068 已完成**后端**全部能力：

- `Class` 实体（`backend/app/db/models/class_entity.py`）：`id / teacher_id / name / grade(1–9) / created_at`；
- `User.class_id`（可空外键，`backend/app/db/models/user.py:20`）；
- `GET/POST/PATCH/DELETE /classes`，列表带 `student_count`（`backend/app/features/classes/router.py`）；
- `GET /students?class_id=&keyword=`、批量移班 `POST /students/batch-reassign`、xlsx 导入/导出、带级联清理的删除，全部就绪且已注册 `main.py`；
- 前端 `ClassModel`（`frontend/lib/shared/domain/models/class_model.dart`）与 `classes` feature 的 `data/`+`providers/` 也已就位。

**真正的缺口只在「前端班级管理界面」**：

1. `features/classes/` **没有 `presentation/`** —— 建/改/删班级的页面不存在；`student_management_screen.dart:627` 的班级选择器空态仍写着「请先在侧栏新建班级」，而这个入口并不存在。
2. 现有 `student_management_screen.dart` 已能按班级分组、筛选 chip、批量移入/移出、导入，**但缺少「班级管理」这一级导航落点**——学生管理是扁平的全量视图，班级只是其内的一个分组维度。

用户诉求：新增「班级管理」，并在其下**为每个班级管理学生**（下钻）。即把已有的「按班级管学生」能力接到一个显式的班级管理容器下面，而不是从零造班级。

### 1.1 关键现状事实（避免重复造轮子）

- `StudentManagementScreen` 已接收 `onOpenStudent` / `onAddStudent` 回调，且内部已用 `ClassModel` + `state.classes` 做分组与筛选——**复用它的成本很低**，缺的是「传入某个 classId 只看该班」的参数化能力与「班级管理」导航入口。
- 后端 `create_student`（`students/router.py:40`）**不接收 class_id**，`import_students_from_xlsx`（`students/service.py:88`）**不读班级列**——要实现「在班级内直接加人/导入归入本班」，这两处需小扩展（见 §2.5）。

## 2. 决策（Decision）

### 2.1 信息架构：班级管理（容器）+ 下钻

- 新增**一级导航项「班级管理」**（`TeacherPage.classManagement`），与现有「学生管理」并列，不取代它。
- 「班级管理」页 = **班级卡片列表**：每张卡片显示 `name` + 年级标签（1–9）+ `studentCount` + 下钻箭头 + 行内「重命名 / 删除」入口。
- 点班级卡片 → **下钻**到该班学生管理页（push `AppPushedPage(showBack: true)`；遵循 ADR-0047/0048 整页非浮层，禁止裸 `Navigator.pop`，见 ADR-0059 §导航纪律）。
- 原「学生管理」**保留**为「全部学生」扁平视图（含「未分班」分组），作为全局视角不被移除。
- **导航单一源**：扩展 `sealed TeacherPage` 增加一个 case（ADR-0059），所有入口只调 `_go(page)`，禁止再开并行状态。

### 2.2 班级管理页（classes 的 presentation）

- 列表项：`name` + `grade(1–9 年级标签)` + `studentCount` + 下钻箭头；行内「重命名 / 删除」走页内联浮层（**不**用 Material `Dialog`，保持无 Material 祖先，见 ADR 视觉纪律）。
- 顶部「+ 新建班级」：内联表单（名称 + 年级 1–9 选择器），提交 `POST /classes`（`classes/router.py:26`）。
- 重命名 / 改年级：底部抽屉表单 → `PATCH /classes/{id}`（`classes/router.py:61`）。
- 删除：确认浮层 → `DELETE /classes/{id}`；后端仅把班内学生 `class_id` 置空（保留账号与错题，`classes/service.py:101`），前端提示「N 名学生已转为未分班」。
- 空态：`AppEmptyState`（解释为什么空 + 下一步「新建班级」）。

### 2.3 班级下钻页（复用并参数化学生管理）

复用 `StudentManagementScreen`，新增构造参数 `classId`（`String?`）：

| 行为 | `classId == null`（原学生管理） | `classId != null`（班级下钻） |
|---|---|---|
| 数据加载 | `GET /students`（全量 + 未分班） | `GET /students?class_id=` |
| 班级筛选 chip | 显示（全部/各班/未分班） | 隐藏 |
| 标题 | 「学生管理 · N 人」 | 「{班级名} · N 人」 |
| 返回 | 留在学生管理 | 返回班级管理列表 |
| 添加学生默认归属 | 无（弹窗可选班级） | 本班（`class_id` 预填） |
| 导入默认归属 | 无 | 本班（归入本班） |

班级内学生操作（决策：四项全要）：

- **查看名册**：搜索按姓名/学号，走 `GET /students?class_id=&keyword=`（关键词后端搜，分组客户端做）。
- **单个添加 + 导入**：在班级上下文内 `POST /students`（带 `class_id`）与 `POST /students/import`（带 `class_id`），直接归入本班，免去「导入后再手动分班」。
- **批量移班**：班内勾选 → 移出本班 / 移入他班（复用 `POST /students/batch-reassign`）。
- **删除学生**：班级上下文内删账号（级联清理错题/作答/打卡/答疑，后端已就绪）。

### 2.4 年级语义（决策收口 · 2026-10-11 已反转）

> 修正：原「`user.grade` 保留但可空」决策被推翻。学生**不再持有任何独立年级字段**，年级完全由班级承载。

- 学生**不持有年级字段**；年级的唯一来源是所属 `Class.grade`（1–9）。`Class.name` 可直接编码年级（如 `1级2班`），展示层无需单独的年级列。
- **同步规则**：不再有 `user.grade` 写入动作；学生年级随班级（重）分配自然变化——加入/改班级即获得该班 `class.grade`，移出班级即 `class_id = NULL`（年级解析为 0/未知）。
- **读取规则**：任何消费方（学情统计 / 答疑 / tutor 日志）需要学生年级时，一律经 `user.class_id` 解析到班级后取 `class.grade`。唯一解析入口为 `app.features.assistant.service._student_grade(session, user)`；未分班（`class_id` 为空）返回 `0`。
- `UserBase` 已删除 `grade` 列：`core/db.py` 的 `_add_classes` 在迁移时 `DROP COLUMN grade`（旧库向后兼容，极老 SQLite 包在 `try/except` 兜底）；`auth/schemas.UserUpdate`、`auth/repository.update_user`、`students/router` 同步移除 `grade` 形参。
- 明确**已移除 `user.grade` 字段**（采用原被否决的「学生年级=班级」方案；未分班学生年级解析为 0，不影响既有消费方——它们本就只在已分班/校内场景读取）。

### 2.5 后端小扩展（必要缺口）

| 端点 | 变更 | 校验 |
|---|---|---|
| `POST /students` | 请求体 `UserCreate` 增加可选 `class_id`；`create_student` 接收后写入 `user.class_id` | 班级须属当前教师（`require_owned`） |
| `POST /students/import` | 增加可选 `class_id` 参数；导入行直接 `class_id=该班`（模板仍只「姓名/学号」两列，不变） | 班级须属当前教师（`require_owned`）；越权整体失败 |

> 两项扩展均复用既有 `core.guard` 归属校验（分层不变量 9），不内联 `x.teacher_id != y`。

## 3. 后果（Consequences）

**正**
- 班级首次拥有可视化管理界面（建/改/删），不再依赖不存在的「侧栏入口」。
- 学生管理形成「全局扁平 + 逐班下钻」双视角，与 ADR-0069 整班派发、ADR-0070 按班统计的分组维度对齐。
- 复用 `StudentManagementScreen` 参数化，避免重复实现一份学生列表。

**负**
- 扩展 `sealed TeacherPage`（导航单源纪律，须同步 `teacher_nav_single_source_test`）。
- 新增班级管理列表页 + 参数化下钻页，文件数增加；受 ≤400 行棘轮约束，列表/表单/确认浮层须拆独立 widget 并在 `test/file_size_guard_test.dart` 的 `_baseline` 登记（只许下调）。
- 后端两处小扩展需补测试（归属越权回滚）。

## 4. 验证（Verification）

- 前端 `flutter analyze`（认 `No issues found!`）+ `flutter test`（**先关代理**）；班级管理列表 / 下钻 / 新建 / 重命名 / 删除 / 班内导入各一 widget 测试（**不套 Material 树**真构建）。
- 后端 `cd backend && uv run ruff check . && uv run pytest -q --basetemp=/tmp/<新目录>`。
- 端点级（项目纪律：前端打 REST，「下发了 X」必须打到端点验）：`POST /classes` 后 `GET /classes` 见人数；班内导入后 `GET /students?class_id=` 查到且 `username` 可登录；`POST /students` 带 `class_id` 后该生 `class_id` 落库。
- 年级回归：加入班级后，消费方经 `user.class_id` 解析的年级 `== class.grade`；移出班级后 `class_id` 为空，年级解析为 `0`（未分班），不报错。

## 5. 明确不做（Out of Scope）

- 多班归属（学生可属多个班）。
- 班级间共享题库 / 资料（ADR-0065 §7 维持关闭）。
- 学生自助加班 / 班级码加入。
- 班级排序拖拽（v1 按 `created_at` 排序）。
- 班级封面/头像等扩展档案。
