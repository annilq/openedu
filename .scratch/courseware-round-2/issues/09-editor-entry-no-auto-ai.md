# 09: 课件编辑器进入行为改造（T09 追认）

**What to build (追认):** 进入 `CoursewareEditorPage` 时不自动建课件——`_loadOrCreate` 只 `listCourseware` 不自动 `createCourseware`（避免空列表时自动跑 AI 起草 + 空白页无反馈）；新增 `_createFirst()`，仅用户点「新增课件信息」才触发 AI 起草。空态显示 `AppEmptyState(actionLabel:'新增课件信息', onAction:_createFirst)`；已有但空课件走「AI 重新起草」（同课件重起草）；两者均显式用户发起。

**Blocked by:** None.

**Status:** done

**Done note (2026-10-07, commit `e7c539f`):** 改动落 `frontend/lib/features/courseware/presentation/pages/courseware_editor_page.dart`。`courseware_editor_page_test` 增 T09 组 3 例（进入不自动建+显示按钮 / 点击触发生成+展示 / 已有课件直接展示不重起草），三件套 43 全绿，`flutter analyze` 0 issue。无对应前端 `ready-for-agent` ticket 的历史缺口已在此追认闭合。

- [x] 进入不自动 `createCourseware`，`_courseware==null` 显示「新增课件信息」空态
- [x] 用户点按钮才 `_createFirst()` 触发 AI 起草
- [x] 已有课件直接展示、不重起草（语义边界：无课件=新增+AI；已有空=重起草）
- [x] 测试覆盖进入 / 触发 / 已有三态，全绿
