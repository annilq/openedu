# 03: 前端库详情页 kind 级图形画廊与默认图形标记

**What to build:** 教师在场景库 kind 详情层看到该场景的图形集（复用 `ReflectionFigureGallery` 的 11 图形），并能把其中一个标为 `default_figure_key`——库成为「场景 = kind + 图形集 + 默认图形」的唯一管理面，消除 ADR-0074 背景里说的「场景与图形割裂」。读取来自 T01 的 `GET /materials/scene-library` 透传 `default_figure_key`，写入调用 T01 的 `PUT /materials/scene-library/{kind}/default-figure`。默认图形只是种子（§7）：标记后立即持久化，但绝不回写已落库 KP 的 `scenes` / `Question.scene_spec`。

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] 库详情页 kind 层级渲染图形画廊（11 图形，引用 `scene_figures.py` 的 key，不复制顶点）
- [ ] 当前 `default_figure_key` 在画廊中高亮标记
- [ ] 「设为默认」动作调用 `PUT /materials/scene-library/{kind}/default-figure` 并乐观更新 UI
- [ ] 设默认后，已落库的 KP `scenes` 与题目快照不受影响（仅影响后续新关联 / 显式「重置为库默认」）
- [ ] 不维护 per-kind allow-list（11 图形全开放，§7 已明确）
- [ ] `flutter analyze` 零 issue；库详情相关 widget 测试覆盖读/写两条路径

**决策锚点：** ADR-0073 边界③（注册表不预填 figure，库只存 key）、ADR-0074 §7（默认图形=种子非事实源、仅设默认不裁剪可用集、保留 KP 可覆盖）。
