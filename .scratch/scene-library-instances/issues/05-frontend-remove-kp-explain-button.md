# T05 — 前端 KP 行移除「讲解」按钮

**Blocked by:** 04
**Status:** done

## What to build

- `knowledge_point_row.dart` 删除「讲解」`AppTextAction` 及其整条链路：打开 `KnowledgePointSceneEditor` 的
  调用、未配置确认框、`kp.semester` 传参等。保留「课件」入口。
- 库详情空态文案更新：当某 kind 的 `associated_knowledge_points` 为空时，显示「在场景库给某知识点关联此场景」
  （原「去知识点管理」改为「在场景库关联」）；开发者指引 relocation 到场景库。

## 决策锚点

- ADR-0074 v4 §5：必须在库具备「演示图形配置 + 关联知识点」能力后撤按钮（故 Blocked by T04），否则新 KP 进不了库。
- ADR-0045 / AppTopBar trailing 约束：删按钮后 KP 行交互更收敛，注意 trailing slot 仅 40px 单动作。

## 验收

- [ ] KP 行无「讲解」入口；「课件」保留且行为不变。
- [ ] 库详情空态文案指向「在场景库关联」；开发者指引在库侧可见。
- [ ] 删按钮后库能完整替代讲解配置（T03/T04 已覆盖图形/关联/标题）。
- [ ] `flutter analyze` 0 issue；`knowledge_point_row` 相关测试更新（无讲解入口断言）。
