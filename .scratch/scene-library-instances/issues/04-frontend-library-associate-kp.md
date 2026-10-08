# T04 — 前端库详情：关联知识点(1:N) + 标题编辑 + 解除关联

**Blocked by:** 01, 02
**Status:** ready-for-agent

## What to build

1. `scene_library_detail_view` 关联知识点列表：扫 `GET …/scene-library` 的 `associated_knowledge_points`
   （反查 `kp.scenes` 得），展示每个关联 KP；T01 的 `kp_missing=true` 项标「关联的知识点已不存在」+ 解除入口。
2. 点关联项 → 经 T02 sealed 状态打开 `KnowledgePointSceneEditor`（复用，传 `id/name/subject/grade/semester/scenes`），
   改图形/标题经现有 `PATCH /materials/knowledge-points/{kpId}/scenes` 保存（实现 v4 §2③ 标题按 KP 编辑）。
3. 新增「关联知识点」入口：前端过滤未关联该 kind 的 KP（教师域现有列表过滤即可，零后端改动），
   选一个 → 写一份 seed 场景（kind + T01 `default_figure_key` 注入 `figure/points` + 注册表中性轴参数）
   经 `PATCH …/scenes` 进该 KP。实现 v4 §2② 关联(1:N)。
4. 解除关联：从 KP 的 `scenes` 移除该 kind 条目（经 `PATCH …/scenes`）；prune 悬空项可解除（不级联删场景）。

## 决策锚点

- ADR-0073：`scenes` 唯一事实源；seed 存完整副本；渲染/出题/课件永不回查库配置；快照不可变。
- ADR-0074 v4 §2②/③：关联(1:N) 由 `kp.scenes` 的 `kind` 隐式表达，无新增关联表；seed 经现有 PATCH。
- ADR-0074 v4 §4：prune 悬空标 + 可解除，不级联删场景。
- T02 前置：钻取走 sealed 状态。

## 验收

- [ ] 库详情列出关联 KP；prune 悬空项标「已不存在」且可解除。
- [ ] 点关联项开编辑器改图形/标题后 `kp.scenes` 更新、渲染路径不变。
- [ ] 「关联知识点」能把未关联 KP 写 seed 进库并出现在列表（图形取自 `default_figure_key`，空则回落空占位）。
- [ ] 解除关联后该 KP 从库列表移除、其 `kp.scenes` 对应 kind 条目删除；场景不被级联删。
- [ ] `flutter analyze` 0 issue；库关联/编辑/解除相关测试覆盖。
