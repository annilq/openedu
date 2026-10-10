# 图库 DB 化 + 画板设计 + SceneSpec 几何化

> 来源：ADR-0083（本轮权威决策，冲突以它为准）。
> **[INDEX.md](INDEX.md)**：依赖链 + 用户决策锚点。tickets 是垂直切片。
> 本地 `.scratch`（gh 未认证，未建 GitHub issue）。每张 ticket 含 What to build / Blocked by / Status / 验收。

## Problem
当前场景库的几何事实源 `FIGURES` 是后端 Python 常量，由构建期脚本 `gen_figures.py` 生成前端 `figures.dart` const，并由 parity 测试 `test_frontend_figures_are_not_stale` 锁双源一致。用户希望**自己在画板上设计图形顶点并入库**，且项目本就依赖 Python 服务（离线论点不成立），parity 锁只是双源副产物——应把图库搬进 DB，并让渲染不再依赖图库（SceneSpec 自带几何）。

## Solution
- 图库搬进 `figure_library` 表（仅几何：key/label/points/edges/note/is_builtin），11 个内置图形作种子入行，用户行由画板保存写入。
- SceneSpec 精简为 `{kind, points, edges}`：移除 inputs 大杂烩、controls/narrative/outputs/title/editable、`figure` 引用键；交互参数（axisAngle/axisX/axisY 初值）与引导文案收归 `SCENE_LIBRARY` 的 kind 外壳。
- 运行时渲染零图库依赖：`SceneSpec` 自带几何 + kind 外壳提供交互 → 渲染器；图库只在画板/画廊创作 UI 打开时按需 `GET` 一次、用完即弃、不缓存。
- 对称轴判定纯视觉（拖轴 + 翻转演示），图库/SceneSpec **不存任何 axis 属性**。
- 退役 `gen_figures.py`、`figures.dart` 生成物、`test_frontend_figures_are_not_stale`，以及代码 `FIGURES` 常量。

## 用户故事（节选）
- 作为教师，我能在画板上拖顶点、放/拖对称轴、翻转预览，点工具栏预设快速放置图形，保存后该图形进入图库并可被复用。
- 作为学生，我拿到一份场景，可以自己拖对称轴、看翻转，判断图形是否对称——无需系统告诉我答案。
- 作为系统，内置 square/triangle/parallelogram 等预设与用户自定义图形同结构存储；渲染同一份 SceneSpec 走同一条 `SceneInterpreter` 链路。
- 作为维护者，改图形只需改 DB（或画板），不再跑生成脚本、不再守 parity 双源锁。

## 实现要点
- 后端：新增 `figure_library` 表+迁移（种子 11 条）；`GET /scene-library/figures` 改读 DB；新增 `POST /scene-library/figures`（画板保存）；`default_scene_from_figure` 从 DB 取 points+edges 注入；`SCENE_LIBRARY` reflection 外壳承载 axis 初值/controls/narrative。
- 前端：`ReflectionSceneData` 解析改读顶层 points/edges，轴初值/controls/narrative 按 kind 从外壳取；`buildReflectionSceneSpec` 不再硬编码；`ReflectionSceneWidget` 增加编辑态（拖顶点/轴/翻转）；画廊按需拉取不缓存。

## 测试决策
- 渲染主接缝（输出侧）：喂新形 SceneSpec dict → 断言按 points+edges 画多边形、轴初值/引导文案来自 kind 外壳、house 仅极端兜底。
- 图库持久化接缝（输入侧）：POST 断言入表内容与 key 分配；GET 断言返回 DB 行。
- 迁移接缝（必要）：旧形 scene_spec → 新形，断言几何不丢、edges 默认按顶点顺序、渲染无回归、快照不可变。

## Out of Scope
- 不引入「自动计算对称轴」算法（判定交还视觉）。
- 不做图库本地磁盘缓存（仅按需拉取用完即弃）。
- 不引入除 reflection 外的新 kind（bar_chart 等仍 unimplemented）。
- 不改动 `Question.scene_spec` 的历史语义（仅加兼容适配层，快照不可变）。

## Further Notes
- 见 ADR-0083「被推翻前提」：离线论点不成立、parity 锁可退役、无需作者标注 axis。
- 与 ADR-0074 §6 协调：`title` 每 KP 覆盖口径迁移到 kind 外壳（已无 title 字段）。
