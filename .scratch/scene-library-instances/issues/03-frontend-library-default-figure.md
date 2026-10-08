# T03 — 前端库详情：演示图形画廊 + 默认标记 + 「新增场景」提醒

**Blocked by:** 01
**Status:** ready-for-agent

## What to build

1. `scene_library_view` 顶部「新增场景」按钮：**不调用任何写端点**，点击即弹开发者提醒
   （toast/引导文案：「新场景类型请在后端 `SCENE_LIBRARY` 注册表配置并随前端渲染器发版，请联系开发者」）。
   —— 落实 ADR-0074 v4「场景服务端硬编码、前端只提醒」。
2. `scene_library_detail_view` 每个 kind 详情层：
   - 展示该 kind 的图形画廊（复用 `ReflectionFigureGallery`，图形集来自 `scene_figures.py` 经注册表暴露），
     当前 `default_figure_key` 高亮标「默认」。
   - 提供「设为默认」调用 T01 的 `PUT /materials/scene-library/{kind}/default-figure`。
   - `default_figure_key` 读自 `GET …/scene-library` 的 `SceneLibraryItem`。

## 决策锚点

- ADR-0073 边界③：图形顶点来自 `scene_figures.py`，库只存 key，不复制几何；注册表不预填 figure。
- ADR-0074 v4 §1：场景服务端硬编码，前端「新增场景」仅提醒开发者，不自由创建。
- ADR-0074 v4 §2①：库成「kind + 演示图形」唯一管理面；默认图形只作 seed（T04 关联时注入）。

## 验收

- [ ] 点「新增场景」弹开发者提醒、无网络写调用、不产生 kind。
- [ ] 库详情展示图形画廊 + 默认高亮；「设为默认」写后 `default_figure_key` 更新并持久化（刷新仍在）。
- [ ] 图形画廊复用现有组件，不重复实现；顶点不落库。
- [ ] `flutter analyze` 0 issue；相关 widget 测试覆盖「设为默认」与「新增场景提醒」。
