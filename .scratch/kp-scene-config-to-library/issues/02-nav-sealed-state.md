# 02: 场景库内钻取收敛为单一 sealed 状态

**What to build:** 场景库「列表 → 详情 → 编辑/关联」的钻取从散落的 `showDialog` 写法收敛到同一 `sealed` 导航状态（ADR-0059 导航状态单一约束）。库内不再出现并列的、各自维护的页面状态，所有入口只调单一 `_go(page)`。这是 T04（编辑已关联实例）、T05（关联知识点）的前置重构——两者都需要一个稳定的导航落点来打开 `KnowledgePointSceneEditor` 与关联 picker，避免引入并列状态导致漏清（且 analyze 照不出来）。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `scene_library_view` / `scene_library_detail_view` 的钻取收敛到单一 `sealed` 导航状态（如 `sealed SceneLibraryPage`）
- [ ] 所有入口（列表点详情、详情点实例卡、详情点关联）只经单一 `_go(page)`，无并列状态变量
- [ ] 移除 KP 行遗留的 `showDialog` 式散落写法（如有复用）；退路用 `maybePop` 不裸 `Navigator.pop`
- [ ] 扩展/复用 `frontend/test/teacher_nav_single_source_test.dart` 守卫导航状态单一（不新建测试文件）；`flutter analyze` 零 issue

**决策锚点：** ADR-0059（导航状态必须单一；并列状态⇒必漏清且 analyze 照不出）、ADR-0074 §导航（库内钻取须走单一 sealed 状态）。
