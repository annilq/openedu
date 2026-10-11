# Ticket 05 — 后端 `class_id` 扩展（`POST /students` 与 `/import` 归属校验）

- **What to build**: 补 ADR-0086 §2.5 的两处缺口。`POST /students`：请求体已能透传 `class_id`（共享 `UserCreate`/`UserBase`），缺口是**缺少对 `class_id` 归属当前教师的校验**——落库前用 `require_owned` 校验班级归属。 `POST /students/import`：当前**不接受** `class_id` 参数；新增可选 `class_id`，导入行直接归入该班（模板仍只「姓名/学号」两列不变），并做归属校验（越权整体失败）。
- **Blocked by**: —
- **Status**: ready-for-agent
- **验收清单**:
  - `POST /students` 带 `class_id` 后该生 `class_id` 落库且属当前教师；带**他人** `class_id` 应 403。
  - `POST /students/import` 带 `class_id` 后导入学生归入本班；导入后 `GET /students?class_id=` 查到且 `username` + 初始密码能真正登录。
  - 越权：`class_id` 指向其他教师的班级时导入/建生整体失败（不部分成功）。
  - 两项扩展均走既有 `core.guard`（`require_owned`），不内联 `teacher_id` 比较（分层不变量 9）。
  - 模板列不变（仍只「姓名/学号」）；不新增后端依赖。
  - 端点测试缝：FastAPI TestClient + 临时 SQLite，夹具沿用 `backend/tests/conftest.py` 与 `tests/utils/user.py`；覆盖建生落库/403、导入归入/越权。
