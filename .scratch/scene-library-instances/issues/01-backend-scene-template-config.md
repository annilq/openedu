# T01 — 后端：`scene_template_config` 表 + 默认图形读写 + 库聚合 prune 标记

**Blocked by:** 无
**Status:** done

## What to build

1. `run_migrations` 幂等新增表 `scene_template_config(kind VARCHAR PK, default_figure_key VARCHAR NULL)`。
   - kind 即 `SCENE_LIBRARY` 注册表 key（如 `reflection`），不做外键（注册表非 DB 实体，避免耦合）。
   - `default_figure_key` 空 → 关联写 seed 时回落注册表 `figure=''` 空占位（与现状一致）。
2. `PUT /materials/scene-library/{kind}/default-figure` 写默认图形：`{default_figure_key}`，kind 稳定契约、
   只弃用不重命名；校验 kind 存在于注册表（否则 422）。
3. `GET /materials/scene-library` 的 `SceneLibraryItem` 透传 `default_figure_key`（空→`null`）。
4. 库聚合反查 `kp.scenes` 时补充 **prune 悬空标记**：关联某 kind 的 KP 若已不存在（被 `_prune_knowledge_points`
   级联清理），在 `SceneLibraryKpRef` 加 `kp_missing: bool`（默认 false）。聚合逻辑在反查时按 kp_id 探活。

## 决策锚点

- ADR-0073：注册表 `SCENE_LIBRARY` 仍只作结构种子源，不承载默认图形；`kp.scenes` 仍唯一事实源。
- ADR-0074 v4：场景服务端硬编码；本 ticket 不引入任何"创建场景"端点，只管 kind 级默认图形 + 聚合。
- 无新增关联表：关联由 `kp.scenes` 的 `kind` 隐式表达（T04 写 seed）。

## 验收

- [ ] 幂等 DDL：`run_migrations` 连跑两次无错；首启动无回填。
- [ ] `PUT …/default-figure` 写后 `GET …/scene-library` 的 `default_figure_key` 透传正确；非法 kind 返 422。
- [ ] 库聚合对已被 prune 的 KP 标 `kp_missing=true`，且不影响其余关联展示。
- [ ] ruff 通过；`test_scene_templates.py` 现有断言（含 `scenes` 透传）不回归。
- [ ] 现有 `SceneLibraryKpRef` 字段向后兼容（新增字段可空/有默认）。
