# 06: 课堂练习在演示页可见（kind-free 下的练习内容块）

**What to build:** T03 去掉 `kind` 后，`practice` 类型与 `payload={qtype,count}` 失去归宿；同时现状 `SectionPractice` 部件已实现但 `PresentStage._buildBody` 根本没调用它（演示页里练习环节不可见）。本票闭合这个连带问题。

**取舍（实现前在本会话最终确认，不得静默丢弃已有练习课件）**
- **路线 A（默认，推荐）**：把"课堂练习"作为环节的**第四个可选内容块**（练习配置：题型 `qtype` + 题量 `count` + 提示 `hints`），由 `PresentStage` 显式调用 `SectionPractice` 渲染。编辑器 `CoursewareSectionEditDialog` 增加"练习"内容块编辑区。
- **路线 B**：本轮暂不支持练习环节——AI 起草停用 `practice` 产出；已存在的练习课件降级为"只有话术"空态（不得白屏/不得静默消失）。

**Blocked by:** 03（去 kind·expand 后方可重定练习归宿）。

**Status:** todo

**验收清单（路线 A 口径）**
- [ ] 练习作为环节可选内容块可配置（题型/题量/提示）
- [ ] `PresentStage` 显式渲染 `SectionPractice`（闭合当前演示页不可见 gap）
- [ ] 编辑器可给环节加/改练习配置并落库
- [ ] 若走路线 B：已存在的练习课件降级为"只有话术"空态、不白屏、AI 起草不再产 practice
- [ ] `flutter analyze` 0 issue；演示页练习环节测试全绿
