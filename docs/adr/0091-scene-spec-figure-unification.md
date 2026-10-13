# ADR-0091：SceneSpec 与 Figure 统一——几何只留一份表达

状态：已实现（2026-10-13 · 6 票全 done，含 06 集成验证）

> 落地轨迹：`5bc77a8` Figure 类型 → `8a77d71` / `a2bfbee` / `0b752c3` 生产端改形 → `bb18c03` 消费端与端点
> → `0a2c3da` / `8375c62` / `60a5b2b` / `d67aa2f` 前端类型化 + 身份缺陷修复 → `1fe688f` 集成验证。
> 真跑迁移时开发库 10 份旧 spec 皆为「无几何的交互控件形」（无 figure/options），按纪律跳过不改写；幂等复跑一致。
> 验证：后端 825 passed / 2 skipped、前端 543 passed、`flutter analyze` No issues。

前提：**项目未上线**。本 ADR 的成立条件就是这一点——统一形状要改写存量快照，
上线后做就是数据迁移风险，现在做只是一次性开发期清理。

## 背景

同一个"几何"当前有**两种写法**，而它们本该是同一个东西：

| 写法 | 位置 | 形状 |
|---|---|---|
| 主几何 | `SceneSpec` 顶层 | `{kind, points, edges}`（ADR-0083 决策 5） |
| 选项几何 | `SceneSpec.optionGroup.items[]` | `{label, caption, points, edges}` |
| 通用图形 | `Figure` / 前端 `FigureShape` | `{key, label, points, edges}`（ADR-0089 v3） |

三种形状、两套解析路径。后端 `fuse_scene_spec` 用 `_GEOMETRY_KEYS` 覆盖**顶层**字段
（`scene_fusion.py:36,85`），前端 `SceneInterpreter` 用另一套解析**条目**（`scene_interpreter.dart:123`）。
同一份几何，读写两侧各有各的认识。

后果已经出现了一处实质缺陷：`optionGroup` 的条目**不带图库 key**（ADR-0083 决策 6），
于是画廊只能拿**展示名**当身份键（`scene_interpreter.dart:220`）：

```dart
final name = item.caption ?? item.label;
figure: FigureShape(key: name, label: name, ...)
```

教师改一次图形名，卡片角标映射与高亮就断；同名图形只认第一个（`:218`）。
这不是渲染 bug，是**身份缺失**——而身份缺失的原因正是"spec 不带 key"这条决策。

**决策 6 的真实目的 vs 实现手段**：目的是「运行时零图库依赖」（渲染不按 key 回查 DB）。
"spec 里不含 key"只是当时达成它的手段；手段顺带把身份也删掉了。二者可以分开：
**带 key，但渲染不消费 key**——零图库依赖这条不变量一动不动。

## 决策

### 1. 几何唯一载体 = `Figure`，`SceneSpec` 改为**持有** `Figure`

```python
# app/domain/figures.py（ADR-0089 v3，不变）
class Figure(SQLModel):
    key: str                      # 图库 key —— 身份 / 溯源 / 校验；渲染不消费
    label: str | None = None
    points: list[list[float]]
    edges: list[list[int]]

# app/domain/scene_spec.py（新）
class SceneSpec(SQLModel):
    """一次演示的快照：**kind 外壳 + 图形**（ADR-0083 决策 5 的几何部分收进 Figure）。"""
    kind: str
    figure: Figure | None = None          # 主图形（演示对象）
    options: list[Figure] | None = None   # 选项组（原 optionGroup.items）
    curated: bool = False                 # 课件编排语境（原 optionGroup.curated）
```

线上 JSON 形态（`Question.scene_spec` / `TaskQuestion.scene_spec` / `kp.scenes[]` / 课件环节 `scene` 同此）：

```json
{
  "kind": "reflection",
  "figure": { "key": "para", "label": "平行四边形", "points": [[0.3,0.4],[0.7,0.4],[0.82,0.7],[0.42,0.7]], "edges": [[0,1],[1,2],[2,3],[3,0]] },
  "options": [ { "key": "square", "label": "正方形", "points": [...], "edges": [...] }, ... ],
  "curated": false
}
```

`options` 非空时前端走图形画廊（既有行为不变），`figure` 为画廊弹窗的基础几何；
`options` 为空则渲染 `figure` 单场景。**两者至少有一个**，否则前端继续走 `AppEmptyState`。

### 2. 反转 ADR-0083 决策 6：从「spec 不含 key」收窄为「**渲染不消费 key**」

- 变：SceneSpec 现在**带** `figure.key` / `options[].key`。
- 不变：渲染仍只吃内联 `points/edges`，**不按 key 回查图库**、运行时零图库依赖（ADR-0083 决策 7）。
- 收益：身份回来了——画廊角标、高亮、去重都有稳定键；"教师改图形名"不再破坏映射。

⚠️ 这条反转**只**因为未上线才成立（需改写存量快照）。上线后不得再做。

### 3. 前端：`FigureShape` 加 `edges`，新建 `SceneSpec` 类

- `FigureShape`（`shared/domain/figures.dart`）补 `edges` 字段 → 与后端 `Figure` **同构**
  （此前前端无 edges，多边形按序闭合；补上是为统一，不是为新功能）。
- 新建 `shared/domain/scene_spec.dart`：`SceneSpec{kind, figure, options, curated}` + `fromJson`。
  **SceneSpec 此前在前端没有类**——只是 `Map<String, dynamic>`，解析散落在
  `ReflectionSceneData.fromSpec` / `SceneOptionItem.fromJson` 两处，这正是"两套解析"的根源。
- `ReflectionSceneData.fromSpec` 改为消费 `SceneSpec.figure`（轴初值仍归 kind 外壳，不进 spec）。

### 4. 删除清单（开发期清债，不留兼容分支）

| 删除 | 位置 | 理由 |
|---|---|---|
| `SceneOptionItem` | `scene_interpreter.dart:100-126` | 就是 `Figure` 的旧投影（`label/caption/points/edges` → `key/label/points/edges`） |
| `optionGroup` 键 | spec 形状、后端 `fuse_scene_spec`、前端解析器 | 改名为 `options`，形状即 `Figure` |
| `adaptSceneSpec` | `reflection_scene_data.dart:172` | 旧形（顶层 `inputs[]`）兼容层；统一的形状只有一个，适配层无对象 |
| `derivedFrom` | `scene_fusion.py:114` | `figure.key` 已说明来源（图库 / 自绘） |
| `_GEOMETRY_KEYS` 顶层覆盖 | `scene_fusion.py:36` | 覆盖语义改为「替换 `figure`」，不再是「覆盖顶层字段」 |

### 5. 存量快照：一次性幂等迁移，代码只认新形

- 覆盖范围：`question.scene_spec`、`taskquestion.scene_spec`、`knowledgepoint.scenes[]`、
  `courseware.sections[].scene`（课件环节的 spec 直接内嵌在 sections JSON 里）。
- 迁移规则：旧形顶层 `points/edges` → 包成 `figure{key,label,points,edges}`；
  `optionGroup.items[]` → `options[]`；`derivedFrom` 丢弃。
  **`key` 缺失怎么办**：旧快照本来没有 key → 用 `figureMatchingVertices` 的**服务端等价物**
  按顶点反查图库拿 key；查不到 → 生成 `user_<hash>`（前端 `kFallbackFigure` 只在渲染期兜底，
  **不参与落库**）。
- **不做 tolerant read**：统一后代码只认新形。双读分支正是"两套形状"的持久化，留着就白统一了。
- 未上线，数据可重建；迁移脚本仍须**幂等 + `--check`**（仓库既有补丁脚本纪律）。

## 类型与签名草图

```python
# app/domain/scene_spec.py（新）
class SceneSpec(SQLModel):
    kind: str
    figure: Figure | None = None
    options: list[Figure] | None = None
    curated: bool = False

def normalize_scene_spec(raw: Any) -> SceneSpec | None:
    """读路径唯一校验入口：dict → SceneSpec；非法 → None（前端走空态，不臆造）。"""


# app/features/materials/scene_fusion.py（改）
def fuse_scene_spec(kp_scenes, *, figure: Figure | None = None) -> SceneSpec | None:
    """几何覆盖语义改为**替换 figure**（原：覆盖顶层 points/edges）。"""

def scene_spec_from_figure(session, figure_key: str | None) -> SceneSpec | None:
    """盖章原语：key → SceneSpec{kind=reflection, figure=Figure}。"""


# frontend shared/domain/scene_spec.dart（新）
class SceneSpec {
  final String kind;
  final FigureShape? figure;
  final List<FigureShape> options;
  final bool curated;
}
```

## 模块边界

| 模块 | 改动 |
|---|---|
| `domain/scene_spec.py` | **新增**：`SceneSpec` + `normalize_scene_spec` |
| `domain/figures.py` | 不变（`Figure`，ADR-0089 v3） |
| `materials/scene_fusion.py` | 改：三个 producer 产 `SceneSpec`；删 `_GEOMETRY_KEYS` 与 `derivedFrom` |
| `materials/service.py` | 改：`kp.scenes` 读写经 `SceneSpec`；`list_figure_library` 不动 |
| `questions` / `review` / `tasks` service+router | 改：响应侧 `scene_spec` 用 `model_dump()`（形状变了，端点不变） |
| 前端 `shared/domain/figures.dart` | 改：`FigureShape` 加 `edges` |
| 前端 `shared/domain/scene_spec.dart` | **新增** |
| 前端 `scene_interpreter.dart` | 改：删 `SceneOptionItem`，`_entries()` 用真 key |
| 前端 `reflection_scene_data.dart` | 改：`fromSpec` 消费 `SceneSpec.figure`；删 `adaptSceneSpec` |
| 前端 `section_scene_figures_picker.dart` | 改：画板写 spec 的新形（`:222`） |
| 迁移脚本 | **新增**：一次性幂等快照改写 |

分层：`SceneSpec` / `Figure` 都在 `app/domain`（渲染契约），谁都能引；生产仍在 `features/materials`。
归属判定仍只走 `core.guard`；改 `features/*/service.py` 必跑 `tests/ai/`。

## 被否决的候选

- **保留双读（tolerant read）平滑过渡**：等于把两套形状永久化，与统一的目的相反。→ 否决（未上线）。
- **`Figure` 吸收 `kind`（SceneSpec 消失）**：图形不带交互意图（同一个房子在对折 / 平移下是同一形状），
  kind 是演示的属性不是形状的属性。→ 否决。
- **`SceneSpec` 消失、只留 `Figure` + 调用方自己传 kind**：kind 是稳定契约，散到调用方必然漂移。→ 否决。
- **后端保持 dict、只改形状（不建 `SceneSpec` 类）**：可行但会留下"后端 dict / 前端类"的第三次双源。
  唯一理由是省几处 `model_dump()`，不值。→ 否决（若实测调用点过多，可降级为此方案，见 Out of Scope）。

## 测试决策

- `normalize_scene_spec`：新形直读；旧形 → `None`（**不兼容**，断言它拒绝而不是静默适配）。
- 迁移脚本：**幂等**（跑两次结果相同）+ 旧形样本 → 新形 + 顶点反查拿到 key。
- 画廊角标：改图形的 `label` 后，角标映射**不变**（真 key 生效，这是本次修复的缺陷）。
- 快照不可变：改 `figure_library` 顶点 → 已落库 `figure.points` 不变。
- 接口级：`GET /questions`、任务详情、错题本下发的 `scene_spec` 是新形（沿袭 `test_questions_bank_scene.py`
  的接口级口径——只测 service 曾漏掉端点整段漏写）。
- 全量 pytest 与 `flutter analyze` 不回归；改 `features/*/service.py` 必跑 `tests/ai/`。

## Tickets（按依赖排序）

- **T01 · `SceneSpec` 类型 + `normalize_scene_spec`（后端）**：新增 `app/domain/scene_spec.py`，含单测。依赖无。
- **T02 · 生产端改形（后端）**：`fuse_scene_spec` / `scene_spec_from_figure` / `build_scene_spec_for_question`
  产 `SceneSpec`；删 `_GEOMETRY_KEYS`、`derivedFrom`、`optionGroup`。依赖 T01。
- **T03 · 消费端改形（后端）**：questions / review / tasks 的 service+router 响应侧 `model_dump()`。依赖 T02。
- **T04 · 存量快照迁移脚本（后端）**：幂等 + `--check`，覆盖 4 处存储；`key` 缺失走顶点反查。依赖 T01。
- **T05 · 前端 `FigureShape.edges` + `SceneSpec` 类（前端）**：新建 `shared/domain/scene_spec.dart`。依赖 T01（形状对齐）。
- **T06 · 前端消费端（前端）**：`ReflectionSceneData.fromSpec` 改读 `figure`；删 `adaptSceneSpec`、
  `SceneOptionItem`；`_entries()` 用真 key；画板写 spec 改形。依赖 T05。
- **T07 · 接口级测试 + 画廊角标回归 + 快照不可变（测试）**：依赖 T03、T04、T06。

## Out of Scope

- 新增可渲染 `kind`（ADR-0073：需开发者工作流 + 前端渲染器发版）。
- `Figure` 的定义变更（ADR-0089 v3 已定）。
- 若 T03 实测调用点过多导致 `model_dump()` 面过大，允许降级为「后端保持 dict 形状 + `normalize_scene_spec` 校验」，
  但**形状必须一致**（顶层 `figure`），仅省掉类型化。

## 后果

- 形状：几何从三种写法收敛为**一种**（`Figure`）；`SceneSpec` 从"裸 dict"变成有类型的契约，前后端同构。
- 行为：画廊身份从"展示名"变成真 `key`，修掉一个已存在的隐性缺陷。
- 代码：净删（`SceneOptionItem`、`adaptSceneSpec`、`_GEOMETRY_KEYS`、`derivedFrom`）；
  净增两个小类型（`SceneSpec` 前后端各一个）。
- 风险：**一次性改写存量快照**——仅因未上线而可接受；脚本须幂等且可 `--check`。
- 不变：快照不可变、`kind` 稳定契约、渲染零图库依赖、交互参数归 kind 外壳（`SceneShell`）。
