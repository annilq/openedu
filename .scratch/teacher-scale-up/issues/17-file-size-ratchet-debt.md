# 17: 文件规模棘轮补登债务（跨 epic）

**What to build:** 将 3 个此前提交已落地但未登记 `file_size_guard` 基线的 >400 行文件，由各自 owner 二选一处理：要么拆小到 ≤400 行，要么正式确认基线（登记实际行数并备注 why）。当前临时补登仅为保测试绿，不应长期锁在高位。

**Blocked by:** 无（独立技术债，跨 epic）

**Status:** done

**范围（2026-10-07 实施 ticket 06 时发现，临时补登于 commit `ce4d1de`）：**
- `features/analytics/presentation/screens/analytics_screen.dart` — 488 行（analytics ticket 12，commit `409b9c9`）
- `features/courseware/presentation/widgets/section_practice.dart` — 429 行（courseware 第二轮，commit `6ffefe0`）
- `features/home/presentation/widgets/teacher/teacher_task_form_view.dart` — 425 行（teacher 方向）

- ~~`features/courseware/presentation/pages/courseware_present_page.dart`（429 行，courseware 第二轮）~~ → **已解决（2026-10-08）**：拆分 497→320 并移出基线（主文件 + `courseware_section_edit_dialog` 抽离），见 2026-10-08 日志；不计入剩余债务。

**Why:** ADR-0058 棘轮要求 >400 行文件必须登记基线且只许下调；这 3 个文件在各自 commit 时漏登，导致 `test/file_size_guard_test.dart` 长期挂在「未登记的文件不得超过 400 行」失败。ticket 06 实施时为保测试绿已临时补登，但基线锁在高位违背棘轮「只许下调」方向。

**决策（2026-10-08 拍板，分文件定 A/B）：**
- `analytics_screen.dart`（488）→ **B 确认保留**：看板属合理大件，正式登记基线并补 why 注释，后续不得增长。
- `section_practice.dart`（429）→ **A 拆小**：抽非核心 widget/长逻辑到子文件，主文件 ≤400，同步下调基线。
- `teacher_task_form_view.dart`（425）→ **A 拆小**：抽长表单/聚合到子文件 ≤400，下调基线。

- [x] `analytics_screen.dart`：**B 确认保留**——补 why 注释（+4 行），基线同步 488→492 登记真实行数（2026-10-08）
- [x] `section_practice.dart`：**A 拆小**——抽出 `PracticeQuestionPrompt`/`PracticeAction`/`PracticeNotice` 到 `section_practice_parts.dart`，主文件 429→293 回到 400 内，**整条移出 `_baseline`**（2026-10-08）
- [x] `teacher_task_form_view.dart`：**A 拆小**——抽出审阅闸门/动作区到 `teacher_task_form_actions.dart`，主文件 429→384 回到 400 内，**整条移出 `_baseline`**（2026-10-08）
- [x] `flutter test test/file_size_guard_test.dart` 仍全绿（3/3），`flutter analyze` 0 issue，`flutter test` 399 全绿

**实施后 `_baseline` 净减 2 条**（section_practice、teacher_task_form_view 退出债务登记）；analytics_screen 作为 B 类合理大件继续保留。两处 A 均为 ADR-0058 P4「子件独立成文件」的真实职责分离。

**决策锚点:** ADR-0058 规模棘轮；技术债 backlog，不在本轮 16 票内。
