# Ticket 01 — 年级语义反转（删除 `user.grade`，年级改由班级承载）

- **What to build**: 删除学生身上的独立年级字段，年级的唯一来源变为所属 `Class.grade`；班级名可直接编码年级（如 `1级2班`）。任何消费方需要学生年级时，一律经 `user.class_id` 解析到班级后取 `class.grade`（唯一入口 `assistant.service._student_grade`），未分班返回 0。
- **Blocked by**: —
- **Status**: ✅ done（2026-10-11，本轮回合已落地并测过）
- **验收清单**:
  - 后端：`UserBase` 删除 `grade`；迁移 `_add_classes` 中 `DROP COLUMN grade`（旧库向后兼容，极老 SQLite 包 `try/except` 兜底）；`UserUpdate` / `update_user` / `students/router` 同步移除 `grade` 形参；`assistant.service` 新增 `_student_grade` 并经 `class_id` 解析年级；`ai/subagents/query/tools/_shared.py` 的 `student_meta` 不再回传 `grade`。
  - 前端：`UserModel` 及整条仓库链（repository / datasource / notifier / form / picker / detail / home / profile / 测试桩）全部去 `grade`。
  - 测试桩：`assistant` 两处 caller 桩 `user` 补 `class_id=None`（否则 `_student_grade` 抛 `AttributeError`）。
  - 回归：`flutter analyze` 0 grade 错误；后端 assistant + students 共 8 文件 33 passed；全局 grep `app/` 无 `user.grade`/`student.grade`/`payload.grade` 残留。
  - 年级回归：加入班级后消费方经 `user.class_id` 解析的年级 `== class.grade`；移出班级后 `class_id` 为空、年级解析为 0、不报错。
