# T02 — 导航：场景库内钻取收敛为单一 sealed 状态

**Blocked by:** 无
**Status:** done

## 完成记录（2026-10-08）

- `teacher_pages.dart` 新增 `SceneLibraryEditorPage(kpId, kpName, subject, grade, semester,
  initialScenes, back)`——编辑器收编为 `TeacherPage` 一个分支，经 `HomeScreen` 单一 `_go`
  switch 打开，不再由知识点行 `showDialog` 直接开。
- `home_screen.dart` 新增 switch 分支，编辑器作为页渲染（Align(topCenter)+ConstrainedBox
  maxWidth 560），`onBack: () => _go(back)` 回落，不裸 `Navigator.pop`。
- `KnowledgePointSceneEditor` 新增可选 `onBack`：页面态走 `onBack`、弹窗态回落 `Navigator.pop`
  （旧知识点行路径仍可工作，T05 移除按钮时一并清掉）。
- 测试：`teacher_nav_single_source_test.dart` 增 2 例（home_screen 单一 switch 处理编辑器页
  + `highlightFor` 对新页面态无并列高亮）。`flutter analyze` 0 issue，9 例全绿。

## What to build

- 库内「列表 → 详情 → 编辑/关联」钻取收敛到同一 `sealed` 导航状态（ADR-0059 单一导航状态约束），
  替换 KP 行散落的 `showDialog` 写法（避免并列状态漏清、analyze 照不出）。
- 提供场景库专用的 `sealed LibraryPage { list | detail(kind) | editor(kpId) }`（或并入现有导航枚举），
  所有入口只调单一 `_go(page)`；T03/T04 的详情/编辑页经此状态打开，不各自 `Navigator.push`。

## 决策锚点

- ADR-0059：导航状态必须单一，并列状态必漏清；非 push 路由页面禁裸 `Navigator.pop`。
- ADR-0074：库内钻取是配置入口的前置重构，T03/T04 依赖。

## 验收

- [ ] 库内所有钻取走单一 sealed 状态；无散落 `showDialog`/`Navigator.push` 直接开编辑器。
- [ ] 详情/编辑返回走注入回调或 `maybePop`，不裸 `Navigator.pop` 弹根栈。
- [ ] 新增对应导航测试（状态切换无并列残留）。
- [ ] `flutter analyze` 0 issue。
