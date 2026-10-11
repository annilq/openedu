# Ticket 06 — 班内添加与导入学生（默认归属本班）

- **What to build**: 在班级下钻页（ticket 04）内，「添加学生」新建的账号与「导入学生」的批量账号**直接归入本班**（`class_id` 预填为本班），免去"导入后再手动分班"。前端入口来自 ticket 04，持久化与归属校验来自后端 class_id 扩展（ticket 05）。
- **Blocked by**: 04, 05
- **Status**: ✅ done（2026-10-11，前端 class_id 透传落地并测过；后端归属校验见 ticket 05）
- **验收清单**:
  - 下钻页「添加学生」提交后，新建学生 `class_id` 落为本班（走 ticket 05 的 `POST /students` class_id 归属校验，越权 403）。
  - 下钻页「导入学生」带 `class_id` 提交后，导入学生直接归入本班（走 ticket 05 的 `/import` class_id 扩展）；导入后 `GET /students?class_id=` 查到且 `username` + 初始密码能真正登录。
  - 越权兜底：下钻页所在班级的 `class_id` 经 `require_owned` 校验，若越权建生/导入应被后端 403 拦截。
  - 文件规模棘轮：改动若逼近 400 行基线则抽 part，不调高基线。
  - 全站禁 Material 控件：新增入口在不套 Material 的树里真构建。
