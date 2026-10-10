# ADR-0083：图库 DB 化 + 画板设计 + 视觉判定 + SceneSpec 几何化

状态：草案（v1——综合 2026-10 多轮设计走查后的锁定版）

修订轨迹：
- 本 ADR 综合 `how` skill 走查（场景数据流转）+ 后续 4 轮问答的全部锁定决策。
- 前身讨论中曾主张「图库放代码、离线优先、parity 锁保双源一致」；经用户逐条反驳后**全部反转**，见 §背景「被推翻的旧前提」。
- 接续并修正 ADR-0073 / 0074：本 ADR 改动 `SCENE_LIBRARY` 的角色边界（从「含 controls/narrative 的完整 SceneSpec 种子」降级为「仅交互外壳」），并新增图库持久化表。

## 背景

`how` skill 走查确认了场景数据的当前链路：`KnowledgePoint.scenes` 是唯一事实源（落库 SceneSpec 数组），`SCENE_LIBRARY` 注册表（代码常量，作者辅助）提供按 kind 的默认结构，`scene_figures.py` 的 `FIGURES` 是手写几何事实源（构建期生成前端 `figures.dart` const，运行时兜底缺模板）。

用户提出的核心诉求与决策：

1. **希望自己在画板上设计图形顶点并入库**——这是「图库 DB 化」的直接动机（非工程师通过 UI 增删/改图形）。
2. **轴对称图形可由用户视觉判断**：拖轴 + 翻转演示，自己看两侧是否重合，无需任何 `axis_count` / `is_axisymmetric` 属性判定。
3. **特殊图形（正方形/平行四边形/三角形…）做成画板工具栏预设**，点击即落到画板、入库。
4. **`SCENE_LIBRARY` 仍需保留**：不同场景类型默认交互不同（轴对称需要对称轴控件），它作为「按 kind 的交互外壳」仍必要。
5. **`SceneInterpreter` 通过画板与 input 直接渲染**——同一渲染器既是播放器也是编辑画板。
6. **去掉本地缓存、减少复杂度**：运行时渲染根本不碰图库，图库只在创作 UI 按需拉取。
7. **`SceneSpec.inputs` 大杂烩重构为通用 `points` + `edges`，并删除 `controls` / `narrative` / `outputs`**。
8. **`title` / `editable` 一并清掉**（`REFLECTION_SEED:34-80` 当前仍带这两个字段）。

### 被推翻的旧前提（明确记录，避免后人回归）

- 「离线优先，所以图库必须构建期生成 const」：**不成立**。app 整体本就依赖 Python 后端（出题/AI/题库全走 API），画廊只是「不额外发一次取图形请求」，并非真离线。图库 DB 化不破坏任何离线契约。
- 「parity 锁（后端 `FIGURES` ↔ 前端 `figures.dart` 双源逐字一致）是必须的」：**它是双源架构的副产物**。入库后前端改为运行时按需拉取，双源消失，parity 锁可退役（见 §实施要点 5）。
- 「`axis_angles` 必须由画板设计者显式标注，否则算法会把平行四边形『修好』成有轴」：**不成立**。既然对称判定改为纯视觉（不读属性），根本不存在「自动算轴」这条路径，也就没有算法篡改教学意图的风险。

## 决策

### 1. 图库（几何）迁入 DB，作为可编辑源

新增 `figure_library` 表，几何（顶点 + 边）成为持久化、可经 UI 编辑的一等资产：

- 列：`id`(PK)、`key`(稳定唯一契约)、`label`、`points`(JSON `none_as_null=True`，`[[x,y],...]` 归一化 0..1)、`edges`(JSON `none_as_null=True`，`[[i,j],...]` 顶点索引对)、`note`(nullable)、`is_builtin`(bool，区分内置预设与用户行)、`created_by`(nullable)。
- 内置 11 个图形（现 `scene_figures.py:FIGURES`）作为 `is_builtin=True` 种子行迁移进表；用户在画板设计的图形作为 `is_builtin=False` 行。
- **图库只存几何，不存任何 axis 字段**（彻底契合「视觉判定，不要属性」）。
- `default_scene_from_figure` / `extract_scene_inputs` 按 `key` 查 DB（`figure_by_key` 改查表），契约（按 key 匹配）不变。
- `GET /scene-library/figures`（`router.py:155`）改为读 DB。

### 2. 对称轴判定改为纯视觉，移除全部 axis 属性

- 图库记录**不含** `axis_angles` / `axis_count` / `default_axis_angle`（验证：`reflection_scene_data.dart:90-103` 运行时 `FigureShape` 本就只消费 `defaultAxisAngle`，`axisAngles/axisCount` 仅残留在生成物数据类里，运行时从不读——印证移除安全）。
- 「是否为轴对称、有几条轴」完全由用户在画板上**拖轴 + 翻转**自己看，不阅卷、不机器判定。
- 若未来仍存在「正方形有几条对称轴」类**机器阅卷题**，正确答案落在**题目自身的答案字段**，而非图库（图库不再断言对称数）。

### 3. 特殊图形做成画板工具栏预设

- 正方形/平行四边形/三角形/风筝/字母等做成工具栏形状原语，点击即生成一条图库记录（或预设本身是 `is_builtin=True` 行）并落到画板。
- 预设只需提供 `points` + `edges`；对称由用户看，无需任何 authored axis 值。
- 原手写 11 个图形整体重表达为「内置预设 + 用户自定义行」，无需为任何一个手填 axis。

### 4. `SCENE_LIBRARY` 保留为按 kind 的交互外壳

- 角色重新界定：从「含 `controls`/`narrative` 的完整 SceneSpec 种子」降级为「**仅交互外壳**」——每种 kind 声明其默认交互参数与引导文案。
- 现存 `REFLECTION_SEED`（`scene_templates.py:34-80`）改造为「reflection 外壳」：承载 `axisAngle=90` / `axisX=0.5` / `axisY=0.5` 的**交互参数初值**（注意：这是用户交互初值，非几何，不入 SceneSpec）、`controls` 默认（play/scrub）、`narrative` 默认引导文案、**不含** `points`/`edges`/`figure`/`outputs`/`title`/`editable`。
- `get_builtin_scene` / `instantiate_builtin` 仍返回深拷贝（进程级共享常量防写脏）；但返回结构改为「外壳」，不再含几何与已删字段。
- 不入库、不运行时编辑（ADR-0073 红线保留：注册表是作者辅助，渲染/出题永不回查）。

### 5. `SceneSpec` 几何化：重构 `inputs` → 顶层 `points` + `edges`，删除 `controls`/`narrative`/`outputs`/`title`/`editable`

新 SceneSpec 形状（与 `REFLECTION_SEED` 旧形对照）：

| 旧（`inputs` 大杂烩） | 新 | 说明 |
|---|---|---|
| `inputs[axisAngle/axisX/axisY]` | — | 交互参数初值，移入 `SCENE_LIBRARY` kind 外壳（决策 4）；运行时用户拖，不入数据 |
| `inputs[figure]` | — | 图库仅创作期用，放置时把几何拷进 scene；SceneSpec **内联几何、不引用 key**（决策 6） |
| `inputs[points]` | 顶层 `points: [[x,y],…]` | 升级为一级几何字段 |
| — | 顶层 `edges: [[i,j],…]` | **新增**，通用连接关系（支持非简单多边形 / 多部件 / 开折线 / 内部引导线） |
| `controls` | — | 移入 kind 外壳，渲染器按 kind 读 |
| `narrative` | — | 移入 kind 外壳，渲染器按 kind 读 |
| `outputs` | — | 本就恒 `{}`（不阅卷），**删除** |
| `title` | — | **删除**（见 §已知遗留，需与 ADR-0074 §6 协调） |
| `editable` | — | **删除**（编辑只发生在创作画板，运行时播放无需此标） |

```json
{
  "kind": "reflection",
  "points": [[0.3,0.7],[0.7,0.7],[0.7,0.45],[0.5,0.25],[0.3,0.45]],
  "edges": [[0,1],[1,2],[2,3],[3,4],[4,0]]
}
```

`edges` 的意义：当前顶点「默认按顺序连成闭合多边形」，表达力有限；显式连接关系后可画非凸、多部件、开折线，甚至把对称轴画成一条带样式的边——比「有序顶点」通用。

### 6. 轴初值/交互参数归 kind 外壳，scene 不各自存；`figure` 引用键不进 SceneSpec

- **轴初值**：`axisAngle/axisX/axisY` 初值只存在于 `SCENE_LIBRARY[kind]` 外壳（reflection 默认 90°/居中）；每条 scene 不再各自存——保持「几何通用」纯净。
- **`figure` 引用键**：SceneSpec **内联** `points` + `edges`，不再引用图库 `key`。图库仅创作期（画板/画廊）使用；渲染/出题/课件**不查库**——既满足决策 6「零图库依赖」，也满足 ADR-0073 快照铁律（改图库不影响已落库 `Question.scene_spec`）。

### 7. 去掉本地缓存，图库仅创作 UI 按需拉取

- 关键推论：`SceneSpec` 自带 `points`+`edges`，交互由 kind 外壳提供 → **运行时渲染零图库依赖、零缓存、零启动拉取**。运行时路径 = `SceneSpec(kind+几何)` + `SCENE_LIBRARY(kind 外壳)` → 渲染器。
- 图库只在**画板/画廊**这类创作 UI 打开时，按需 `GET /scene-library/figures` 拉一次（用完即弃，不缓存）。
- `figures.dart` 角色收缩为仅保留 `house` 单形状作最后兜底 const；`gen_figures.py` 与 `test_scene_figures.py`（parity 锁）**退役**。

### 8. `SceneInterpreter` 统一：渲染器 = 播放器 = 画板（编辑态）

- 同一 `ReflectionSceneWidget` / `_ReflectionPainter` 既做播放又做编辑（编辑态：可拖顶点 + 拖轴 + 翻转）。
- `SceneInterpreter`（`scene_interpreter.dart`）本就按 `kind` 从 SceneSpec 的 `points`/`edges` 渲染；画板只是该 widget 的编辑态，无需第二套渲染器。
- 画布边长 = `constraints.maxWidth`（天然正方形，ADR-0061 §O）。

## 与既有 ADR 的关系

- **扩展 ADR-0073**：`SCENE_LIBRARY` 从「完整 SceneSpec 种子」降级为「交互外壳」（决策 4），但**保留其红线**（注册表作者辅助、渲染/出题/课件永不回查、深拷贝）。
- **修正 ADR-0074**：① 图库从「只存 key、几何来自 `scene_figures.py`」变为「几何落 `figure_library` 表」；② `SceneSpec` 删 `title` 后，ADR-0074 §6「每关联 KP 场景条目标题可覆盖」机制需重新落点（见 §已知遗留 1）。
- **不影响 ADR-0061**：§O 画布正方形、§U 快照优先、视觉演示范式全部保留并强化（判定从属性改为视觉）。
- **显式排除**：图库做事实源 / live binding（ADR-0073 已拒）、注册表运行时编辑、前端自由创建 kind、parity 双源继续存在。

## 最终数据模型

```
图库(DB)        : figure_library { key, label, points[[x,y]], edges[[i,j]], note?,
                                   is_builtin, created_by? }              // 仅几何，无 axis
SCENE_LIBRARY(代码): kind → { axisAngle:90, axisX:0.5, axisY:0.5,         // 交互外壳
                              controls:{play,scrub}, narrative:"…" }      // 保留，不入库
SceneSpec(运行时) : { kind, points[[x,y]], edges[[i,j]] }                 // 极简，内联几何
SceneInterpreter : 统一 渲染器 = 播放器 = 画板(编辑态)
```

## 实施要点

### 后端

1. 新增 `figure_library` 表（幂等 DDL，`run_migrations`）：列见决策 1；11 条内置作 `is_builtin=True` 种子迁移。
2. `scene_figures.py`：保留 `figure_by_key` 但改查 `figure_library` 表，返回 `{points, edges}`（不再返回 axis 字段）；旧 `FIGURES` 常量可整体删除（或留作迁移源）。
3. `scene_templates.py`：`REFLECTION_SEED` 改为 reflection 外壳（去掉 `inputs` 包装、`points`/`figure`/`controls`/`narrative`/`outputs`/`title`/`editable` 中几何与已删项；保留 `axisAngle/axisX/axisY` 初值 + `controls` + `narrative`）；`get_builtin_scene`/`instantiate_builtin` 返回外壳。
4. `scene_fusion.py`：`default_scene_from_figure` 产出新形 SceneSpec（`kind` + `points` + `edges`），不再注入 `inputs[figure/points]`；`build_scene_spec_for_question` 调 `extract_scene_inputs` 命中图库 key 后查 DB 取几何；`apply_overrides` 同步改为合并顶层 `points`/`edges`（或移除，因不再有 inputs 覆盖语义）。
5. `router.py`：`GET /scene-library/figures` 改读 DB；评估新增 `POST /scene-library/figures`（画板保存用户图形）与 `PUT/DELETE` 写端点（kind 稳定契约，图形 key 由后端分配或用户指定且唯一）。
6. `schemas.py`：新增 `FigureLibraryItem` / 写请求 schema；`SceneSpec` schema 改为 `kind` + `points` + `edges`。

### 前端

1. `reflection_scene_data.dart`：
   - `ReflectionSceneData.fromSpec` 改为读顶层 `points`/`edges`（删除 `inputs` 遍历与 `figure` key 回退；`house` 仍作最后兜底 const）。
   - `axisAngle/axisX/axisY` 初值改从 kind 外壳取（需在前端建立与 `SCENE_LIBRARY` 同构的 kind 外壳常量，或后端随场景类型下发）。
   - `controlsPlay/controlsScrub` 改从 kind 外壳取；`narrative` 改从 kind 外壳取；删除 `editable`/`lockedAxisymmetric`（后者依赖已删的 `outputs.isAxisymmetric`）。
   - `buildReflectionSceneSpec` 删除硬编码 `controls`/`narrative`/`outputs`/`title`/`editable`，改为产出 `{kind, points, edges}`。
2. 新增**画板 UI**（复用 `ReflectionSceneWidget` 编辑态）：画布放顶点（拖拽）+ 拖轴 + 翻转预览 + 工具栏预设（square/parallelogram/triangle… 内联 points+edges）+ 保存写 `POST /scene-library/figures`。
3. `figures.dart`：收缩为仅 `house` 兜底 const；`gen_figures.py` 与 `test_frontend_figures_are_not_stale` / `TestFrontendBackendParity` 退役。
4. 画廊（创作 UI）：打开时 `GET /scene-library/figures` 拉一次，用完即弃（无本地缓存）。

## 迁移与兼容性

- 存量 `kp.scenes` / `Question.scene_spec`：旧形含 `inputs`/`controls`/`narrative`/`title`/`editable`。需写一次性迁移脚本把旧 spec 重写为 `{kind, points, edges}`（几何来自旧 `inputs[points]` 或 `figure` 解析；`edges` 默认按顶点顺序闭合），并填充缺失 `edges`。
- `figure_library` 首启动回填 11 条内置；存量 spec 引用的旧 `figure` key 仍可经回填映射到 `key`。
- ADR-0073 快照不可变回归、`kind` 稳定契约、ADR-0061 §O 画布正方形——均不动。
- 删除 `outputs.isAxisymmetric` 后，任何依赖该字段的阅卷/判定逻辑须改为「题目自身答案字段」或「纯视觉」，需排查调用点。

## Consequences

- 后端：图库可经 UI 持久化编辑（满足用户画板入库诉求）；`SCENE_LIBRARY` 精简为外壳；`FIGURES`/parity 双源退役。
- 前端：运行时零图库依赖、零缓存，渲染更轻；新增画板创作 UI；几何表达更通用（edges）。
- 约束：ADR-0073 红线不动；对称判定转纯视觉、不阅卷（除非题目自带答案）；图库仅创作期使用。

## 验证判据

- 画板设计一图形 → `POST /scene-library/figures` 入库 → 画廊可见 → 关联到 KP 后出题渲染出该图形（内联 geometry，不查库）。
- 旧 spec 迁移后渲染无回归（house 仅作极端兜底，不凭空出现）。
- 移除 `axis_count`/`isAxisymmetric` 后无调用点崩溃；对称判定纯靠拖轴翻转演示。
- `flutter analyze` 0 issue；场景库/出题/课件相关用例 + 全量不回归；parity 测试退役后无残留引用。
- `SCENE_LIBRARY` 外壳改动不影响已落库 `Question.scene_spec`（快照不可变回归绿）。

## 已知遗留

1. **`title` 删除与 ADR-0074 §6 的冲突**：原「每关联 KP 场景条目标题可覆盖」依赖 SceneSpec 的 `title`。删除后标题改由 kind 外壳默认（如「轴对称演示」）。是否需保留 per-KP 标题覆盖、若需则放在 `kp.scenes` 条目的独立元数据字段（不入 SceneSpec）——待定。
2. **`editable` 删除后的编辑入口**：运行时播放不再有 editable 标；编辑只发生在创作画板。需确认是否有「用户微调已下发场景」的需求，若有则走画板而非运行时标。
3. **`extract_scene_inputs` 命中后的几何来源**：确认旧 spec 的 `figure` key 在迁移后能被 `figure_library.key` 映射；未命中图库的题面（如「图书馆 86 本书」）仍返回 `None` 退化纯文本（不臆造）。
4. **写端点鉴权**：`POST/PUT/DELETE /scene-library/figures` 的权限（教师可建自己的、内置预设不可改）——待定。
5. **字母类图形（H/N/F/G）仍未进库**：「哪个字母是轴对称」类题仍无图，属 backlog（ADR-0061 §U）。

## Out of Scope

- 图库做事实源 / live binding（ADR-0073 已拒）。
- 注册表运行时编辑 / 版本化。
- 前端自由创建 kind（开发者工作流 + 前端渲染器发版）。
- 保留 parity 双源（本 ADR 明确退役）。
- 机器阅卷自动判定对称数（改由题目答案字段或纯视觉）。
