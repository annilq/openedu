# 01: 班级实体与 CRUD 端点

**What to build:** 教师能创建、重命名、改年级、删除班级，班级自带年级（1–9）并归属当前教师。删除班级时班内学生只降级为「未分班」，学生账号与其错题数据保留。班级列表自带每班人数。所有操作受归属校验保护，别的教师无法触碰。这是后续批量派发（按班级分组）与学情统计（按班级作用域）的地基。

**Blocked by:** None (can start immediately)

**Status:** done

**Done note (2026-10-07):** 已由并行 agent 实现：`backend/app/db/models/class_entity.py` 定义 `Class`；`features/classes/router.py` 提供 CRUD（POST/GET/PATCH/DELETE）+ `student_counts`；`service.py` 走 `require_owned` 归属校验；`User.class_id`（user.py:24）可空；`core/db.py:_add_classes` 幂等迁移（`CREATE TABLE IF NOT EXISTS` + `ALTER user ADD class_id`）；`api/main.py:24` 注册路由。验收清单需对照新代码复核（跨教师 403、删班降级、老库迁移）。

- [ ] 建班成功；同教师下重名被服务端**显式查重**拒绝（不依赖 DB 约束，因 SQLite `ALTER TABLE` 静默忽略 `UNIQUE`，见 ADR-0061 §R）
- [ ] 改名 / 改年级成功
- [ ] 删班后班内学生 `class_id` 置空，学生账号与错题仍在，列表归入「未分班」
- [ ] `GET /classes` 返回的 `student_count` 与实际一致
- [ ] 别教师对本教师的班级做增删改返回 403
- [ ] 迁移幂等：手工造「缺班级表、学生表缺 `class_id` 列」的老库，确认迁移运行不报错、服务端降级正常
- [ ] 归属判定只经 `core.guard`（分层不变量 9），班级新增对应守卫，无内联 `teacher_id` 比较

**决策锚点：** ADR-0068、spec `teacher-class-and-student-management.md`；班级 `(teacher_id, name)` 唯一靠服务端查重；学生 `class_id` 可空、迁移不回填既有学生。
