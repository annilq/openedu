# 01: 后端 scene_template_config 表与默认图形读写

**What to build:** 后端新增一张轻量持久化表 `scene_template_config(kind PK, default_figure_key)`，把「kind 级默认图形」从 `scene_templates.py` 里的代码常量变成可写、可落库的配置；并通过 `run_migrations` 幂等建表（无 Alembic）。`GET /materials/scene-library` 的 `SceneLibraryItem` 透传每个 kind 的 `default_figure_key`（空则回落注册表 `figure=''` 空占位，行为同现状）；新增 `PUT /materials/scene-library/{kind}/default-figure` 写默认图形（`kind` 稳定契约、只弃用不重命名）。注册表 `SCENE_LIBRARY` 仍只作结构种子源，不承载默认图形。这是 §7「kind 级默认图形管理」的数据底座，也是 T03 前端画廊读写的前提。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `run_migrations` 幂等建 `scene_template_config`（kind 主键 + default_figure_key 可空）；老库重跑不报错、不丢数据
- [ ] 新增模型 `SceneTemplateConfig`（SQLModel），归属走全局（非 per-teacher，kind 是全局契约）
- [ ] `GET /materials/scene-library` 返回每个 `SceneLibraryItem.default_figure_key`；`default_figure_key` 为空时回落空字符串
- [ ] `PUT /materials/scene-library/{kind}/default-figure` 接收 `default_figure_key` 并持久化；重复写覆盖；`kind` 不存在时按结构种子源兜底创建配置行
- [ ] 注册表 `SCENE_LIBRARY` 不被改为事实源，仍只读；`figure=''` 中性种子保持
- [ ] 现有场景库聚合测试 `test_scene_templates.py` 不受影响；快照不可变回归仍绿

**决策锚点：** ADR-0073（注册表只作结构种子源、scenes 唯一事实源、快照不可变）、ADR-0074 §3/§7（默认图形经 seed 注入 KP 实例、不构成 live binding）；`default_figure_key` 引用 `scene_figures.py` 的 key，不复制顶点。
