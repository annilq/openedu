# 06: 课堂练习在演示页可见（kind-free 下的练习内容块）

**What to build:** T03 去掉 `kind` 后，`practice` 类型与 `payload={qtype,count}` 失去归宿；同时现状 `SectionPractice` 部件已实现但 `PresentStage._buildBody` 根本没调用它（演示页里练习环节不可见）。本票闭合这个连带问题。

**取舍（实现前在本会话最终确认，不得静默丢弃已有练习课件）**
- **路线 A（默认，推荐）**：把"课堂练习"作为环节的**第四个可选内容块**（练习配置：题型 `qtype` + 题量 `count` + 提示 `hints`），由 `PresentStage` 显式调用 `SectionPractice` 渲染。编辑器 `CoursewareSectionEditDialog` 增加"练习"内容块编辑区。
- **路线 B**：本轮暂不支持练习环节——AI 起草停用 `practice` 产出；已存在的练习课件降级为"只有话术"空态（不得白屏/不得静默消失）。

**Blocked by:** 03（去 kind·expand 后方可重定练习归宿）。

**Status:** done

**取舍结论**：按**路线 A**（默认）实施——课堂练习作为第四个可选内容块，由 `PresentStage` 显式渲染 `SectionPractice`；路线 B 不采用。

**验收清单（路线 A 口径）**
- [x] 练习作为环节可选内容块可配置（题型/题量/提示）
- [x] `PresentStage` 显式渲染 `SectionPractice`（闭合当前演示页不可见 gap）
- [x] 编辑器可给环节加/改练习配置并落库
- [ ] 若走路线 B：已存在的练习课件降级为"只有话术"空态、不白屏、AI 起草不再产 practice（不适用，走路线 A）
- [x] `flutter analyze` 0 issue；演示页练习环节测试全绿

**实现备注（路线 A）**
- 新增 `CoursewarePracticeBlock`（qtype/count/hints）+ `copyWith`；`CoursewareSectionModel.practice` 透传（copyWith 用 `_unset` 哨兵支持显式清空，与 scene 同模式）。
- `PresentStage` 加 `courseware` 构造形参；`_buildBody` 空态判定由 `!materials && !scene` 扩展为 `!materials && !scene && !practice`；新增 `if (hasPractice) SectionPractice(courseware: courseware, section: section)` 显式渲染，闭合此前演示页练习环节不可见的 gap。
- 编辑器 `CoursewareSectionEditDialog` 在场景块后加 `SectionPracticeEditBlock`（独立文件 `section_practice_edit_block.dart`，ADR-0058 P4 子件独立）：`AppPickerField<String>` 选题型（choice/fill/calc/open）+ 题量/提示两 `AppTextField`；无练习显「添加练习」、有练习显「移除练习」。
- `SectionPractice` 改读 `widget.section.practice?.qtype`（迁离旧 `payload['qtype']`）。
- 测试：`courseware_practice_test` 新增「课堂练习编辑块」用例（添加/改题型/移除），`courseware_present_page_test` 新增「练习环节渲染 SectionPractice」用例（override `assistantRepositoryProvider` 防构建崩）。
- 验证：`flutter analyze lib/features/courseware` No issues；`courseware_practice_test` 8 passed；present/editor 合并跑全绿。
- ⚠️ `SectionPractice` 测试构建依赖真实 `assistantRepositoryProvider` → 演示页测试须 override 为 `_NoopAssistant`，否则 widget 测试崩（沿用 `courseware_practice_test` 既有 `_RecordingAssistant` 模式）。
