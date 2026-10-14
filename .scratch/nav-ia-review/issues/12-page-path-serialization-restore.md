# 12: 页面路径序列化与重启恢复

**What to build:** 教师当前所在页面（含下钻页与其关键参数）能序列化成一条稳定的路径字符串；应用重启或进程被回收后自动回到同一页面，而不是一律落到概览——审核草稿审到一半被打断，回来还在那一页。

**Blocked by:** 03（返回栈：恢复时要一并还原栈，否则按返回会跳到陌生页）

**Status:** done

## 验收

- [x] 每个页面类型能产出稳定路径字符串，并能从字符串还原（含学生 ID / 班级 ID / 场景类型等参数）
- [x] **认不出的路径一律回落概览**：不崩、不停在空白页、不静默停在半截状态
- [x] 切换页面时持久化当前路径；启动时若有则恢复
- [x] 恢复后侧栏高亮、返回栈与当前页三者一致，按返回不会跳到从未访问过的页
- [x] 学生端同样恢复上次所在页签
- [x] 登出清空已存路径（不得把上个账号的落点带进下个账号）
- [x] 单测覆盖：往返序列化、未知路径回落、参数缺失回落

## 落地要点（done）

- 序列化只动 `teacher_pages.dart`（toPath / teacherPageFromPath）、`storage_service.dart`
  （teacher_last_page_path / child_last_tab，clearAll 一并清）、`home_screen.dart`
  （initState 按角色恢复；_go/_goEntry/_back/_switchChildTab 切页即持久化）。不引入
  Navigator 栈或第三方路由库，ADR-0059 单状态不变。
- 复杂对象落点还原：EditStudentPage 持 UserModel → 以 studentId 落点 StudentDetailPage
  （详情页按 id 自取数，不复活编辑表单）；TaskReviewPage 近提交态刻意不复活 → 回落
  TaskListPage。其余页面参数（classId/className/kind/runId/initialTab）直达还原。
- 恢复语义用 `reset`（清历史）：重启后返回恒落概览，不会跳到从未访问过的页，与侧栏
  高亮 / 当前页三者一致。仅恢复「在哪一页」，不恢复页面内临时输入态。
- 取数（mutate provider）仍走 post-frame 回调，initState 内只动本地栈与读 storage，
  不违反「build 期禁止 mutate provider」。
- 顺手修绿 10/11 遗留导航测试陈旧断言：侧栏改名（学生 / 班级管理 → 班级）标签陈旧；
  StudentsScreen 容器默认「全部学生」视图 + IndexedStack 常驻导致「三(1)班」find 歧义，
  下钻前先切到「按班级」视图再点班级卡片。这些与 12 逻辑无关，属 10/11 既有测试债。

## 纪律

- **不引入 Navigator 栈与第三方路由库**；ADR-0059 单一导航状态不变。
- 路径只作**持久化与恢复**用，不得被当成跨页面通信通道（那有既有的意图通道）。
- 只恢复"在哪一页"，不恢复页面内的临时输入态（半填的表单不该被复活）。
