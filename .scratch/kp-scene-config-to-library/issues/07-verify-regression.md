# 07: 验证收尾——空态文案迁移与全量回归

**What to build:** 收尾 ticket：把库空态/开发者指引文案从「去知识点管理」统一改为「在场景库关联」（ADR-0074 §2 空态迁移），并跑全量回归确认这次 UX 整合零回归。覆盖 ADR-0074 验证判据全部条目。

**Blocked by:** 03, 04, 05, 06

**Status:** ready-for-agent

- [ ] 库空态（某 kind 的 `associated_knowledge_points` 为空）显示「在场景库给某知识点关联此场景」，不再指向知识点管理
- [ ] 开发者指引 `SceneDeveloperGuide` 仅在编辑器内未配置时弹出，位置正确
- [ ] `flutter analyze lib` 零 issue
- [ ] 场景库相关用例 + 全量 311 例不回归
- [ ] ADR-0073 快照不可变回归仍绿（设库默认后已落库 `kp.scenes` / `Question.scene_spec` 不受影响）
- [ ] 现有场景库聚合测试 `test_scene_templates.py` 不受影响

**决策锚点：** ADR-0073（快照不可变铁律）、ADR-0074 验证判据（去按钮后库可编辑/关联、默认图形只经 seed、KP 覆盖只动自身）。
