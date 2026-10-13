# 班级管理前端（容器 + 下钻）与年级语义反转 · Tickets 索引

> 来源 spec：`.scratch/class-management-frontend/SPEC.md`（GitHub issue 正文源）。
> 决策依据：ADR-0086（班级管理前端，含 2026-10-11 年级语义反转）；上游 ADR-0068（班级实体与后端，已落地）。
> 发布形式：本地 `.scratch` 文件（未建 GitHub issue；`gh` 未登录）。后续 `gh auth login` 后可一键转 issue 并打 `ready-for-agent`。
> 术语以 `CONTEXT.md` 为准；每个 ticket 文件含 `What to build` / `Blocked by` / `Status: ready-for-agent` / 验收清单。
> ⚠️ **全部 7 票已随 ADR-0086 落地并测过**（60e9896 班级管理前端导航/列表/下钻/班内建生导入；aec3ac6 后端 `POST /students` 与 `/import` 的 class_id+归属校验），本轮已闭合。

## Tickets（依赖序，blockers first）

| ID | 标题 | Blocked by | Status |
|----|------|-----------|--------|
| 01 | 年级语义反转（删除 `user.grade`，年级改由班级承载） | — | ✅ done |
| 02 | 一级导航「班级管理」落地（扩展 `sealed TeacherPage` + 单源测试） | — | done |
| 03 | 班级管理列表页（建/改/删班级 + 空态） | 02 | done |
| 04 | 班级下钻页（参数化 `StudentManagementScreen`：查看/筛选/返回 + 班内查看/移班/删除） | 03 | done |
| 05 | 后端 `class_id` 扩展（`POST /students` 与 `/import` 归属校验） | — | done |
| 06 | 班内添加与导入学生（默认归属本班） | 04, 05 | done |
| 07 | 端到端回归与全量测试（analyze/test + 年级回归） | 03, 04, 05, 06 | done |

> 并行分析：02 ‖ 05 文件集不相交（02=`features/home`+导航测试，05=`features/students` 后端），可并行；03 → 04 串行（04 复用 03 的列表页下钻入口）；**04 ‖ 05 可并行**（04 的下钻查看/筛选/返回/批量移班/删除全用既有端点，不依赖 05 的 class_id 持久化）；06 须等 04+05 两者都落地（前端入口 + 后端落库）；07 收口待 03/04/05/06。

## 决策锚点（写进每张 ticket）

- **复用优先**：下钻页是参数化既有 `StudentManagementScreen`，**不做**第二份学生列表实现。
- **导航单源**：扩展 `sealed TeacherPage` 增加一个 case，所有入口只调 `_go(page)`，禁止再开并行状态（同步 `teacher_nav_single_source_test`）。
- **年级唯一来源 = 所属 `Class.grade`**：任何消费方一律经 `user.class_id` → `class.grade` 解析（入口 `_student_grade`），未分班返回 0；**不保留 `user.grade` 字段**。
- **后端只补缺口**：`POST /students` 已能透传 `class_id`（共享 schema），真缺口是**归属校验缺失** + **`/import` 无 `class_id` 参数**；两项都走既有 `core.guard`，不内联 `teacher_id`。
- **全站禁 Material 控件**：新增页面/控件必须在不套 Material 的树里真构建。

## 最容易回归的断言（实施时不可省）

- **01**：全局 grep `app/` 无 `user.grade`/`student.grade`/`payload.grade` 残留；`assistant` 测试桩 `user` 须带 `class_id`（否则 `_student_grade` 抛 `AttributeError`）；年级回归经 `class_id` 解析 `== class.grade`。
- **02**：`flutter analyze` 零错误（残留旧导航状态即漏改）；`teacher_nav_single_source_test` 新增 case 后无并行状态。
- **03**：删班后前端提示「N 名学生已转为未分班」；空态 `AppEmptyState` 出现。
- **04**：`classId != null` 时看不到"全部/各班/未分班" chip、标题含班级名、返回回到列表；班内查看名册/批量移班/删除行为与原学生管理一致。
- **05**：带他人 `class_id` 应 403；`/import` 带 `class_id` 后导入学生归入本班且 `username`+初始密码能登录。
- **06**：下钻页「添加学生」新建账号 `class_id` 落为本班；「导入学生」带 `class_id` 后导入学生归入本班且 `username`+初始密码能登录；越权被 403 拦截。

## 测试缝

- **前端主缝（输出侧，最高位，ticket 04）**：参数化后的 `StudentManagementScreen` —— 喂 `classId`（null / 某班 id），断言加载端点（`GET /students?class_id=`）、chip 有无、标题、返回落点、班内查看/批量移班/删除。
- **前端次缝（ticket 06）**：下钻页「添加学生 / 导入学生」入口 —— 断言提交后 `class_id` 落为本班（依赖 ticket 05 后端），用假仓库+后端端点接住。
- **前端次缝**：新建 `ClassManagementScreen` —— 卡片渲染 / 新建 / 重命名 / 删除 / 空态，用假仓库接住保存调用。
- **前端导航缝**：扩展既有 `teacher_nav_single_source_test.dart`（不新建）。
- **后端缝**：REST 端点（FastAPI TestClient + 临时 SQLite，夹具 `backend/tests/conftest.py`、身份 `tests/utils/user.py`）。

## 转 GitHub issue 步骤（待登录）

1. `gh auth login`
2. 按编号 01→07 顺序建 issue，`Blocked by` 指向 blocking issue 编号（01 已 done，可标 closed 或并入集成分支）
3. 全部打 `ready-for-agent` 标签（01 标 `done`/closed）

## Backlog（延后待办，不在本轮 7 票内）

- 班级排序拖拽（v1 按 `created_at`）。
- 班级封面/头像等扩展档案。
- 学生自助加班 / 班级码加入。
- 多班归属（学生可属多个班）。
- 班级间共享题库 / 资料（ADR-0065 §7 维持关闭）。
