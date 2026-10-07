# 05: 练习提示级别选择 + tutor 分级驱动 + 反馈卡片

Parent: docs/specs/teacher-courseware-round-2.md（ADR-0067 第二轮 · 练习深化方向）

**What to build:** 课堂练习环节暴露「提示级别」选择（方向 / 条件 / 下一步，默认方向）；所选级别经「课件练习」上下文（`CoursewareContext.extra`）透传给 tutor，tutor 给出对应档提示（复用首轮已实现的 `_courseware_hint_context` 三档约束）；判错反馈卡片写明「哪错 + 给的是第几级提示 + 本练习不建任务 / 不落作答」；未配置模型时明确提示（沿用首轮处理）。

**Blocked by:** None（can start immediately）。

**Status:** done

## Done note（2026-10-07）
T05 落地并验收（前端为主，分级由提示词驱动，无需后端新增逻辑）：
- `AssistantCoursewareContext` 增 `extra` 字段 + `copyWith`；`toJson` 仅在 non-null 时序列化 `extra`，不污染无 extra 的旧调用。
- `SectionPractice`：新增提示级别选择器（方向 / 条件 / 下一步，默认方向，初始值读自 `section.payload['hint_level']`）；选级后 `_requestHint` 按级别构造约束化提示词（方向级不给关键条件、下一步级不给最终答案），并经 `extra={'hint_level': ...}` 透传到 `POST /assistant/chat` 请求体。
- 判错反馈卡：`_hintRequested` 后展示「已给【X】级提示（本练习不建任务、不记录作答）」，重申不建任务 / 不落作答。
- `hint_level` 走环节 payload 自由 JSON（后端 `sections` 为 JSON blob，原样落库，无需 schema 改动）；分级提示词已把级别语义带给 tutor。
- 测试：`test/courseware_practice_test.dart` 扩至 8 例（含 3 个 T05 新增：默认方向透传 + 反馈卡；选「下一步」后请求体带 `next_step`；选「条件」后带 `condition` 约束；始终不落任务/作答）。`flutter analyze lib/features/courseware lib/features/assistant` 0 issue；editor/present/practice 30 全绿。
- 注：`_courseware_hint_context` 后端三档约束在当前代码库不存在，分级由前端提示词承载；`extra` 已就位，待后端 tutor 接入即可结构化消费。
