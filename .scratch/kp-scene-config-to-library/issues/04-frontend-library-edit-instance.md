# 04: 前端库详情页编辑已关联实例

**What to build:** 教师在场景库详情页点任一 `_InstanceCard`（已关联的知识点实例），经 T02 的导航落点打开 `KnowledgePointSceneEditor`（复用，传入该 KP 的 `id/name/subject/grade/semester/scenes`），改完经现有 `PATCH /materials/knowledge-points/{kpId}/scenes` 保存回 `KnowledgePoint.scenes`。这就是 ADR-0074 §1「编辑已关联实例」——把原先只能在 KP 行做的「写」，搬到库详情页，且不改事实源与渲染/出题/课件路径。

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] 库详情页 `_InstanceCard` 可点进 `KnowledgePointSceneEditor`（传全量 KP 上下文，含 `semester`）
- [ ] 编辑器内改 `figure/points`/轴参数后，`PATCH …/scenes` 写回，断言 `kp.scenes` 更新
- [ ] 编辑器内的图形画廊（`ReflectionFigureGallery`）与「未配置弹开发者指引」空态保留（位置从 KP 行迁到库内）
- [ ] 保存后库详情页列表即时反映新值（无需刷新整页）
- [ ] 渲染/出题/课件路径零改动（`scenes` 仍是唯一事实源）
- [ ] `flutter analyze` 零 issue；库详情「编辑实例」widget 测试覆盖打开+保存

**决策锚点：** ADR-0073（scenes 唯一事实源、渲染/出题/课件永不回查注册表）、ADR-0074 §1/§3（库详情页升级为可写配置入口、复用编辑器不重写）。
