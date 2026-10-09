# ADR-0065 产品定位重定位：家长/儿童 → 教师/学生

- 状态：提案（待评审）· Batch 1 已落地（CONTEXT.md + 后端术语/列改名 + 幂等迁移）
- 日期：2026-10-06
- 关联：ADR-0047/0048（助手整页）、ADR-0059（单源导航）、ADR-0055（资料库 parent_id）、ADR-0061（scene 渲染）

## 1. 背景（Context）

原定位（见 `CONTEXT.md` 第 3 行）：中小学错题复习应用，**家长生成任务 → 儿童答题产生错题 → 间隔重复复习直至毕业**。
现在产品定位改为面向**教师与学生**：教师出题/派发/看学情，学生答题/复习/伴学。

经 grill 四个分叉，结论锁定为**最小改造**：

| 分叉 | 决策 |
|---|---|
| 改动深度 | **纯重命名**：`parent→teacher`、`child→student`，归属仍 1 对少数，**不加班级/共享/批改回流** |
| 批改闭环 | **维持不回流**（学生卷仍导出 + 外部批改，错题/掌握度不自动更新，沿用现状设计） |
| 学生自主性 | **维持派发制**（学生只答题+伴学，任务全由教师派发） |
| 共存策略 | **完全替换**：下掉 `parent/child` 角色，统一为 `teacher/student`，迁移旧数据 |

> 明确**不做**（避免范围蔓延，grill 已关闭）：班级/学生组管理、题库/资料跨班共享、批改回流系统、学生自主练习。

## 2. 决策（Decision）

全仓以「机械重命名 + 角色枚举替换 + 旧数据迁移」完成定位切换，**不引入任何新实体或新关系**。
术语映射：`家长(parent)`→`教师(teacher)`，`儿童/娃娃(child)`→`学生(student)`。

## 3. 需要调整的功能（核心交付：哪些功能要改）

### 3.1 角色枚举与归属标识（后端）

| 位置 | 当前 | 改为 | 备注 |
|---|---|---|---|
| `User.role` 取值 | `parent` / `child` | `teacher` / `student` | 全仓 `ctx.role` 驱动 AI 分流 |
| `ModelConfig.parent_id` | `parent_id` | `teacher_id`（建议 RENAME COLUMN） | `model_management/repository.py` 全函数签名 `parent_id`→`teacher_id` |
| 题库/资料/任务/会话归属列 | `parent_id` | `teacher_id` | 含 ADR-0055 的 4 张资料表 |
| 每学习者维度列 | `child_id` | `student_id` | `wrong_question`/`mastery`/`review`/`attempt`/`assistant_session` |
| `core.guard` 归属校验 | `require_owned(parent_id=...)` | `require_owned(teacher_id=...)` | 分层不变量 9，只经 guard（ADR 纪律） |

> **DB 列改名取舍**：`ALTER TABLE … RENAME COLUMN parent_id TO teacher_id` 在 SQLite 3.25+ 支持且对「无 FK、仅作归属过滤」的列安全（无约束重建风险，区别于 ADR-0061 §R 的加约束场景）。若想进一步压低 DB 风险，可**保留列名 `parent_id`、仅改名角色枚举与代码标识符**——代价是 glossary 与代码语义不一致。默认建议改名，迁移须幂等（先读 `sqlite_master` 判列是否存在）。

### 3.2 AI 能力分流（后端 `app/ai`）

| 文件 | 当前 | 改为 |
|---|---|---|
| `subagents/guide/manifest.py` | `roles: ["parent"]` | `roles: ["teacher"]`（仅教师出题，不变） |
| `subagents/tutor/manifest.py` | `roles: ["parent", "child"]` | `roles: ["teacher", "student"]` |
| `subagents/query/__init__.py` 等 | `roles: [parent, child]` | `roles: [teacher, student]` |
| `query/tools/_shared.py` `project_for_role` | child 端剥答案与解析 | student 端剥答案与解析（**保持「裁剪只在一处」**，不动第二处） |
| `query/tools/list_children.py` 等 | `child_id`/`child_name` 定位器 | `student_id`/`student_name` |
| `assistant_repository`/`assistant_notifier` 注释 | 「parent_id + child_id」归属校验 | 「teacher_id + student_id」 |

### 3.3 前端导航与页面（ADR-0059 单源）

| 文件 | 当前 | 改为 |
|---|---|---|
| `home/presentation/parent_pages.dart` | `sealed ParentPage`（13 页） | `sealed TeacherPage`，页名 `AddChild`→`AddStudent`、`EditChild`→`EditStudent`、`Overview/CreateTask/TaskList/WrongQuestions/TutorLogs/QuestionBank/MaterialLibrary/Models/TaskReview/Profile` 不变（语义仍适用） |
| `home/presentation/screens/home_screen.dart` | `user.isParent` 分派 | `user.isTeacher` |
| `main/app.dart`、`profile_screen.dart` | `isParent` / 角色标签 `家长`/`学生` | `isTeacher` / `教师`/`学生` |
| `features/children/*` | 儿童管理（AddChild/EditChild/`interest_picker`） | `features/students/*`，兴趣选择改为学生 onboarding（文案调整，逻辑不变） |

### 3.4 伴学助手 UI 口径

| 文件 | 当前 | 改为 |
|---|---|---|
| `assistant_chat_page.dart` | `isParent` 切标题/空态；家长=`AI 学习助手`、儿童=`问 AI 老师` | `isTeacher`；教师=`AI 学习助手`、学生=`问 AI 老师`（学生端文案可保留或改`问 AI 老师`不变） |
| `_WelcomeHint` | 家长：`可以出题、查学情、看错题`；儿童：`有问题就问 AI 老师吧` | 教师同左；学生同左 |

### 3.5 导出/批改（保持不回流，仅改文案主体）

| 文件 | 当前 | 改为 |
|---|---|---|
| `export` / 学生卷相关文案 | 「家长用外部批改 App 扫码」 | 「教师用外部批改 App 扫码」；`CONTEXT.md` §学生卷 批改主体 家长→教师 |
| `CONTEXT.md` 学生卷条目 | 批改由家长完成、不回流 | 批改由教师完成、不回流（设计不变） |

### 3.6 术语事实源 `CONTEXT.md`（glossary 增量）

重写以下条目（保留定义结构，仅替换主体与 `_Avoid_` 说明）：

- **家长 (Parent)** → **教师 (Teacher)**：角色 `teacher`，对**学生账户**有监管与出题权限。
- **儿童账户 (Child Account)** → **学生账户 (Student Account)**：角色 `student`，学习者，拥有错题本、答题与复习。删除 `_Avoid_: 学生（本应用学习者即儿童账户）`——现在学习者即学生账户，术语统一。
- **角色** 段：`parent` / `child` → `teacher` / `student`。
- **学生卷 (Student Sheet)**：批改主体 家长→教师，其余不变。
- 全文中「娃娃」「家长」指代统一替换；`parent_id`/`child_id` 在术语表中改为 `teacher_id`/`student_id`。

## 4. 旧数据迁移

1. `UPDATE users SET role = 'teacher' WHERE role = 'parent'`；`role = 'student' WHERE role = 'child'`。
2. `ALTER TABLE … RENAME COLUMN parent_id TO teacher_id`（逐表；先判列存在，幂等）。
3. `ALTER TABLE … RENAME COLUMN child_id TO student_id`（涉及错题/掌握度/复习/作答/会话表）。
4. 迁移脚本放后端启动期幂等 DDL（参照 ADR-0053 长列表迁移纪律）；本地须 `cd backend` 跑（memory：真库 `backend/app.db`）。
5. 既有顺序污染测试（memory 记 4 个）与改名无关，但改名后全量 pytest 须重跑确认无回归。

## 5. 须保留的不变量 / 风险

- **ADR-0059 单源导航**：`TeacherPage` 仍为唯一 `sealed` 状态，禁止「索引+覆盖层+布尔」并列（前端测试 `parent_nav_single_source_test.dart` → 改名 `teacher_nav_single_source_test.dart`）。
- **`project_for_role` 裁剪只在一处**（ADR 纪律）：改名时严禁在 child/student 视图再开第二处答案剥离。
- **分层不变量 9**：归属判定只经 `core.guard`，禁内联 `x.teacher_id != y`（AST 守卫 `tests/ai/test_layering_invariants.py` 全仓扫，改名后必跑）。
- **全禁用 Material 控件**：改名不涉及控件树，但 `students` feature 新页面须在不套 Material 的树里真构建一次（memory 头号陷阱）。
- **文件规模棘轮 ADR-0058**：`features/children`→`features/students` 搬迁逐行原样搬，禁正则删方法（memory：DOTALL 吞 body 实测 58 编译错）。
- 测试改名清单：`children_notifier_test`→`students_notifier_test`、`parent_nav_single_source_test`→`teacher_nav_single_source_test`、`model_management_ui_test`（含家长文案断言）等含 `家长/儿童/娃娃` 字符串断言的全部同步改。

## 6. 验证

- `cd backend && uv run ruff check . && uv run pytest -q`（全量，含 `--basetemp` 沙盒，memory 纪律）
- `cd frontend && flutter analyze` + `flutter test`（关代理跑，memory 纪律）
- 端点验：教师端 `POST /assistant/chat` 走 `guide`（出题）；学生端同端点只走 `tutor`/`query`，答案仍被 `project_for_role` 剥离。
- 人工核对 `CONTEXT.md` 无残留 `家长/儿童/娃娃/parent/child` 旧术语（grep 守卫）。

## 7. 明确不做（Out of Scope，grill 已关闭）

- 班级/学生组、跨班共享题库与资料
- 批改回流（客观题自动判分 / 教师端内批改）
- 学生自主练习与自建任务
- parent/child 与 teacher/student 双角色共存

## 8. 落地进度 (Status)

### Batch 1 — 已完成（2026-10-06）：CONTEXT.md + 后端

- **CONTEXT.md glossary 全量改写**：家长→教师、儿童账户→学生账户、儿童→学生；列引用 `parent_id`/`child_id` → `teacher_id`/`student_id`；角色 `parent/child` → `teacher/student`；删除 child 端「Avoid: 学生」说明（学习者即学生账户）。保留全部 `_Avoid_` 与定义结构。
- **后端角色/列改名**（精确字符串替换，排除 `app/core/db.py` 原生迁移 SQL）：
  - `User.role` 枚举值 `parent/child` → `teacher/student`（模型 + 守卫 + deps）。
  - 归属列 `parent_id`→`teacher_id`、`child_id`→`student_id`（models / service / guard / tools）。
  - `require_parent`→`require_teacher`、`require_child`→`require_student`、`CurrentParent`→`CurrentTeacher`、`CurrentChild`→`CurrentStudent`、`resolve_parent`→`resolve_teacher`、`resolve_children`→`resolve_students`。
  - git mv：`app/features/children`→`students`、`list_children.py`→`list_students.py`、`list_parent_tasks.py`→`list_teacher_tasks.py`；`main.py` 引用同步改 `students_router`。
  - AI SubAgent：`guide/query/tutor` manifest `roles` → `[teacher]` / `[teacher, student]`；`project_for_role` 对 `student` 端继续剥答案（`ANSWER_FIELDS` 不变）。
  - 配套脚本 `scripts/ingest_textbooks.py` 同步改 `get_teacher_id` / `Material.teacher_id`；`agent_core` 角色注释与 SubAgent 默认 `roles` 默认值改 `[teacher, student]`。
- **幂等迁移**（`app/core/db.py::_rename_ownership_columns`，挂 `run_migrations`）：旧库 `parent_id`→`teacher_id`、`child_id`→`student_id`（逐表判列存在，`ALTER TABLE RENAME COLUMN`）；`UPDATE "user" SET role` 映射。SQLite（`PRAGMA table_info`）+ Postgres（`information_schema`）双后端，表不存在即跳过，新库 no-op。
- **验证**：`ruff` 全绿；`pytest` 全量 **617 passed，3 failed（已 `git stash` 对照原码确认是改名前既存失败：vectorize/retrieval 3 个为已知顺序污染，非回归），2 skipped**。
- **改名脚本的误伤修复**（已逐处修）：`Path(...).parents[N]`→`.teachers[N]`（6 处：config.py / layering / option_prefix / scene_figures）、`Path.mkdir(parents=True)`→`teachers=True`（service.py:238）、后端测试 `test_option_prefix_contract.SITES` 被一并指向尚不存在的前端 `teacher/` 路径 → 回退到 `parent/`（前端本批不动，用户要求「先改 CONTEXT.md + 后端」）。

### Batch 2 — 已完成（2026-10-06）：前端 Dart

- **目录/文件改名**（精确脚本，regex 带负向预查保护 Flutter `child:`/`children:` 具名参数与 `SingleChildScrollView` 等控件）：
  - 目录 `features/home/.../parent/`→`teacher/`；文件 `parent_*`→`teacher_*`（如 `parent_task_review_notifier.dart`→`teacher_task_review_notifier.dart`、`parent_destinations.dart`→`teacher_destinations.dart`、`child_mastery_screen.dart`→`student_mastery_screen.dart`、`child_home.dart`→`student_home.dart`）。
  - 导航 `ParentPage`→`TeacherPage`（ADR-0059 单源，`teacher_pages.dart`）；`selected_child_provider`→`selected_student_provider`、`SelectedChild`→`SelectedStudent`、`SelectedChildNotifier`→`SelectedStudentNotifier`、`selectedChildProvider`→`selectedStudentProvider`。
  - `features/children/*`→`features/students/*`；`children` feature UI 文案「娃娃/儿童」→「学生」。
- **前端测试改名**：`parent_nav_single_source_test`→`teacher_nav_single_source_test`、`children_notifier_test`→`students_notifier_test` 等含旧术语断言同步改（`list_density_test`/`task_empty_state_test` 内 `SelectedChild`/`SelectedChildNotifier` 一并改 `SelectedStudent`/`SelectedStudentNotifier`）。
- **误伤回收**（broken stash `b657d2e4` 已被 `git reset --hard HEAD` + `git clean -fd` 清掉，仅 reflog 留痕；从 reflog 提取其它会话未提交文件做逆向修复）：
  - 21 个其它会话 `.dart`（语音/场景/知识点）全局逆向 `student→child`/`teacher→parent`/`学生→儿童` 安全拷回（确认不含 domain `student` 令牌）。
  - 3 个 untracked 文件从 stash `^3` 正确路径（`frontend/lib/...`）提取：`reflection_figure_gallery.dart`、`reflection_scene_dialog.dart`（`lib/shared/widgets/scene_interpreter/`）、`patch_macos_spm_migration.py`（`frontend/scripts/`）—— 二者本就已是 `学生/教师` 正确口径、Flutter 参数完好，原样恢复。
  - `selected_student_provider.dart:25` 被逆向误改的 `parentWrongQuestionsProvider` 回退为正确的 `teacherWrongQuestionsProvider`；并删掉逆向误生的孤儿旧名文件 `selected_child_provider.dart`，统一为单文件 `selected_student_provider.dart`。
- **验证**：`flutter analyze` = **0 error**（2 个预存 warning：`select_options_refresh_test:39` unused `picked`、`list_density_test:53` override，均非回归）；`flutter test`（关代理）= **344 passed / 7 failed**。
- **7 failed 非回归**：全部在 `scene_editor_dialog_test.dart` + `scene_option_group_test.dart`（ADR-0061 场景/反射功能，另一会话进行中）。失败为运行时场景逻辑（`Found 0 widgets with type "ReflectionSceneWidget"`、空列表），与 teacher/student 改名无关（`flutter analyze` 已零类型错误，改名仅动 import 路径与 `AppUserMode.parent`→`teacher`）。属另一会话进行中工作，不在本批范围，提交前由用户决定是否并回场景会话处理。
