# 17: 文件规模棘轮补登债务（跨 epic）

**What to build:** 将 4 个此前提交已落地但未登记 `file_size_guard` 基线的 >400 行文件，由各自 owner 二选一处理：要么拆小到 ≤400 行，要么正式确认基线（登记实际行数并备注 why）。当前临时补登仅为保测试绿，不应长期锁在高位。

**Blocked by:** 无（独立技术债，跨 epic）

**Status:** backlog

**范围（2026-10-07 实施 ticket 06 时发现，临时补登于 commit `ce4d1de`）：**
- `features/analytics/presentation/screens/analytics_screen.dart` — 488 行（analytics ticket 12，commit `409b9c9`）
- `features/courseware/presentation/pages/courseware_present_page.dart` — 429 行（courseware 第二轮，commit `6ffefe0`）
- `features/courseware/presentation/widgets/section_practice.dart` — 429 行（同上）
- `features/home/presentation/widgets/teacher/teacher_task_form_view.dart` — 425 行（teacher 方向）

**Why:** ADR-0058 棘轮要求 >400 行文件必须登记基线且只许下调；这 4 个文件在各自 commit 时漏登，导致 `test/file_size_guard_test.dart` 长期挂在「未登记的文件不得超过 400 行」失败。ticket 06 实施时为保测试绿已临时补登，但基线锁在高位违背棘轮「只许下调」方向。

**Resolution 选项（二选一，建议各自 owner 认领）：**
- **A. 拆小**：把非核心职责（大 widget / 长表单 / 聚合逻辑）抽到子文件，使主文件 ≤400；同步下调基线。
- **B. 确认保留**：若确属合理大件（如 analytics 看板），正式登记并写 why，基线维持，但后续不得继续增长。

- [ ] 4 个文件各自 owner 认领并二选一处理
- [ ] 处理后在 `test/file_size_guard_test.dart` 中对应基线条目同步（拆小则下调 / 确认则保留并补 why 注释）
- [ ] `flutter test test/file_size_guard_test.dart` 仍全绿

**决策锚点:** ADR-0058 规模棘轮；技术债 backlog，不在本轮 16 票内。
