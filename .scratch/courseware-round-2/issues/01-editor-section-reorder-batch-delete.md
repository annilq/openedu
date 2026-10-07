# 01: 编辑器环节拖拽重排 + 批量删除

Parent: docs/specs/teacher-courseware-round-2.md（ADR-0067 第二轮 · 编辑器方向）

**What to build:** 课件编辑页里，教师能拖拽环节卡片改讲解顺序、能多选后批量删除，且步骤条「n/N」实时跟随；改完重开课件顺序与删除结果都持久化。首轮已有 `updateSections`（整体覆盖写 sections 数组），本轮把「改序」从删了重建升级为拖拽，并补批量删除。

**Blocked by:** None（can start immediately）。

**Status:** done

**Done note (2026-10-??):** 实现 `editor_section_list.dart`（新 widget，~290 行，避 400 行）+ 改 `courseware_editor_page.dart`（重排/批量删回调 + 新动作行「开始讲课」移出 40px trailing 槽，修复 45px 溢出）+ 新 `courseware_editor_page_test.dart`（4 测试）。`flutter analyze lib/features/courseware` = 0 issues；T01 4 测试 + 既有 present(13)+practice(1) 全绿，零回归。发现并修正：`AppTopBar.trailing` 是 40 宽单图标槽，全文按钮「开始讲课」不能塞进去（根因 45px 溢出），改放备课行主操作位。

- [ ] 拖拽卡片到新位置后，步骤条与「n/N」计数立即更新，无需刷新。
- [ ] 重排后调 `updateSections` 以重排后的数组写入；重开课件 / 重新读取，顺序保持一致。
- [ ] 进入多选模式可选中若干环节；批量删除从列表移除它们，步骤条计数同步更新。
- [ ] 批量删除结果持久化，重开课件不再出现被删环节。
- [ ] 全程不引入 Material 系控件（可点区走 `AppFocusableAction` 或其派生）；编辑页及相关 widget 单文件 ≤400 行（ADR-0058）；`presentation/` 不 import `*/data/`（R4 棘轮）。
- [ ] 后端若无现成整体覆盖写能力则补之，但归属仍走 `core.guard`；测试用 FastAPI TestClient + 临时 SQLite，断言「发送重排数组 → GET 返回同序」「批量删除 → GET 数量正确」。
- [ ] 前端 widget 测试（关代理单进程）断言拖拽后步骤条更新、批量删除后计数正确，且 1920×1080 / 1366×768 / 1024×768 三档不溢出。
