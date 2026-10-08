# 06: 前端 KP 行移除「讲解」按钮

**What to build:** `knowledge_point_row.dart` 删除「讲解」`AppTextAction` 及其整条链路（含「尚未配置讲解资源」确认框、`kp.semester` 传参、打开 `KnowledgePointSceneEditor` 的 `showDialog`）。保留「课件」入口。配置讲解的唯一入口从此是场景库（T04/T05）。必须在 T04/T05 落地后才能撤——否则新 KP 失去进库的入口。

**Blocked by:** 04, 05

**Status:** ready-for-agent

- [ ] 删除 KP 行「讲解」按钮、`AppTextAction` 及其打开编辑器的整条链路
- [ ] 删除「尚未配置讲解资源」确认框与 `kp.semester` 传参（该链路专属）
- [ ] 「课件」入口保留且行为不变
- [ ] 库详情页空态文案更新为「在场景库关联」（替代原「去知识点管理」），见 T07
- [ ] 无残留 `KnowledgePointSceneEditor` 从 KP 行调用的引用（`flutter analyze` 零 issue、grep 复核）
- [ ] 库详情「编辑/关联」两条路径已可独立覆盖原本「讲解」的全部能力

**决策锚点：** ADR-0074 §2（KP 行去掉讲解、保留课件、空态语义迁移到库）、ADR-0059（导航状态单一，不残留散落 showDialog）。
