# 07 — Flutter 错题本模块

**What to build:** 在 App 中新增 `wrong_questions` feature：复习列表、复习作答、掌握度展示，体验与正常练习一致。

**Blocked by:** 05 — 遗忘曲线复习调度与流程, 06 — 知识点掌握度看板

**Status:** ✅ done

- [x] 娃娃可见待复习列表并能作答/打卡（复用 practice 组件）
- [x] 家长可见知识点掌握度看板
- [x] 重复使用 practice 的作答/批改组件，无重复实现
- [x] notifier 状态机（Idle/Loading/Success/Error）有 mocktail 单测

> 回填说明（2026-09-04）：前端 `features/review` 已落地（`wrong_questions_screen` / `review_screen` / `review_question_view` 复用 practice 组件，`review_notifier` 状态机）。原 `Status: ready-for-agent` 为空滞后标记，特此修正。
