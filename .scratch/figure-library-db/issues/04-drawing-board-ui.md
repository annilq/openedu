# 04: 画板 UI（编辑态）+ 工具栏预设 + 保存端点

**What to build:** 教师/用户可在画板上手绘图形顶点、放置或拖动对称轴、翻转预览；点工具栏预设快速放置标准图形；保存写入图库。对称判定纯视觉，图库不存任何 axis 属性。

**Blocked by:** 01（保存端点依赖图库表）, 02（编辑态渲染依赖新 SceneSpec 几何 + kind 外壳交互）

**Status:** done

## 编辑态（复用 `ReflectionSceneWidget`）
- 拖顶点改 points；放置/拖动对称轴；翻转预览（与播放态同一 painter）。
- 工具栏预设（square/triangle/parallelogram…）点击即落到画板，仅提供顶点（无 axis 属性）。

## 保存
- 新增 `POST /scene-library/figures`：写入 `figure_library`（`is_builtin=false`），分配 `key` 返回。
- 画板产出的几何用假仓库/端点断言保存内容（points/edges 完整、key 已分配）。

## 验收
- [x] `ReflectionSceneWidget` 编辑态：可拖顶点、放/拖对称轴、翻转预览。
- [x] 工具栏预设点击即落画板（仅顶点，无 axis 字段）。
- [x] `POST /scene-library/figures` 写入用户行，返回分配 key；points/edges 完整。
- [x] 图库行无任何 axis 属性（对称纯视觉）。
- [x] 画板产出经断言保存内容正确。

## 落地记录
- **T04-A（后端，`cbc657c`）**：`POST /materials/scene-library/figures` + `scene_service` 校验/分配 `user_<hex>` key；10 条后端测试。
- **T04-B/C（前端，本次）**：
  - `reflection_scene_painter.dart`（新，259 行）：从 `reflection_scene.dart` 抽出的公共 painter + 几何工具
    （`clipHalfPlane`/`foldVertex`/`isAxisymmetric`/`reflectionFrame`）；`showHandles` 画顶点手柄。
    `reflection_scene.dart` 因此从 567 → 438 行（棘轮只降，安全）。
  - `reflection_scene.dart`：新增 `editing` / `onPointsChanged`；编辑态可拖顶点、拖空白移轴（`GestureDetector`，
    `shared/` 下不受 `no_bare_gesture` 约束）；编辑态状态条**不报「是不是轴对称」**（决策 2）。
  - `reflection_scene_board.dart`（新，240 行）：`ReflectionSceneBoard`（工具栏预设→落画板、起名、保存）
    + `ReflectionSceneBoardDialog.show`（ShadDialog，钉宽 460）。
  - `material_repository(.dart/_impl.dart)`：`createFigure(...)` → `POST /materials/scene-library/figures`。
  - `scene_library_view.dart`：新增「图形画板」入口。
  - `test/reflection_scene_board_test.dart`（新，319 行，9 测试全绿）：预设落板 / 拖顶点 / 拖轴 / 保存载荷 /
    拖后保存 / 空态禁用 / 不报结论 / 弹窗关闭 / 页面入口。
- **踩坑**：`showShadDialog` 默认 `useRootNavigator: true` → 弹窗渲染在根 Navigator 的 Overlay；
  `ShadToaster` 必须装在 Navigator **之上**（生产由 `ShadAppBuilder` 兜），否则弹窗内 `AppToast.show`
  抛「Could not find ShadToaster」→「保存成功→onBack 关弹窗」走不到。测试脚手架已改成同构
  （`CupertinoApp.builder` 里包 `ShadToaster`）。
- **验证**：`flutter analyze` = No issues found；全量 `flutter test` 505 passed（唯一失败
  `analytics_charts_test.dart` 为既存、与本轮无关）；文件规模棘轮通过。
