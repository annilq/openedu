# ADR-0086 端到端删除课堂练习环节的 AI 出题 / 提示

- 日期：2026-10-11
- 状态：Accepted
- 关联：ADR-0085（课件 AI 起草移除；§2.3 显式预留「若后续要删 B 须另开 ADR」——本 ADR 即那条「另开 ADR」）、ADR-0078 §2.6（练习内容块决策）、ADR-0067 §3.6（课件练习上下文透传）、ADR-0072（判定闭环与 `quiz` 标记）、`CONTEXT.md`（课件术语段）
- **Supersede**：ADR-0085 §2.3 把 B 的范围收窄为「仅讲课现场『问 AI 老师』浮标」（不再含 `SectionPractice`）；ADR-0078 §2.6「练习内容块」决策被撤销；ADR-0067 §3.6 里 `practice` 的专用用途（答错分级提示 / 课堂出题）被移除。

## 背景与决策

ADR-0085 在删除课件 AI 起草（A）时，把「课件里的 AI」拆成两处独立能力：

- **A = AI 生成课件内容**（起草 / 补充讲解 / 重新起草）——已删。
- **B = 讲课现场的助手集成**——ADR-0085 §2.3 保留，但预留「若后续要删须另开 ADR」。

B 内部其实还有两条**互不相干**的入口，都走 `POST /assistant/chat` + `AssistantChatReq.courseware`：

1. 讲课页悬浮「问 AI 老师」（`DraggableAssistantFab` → `AssistantChatPage(coursewareContext)`）：就当前知识点提问 / 求讲解；
2. **课堂练习环节 `SectionPractice`**：点「出题」让 AI 出一道题、学生口头答、教师代录对 / 错、答错时 AI 给分级提示（`hint_level` 经 `extra` 透传）。

用户进一步要求「完全删除课堂练习环节的『出题 / 提示』功能」。经 AskUserQuestion 确认范围＝**端到端全删**（讲课端组件 + 编辑页「添加练习」入口 + `CoursewarePracticeBlock` 数据模型 + `section.practice` 字段），而非仅摘掉 AI 按钮留空壳。

**关键判定**：课堂练习环节本质是纯 AI 出题 / 提示，删它不影响入口 1（浮标）。后端动作键 `courseware_generate` / `courseware_hint` / `quiz_judge` 仍被浮标使用，**不删**。故本次只动前端，后端零改动。

## 删了什么（仅前端）

- **讲课端组件**：`section_practice.dart`（`SectionPractice`）、`section_practice_parts.dart`（`PracticeQuestionPrompt` / `PracticeAction` / `PracticeNotice`）、`section_practice_edit_block.dart`（`SectionPracticeEditBlock` 编辑块）、`courseware_practice_block.dart`（`CoursewarePracticeBlock` 模型）。
- **演示页挂载**：`courseware_present_widgets.dart` 的 `PresentStage._buildBody` 移除 `hasPractice` 分支与 `SectionPractice` 渲染；空态文案 / 步骤去掉「课堂练习」；`PresentStage` 去掉不再使用的 `courseware` 字段。
- **编辑入口**：`courseware_section_edit_dialog.dart` 移除 `SectionPracticeEditBlock`；`editor_section_list.dart` 移除 `s.practice != null` 的「课堂练习」分类分支。
- **数据模型**：`courseware_section.dart` 移除 `practice` 字段、`_resolvePractice`、`copyWith`/`toJson` 中的 `practice`；`assistant_courseware_context.dart` 移除 practice 专用的 `sectionId` 与 `extra`（`hint_level` 透传，仅被本功能使用）。
- **测试**：删 `courseware_practice_test.dart` / `courseware_practice_block_test.dart`；`courseware_present_page_test.dart` 去 `practice` 夹具与「渲染 SectionPractice」用例；`file_size_guard_test.dart` 注释补记。

## 不删（保留）

- 讲课现场「问 AI 老师」浮标（`courseware_present_page.dart` 的 `DraggableAssistantFab` → `AssistantChatPage(coursewareContext)`），仍走 `courseware_generate` / `courseware_hint` / `quiz_judge` + `AssistantChatReq.courseware` 通道。
- 后端动作键与 `AssistantChatReq.courseware` 契约全部保留。

## 行为变更

- 课件环节内容块从「素材 / 场景 / 练习」收为「素材 / 场景」。
- 编辑器不再提供「添加练习」入口；课件模型不再有 `practice` 字段。
- 老课件若仍含 `practice` 字段，前端加载时静默忽略（不再解析），退化为「只有话术」空态——不再有不可见 / 半残的练习块。

## 验证

- `flutter analyze`：无新增问题（仍 2 条 info，在无关文件 `test/scene_library_associate_dialog_test.dart`，既存）。
- 相关 `flutter test`：课件演示页 / 编辑器 / 中心屏 / 文件规模护栏全绿（44 passed）。
- 后端未改动；结构化出题（`/tasks/generate`）与浮标助手通道不受影响。

## 取号

本分支 `docs/adr/` 最大号 = **0085**（`0083` 在并行 figlib 分支、未并入本分支）；顺延取 **0086**。
