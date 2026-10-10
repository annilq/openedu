# 02: SceneSpec 形态改造（后端产出 + 前端渲染，端到端）

**What to build:** 把 SceneSpec 从「inputs 大杂烩 + controls/narrative/outputs/title/editable + figure 引用」精简为 `{kind, points, edges}`；交互参数与引导文案收归 `SCENE_LIBRARY` 的 kind 外壳；前后端同步切换，CI 保持绿。这是整案的核心切片，跨前后端一次落地。

**Blocked by:** 01（图库源须已是 DB，供 `default_scene_from_figure` 取几何）

**Status:** ready-for-agent

## 后端
- `SCENE_LIBRARY` 的 reflection 外壳承载：`axisAngle/axisX/axisY` 初值、默认 `controls`、`narrative`（原 `REFLECTION_SEED` 对应字段上移）。
- `default_scene_from_figure` 从 `figure_library` 表取 points+edges 注入新 SceneSpec，不再读代码 `FIGURES`。
- `scene_spec_for_read` / `fuse_scene_spec` 产出 `{kind, points, edges}`，不再含 inputs/controls/narrative/outputs/title/editable/figure 引用。

## 前端
- `reflection_scene_data.dart`：从 spec 顶层读 points/edges；轴初值/controls/narrative 按 kind 从 `SCENE_LIBRARY` 外壳取（替代从 spec 读 + `buildReflectionSceneSpec` 硬编码）。
- painter 按 points+edges 画多边形（闭合/开折线/多部件均可）。
- `house` 仅作极端兜底（无 points 时）。

## 为什么是单切片
拆成「后端 expand / 前端 switch」两票会在合并窗口期让后端出新形、前端仍读旧形 → 红。故作为一条垂直切片一次落地，保持 CI 绿。

## 验收
- [ ] 后端融合链路产出新形态 `{kind, points, edges}`，旧字段（inputs/controls/narrative/outputs/title/editable/figure）不再出现。
- [ ] `SCENE_LIBRARY` reflection 外壳含 axis 初值/controls/narrative。
- [ ] `default_scene_from_figure` 从 DB 取几何注入，不依赖代码 `FIGURES`。
- [ ] 前端解析改读顶层 points/edges + kind 外壳；`buildReflectionSceneSpec` 不再硬编码 controls/narrative。
- [ ] 同一份新 SceneSpec 渲染结果与旧版视觉一致（多边形 + 对称轴 + 翻转 + 引导文案来自外壳）。
- [ ] `house` 仅极端兜底。
