# 04: 画板 UI（编辑态）+ 工具栏预设 + 保存端点

**What to build:** 教师/用户可在画板上手绘图形顶点、放置或拖动对称轴、翻转预览；点工具栏预设快速放置标准图形；保存写入图库。对称判定纯视觉，图库不存任何 axis 属性。

**Blocked by:** 01（保存端点依赖图库表）, 02（编辑态渲染依赖新 SceneSpec 几何 + kind 外壳交互）

**Status:** ready-for-agent

## 编辑态（复用 `ReflectionSceneWidget`）
- 拖顶点改 points；放置/拖动对称轴；翻转预览（与播放态同一 painter）。
- 工具栏预设（square/triangle/parallelogram…）点击即落到画板，仅提供顶点（无 axis 属性）。

## 保存
- 新增 `POST /scene-library/figures`：写入 `figure_library`（`is_builtin=false`），分配 `key` 返回。
- 画板产出的几何用假仓库/端点断言保存内容（points/edges 完整、key 已分配）。

## 验收
- [ ] `ReflectionSceneWidget` 编辑态：可拖顶点、放/拖对称轴、翻转预览。
- [ ] 工具栏预设点击即落画板（仅顶点，无 axis 字段）。
- [ ] `POST /scene-library/figures` 写入用户行，返回分配 key；points/edges 完整。
- [ ] 图库行无任何 axis 属性（对称纯视觉）。
- [ ] 画板产出经断言保存内容正确。
