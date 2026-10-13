# ADR-0089：场景感知的 AI 出题与答疑——删除文本抽取，Figure 作为通用渲染载荷

状态：已实现（**v3.1** · 2026-10-13 · 4 票全 done）

> 落地轨迹：`2a826bc` 目录投影 / 校验 / 盖章模块 → `2fc3cd1` 出题选项内嵌图形（结构化身份键 + 落库盖章）
> → `1ccb6d3` 答疑三层识别 + 删除题面猜测（含删 `scene_extract.py` 整族）→ `e291aa1` 前端选项行内渲染图形。

修订轨迹：
- v1：复用 `scene_spec.optionGroup` 存选项图形；`extract_option_group` 降级为存量回退。
- v2：删除文本抽取整族；图形内嵌进选项；答疑改模型判定。
- v3（本版）：`OptionFigure` → **`Figure`**（与"选项"解绑，它是**通用渲染载荷**）；
  答疑侧"要不要出图"补成**三层识别**（确定性门控 / 模型判定 / 后端校验），
  并**删掉 v2 的意图关键词门控**。
- v3.1：**ADR-0091 已让 `SceneSpec` 直接持有 `Figure`**（几何三种写法归一）。
  本 ADR 的 `Figure` 定义与三层识别**不变**，只是"SceneSpec 的几何子集"这句话变成了字面实现；
  ADR-0083 决策 6「spec 不含 key」被收窄为「渲染不消费 key」。

## 背景

知识点相关业务分散在场景（`kp.scenes` / `Question.scene_spec`）、题目、AI（出题 SubAgent + 伴学答疑）三条链路上。
接缝处有一处**实现方向错误**的机制。

### 文本抽取整族（`extract_option_group` / `extract_scene_inputs`）

- `extract_option_group`（`scene_extract.py:85`）：正则扫**选项文字** → 猜出图形 key → 图库取几何 →
  `optionGroup`。全-or-无，任一选项猜不出即整题无图。
- `extract_scene_inputs`（`scene_extract.py:50`）：正则扫**题干/提问** → 猜图形 key。两处消费：
  - `scene_fusion.build_scene_spec_for_question`（`:286`）——决定 overrides 与图库兜底；
  - `tutor/agent.py:_interactive_scene_for`（`:63`）——**学生答疑的场景卡就靠它**。

也就是说，「平行四边形是轴对称图形吗？」今天确实能出图，
但靠的是从这句话里**正则命中"平行四边形"四个字**（`test_scene_extract.py:35` 正是这条断言）。
换个说法（"这个图形有几条对称轴"、带上图、或教师自绘图形）就静默失效——
这就是「渲染依赖文本抽取」的代价：它能跑，但**不可靠、不可维护、不可扩展**。

> **更正 v1 的一处误判**：v1 称"AI 答疑后端零命中 `interactive_scene`"。实证是**已补上**——
> `tutor/agent.py:106-108` 会 `yield data_event(scene, extra={"type": "interactive_scene"})`。
> 缺口确实补了，但补在了正则上。本 ADR 要把它换成模型判定。

### 事实源仍不是"场景库"

ADR-0073 红线不变：渲染 / 生成只读 `KnowledgePoint.scenes`，**永不回查** `SCENE_LIBRARY` 注册表。
生成语境的"查场景" = 读 `kp.scenes`（`resolve_kp_scene`，`scene_fusion.py:42`）。

## 决策

### 1. 删除 `extract_option_group` 与 `extract_scene_inputs`（整族）

| 删除 | 位置 | 替代 |
|---|---|---|
| `extract_option_group` | `scene_extract.py:85` + `test_scene_extract.py:161-204` | 选项自带 `Figure`（决策 2） |
| `extract_scene_inputs` | `scene_extract.py:50` + 相关断言 | AI **显式发射** figure key（决策 4） |
| `scene_extract.py` 整个模块 | —— | 删空即删（无其它公开物） |

**为什么两个都删**：它们是同一套"从自然语言里猜图形"的机制，只留一个等于留一半的猜测逻辑。
出题侧由结构化输出给 key，答疑侧由模型判定给 key，**后端从此不再猜任何东西**。

**能力不回退**：旧路径里"`kp.scenes` 为空但题面点名了正方形 → 图库兜底出图"（ADR-0061 §U.3）
在新设计里变为"AI 发射 `figure_key=square` → 盖章出图"。同一个能力，驱动方从正则换成模型，
且**教师自绘图形第一次也能被引用**（旧词表只认内置 11 个）。

**保留但改语义**：`default_scene_from_figure`（`scene_fusion.py:92`）不删——它是"按 key 取权威几何
并产出纯几何 SceneSpec"的**盖章原语**，正是新链路要用的东西。建议**改名** `scene_spec_from_figure`
（"兜底/默认"语义已消失），4 处调用 + 测试一并改；若不改名则须改 docstring，别让后人以为是兜底。

`build_scene_spec_for_question` 保留，但**不再接收 `stem`/`options`**（那是给正则用的），
改为接收 AI 显式给的 `figure_key: str | None`。

### 2. `Figure`：与"选项"解绑的通用渲染载荷

v2 把它叫 `OptionFigure`、挂在选项上——**这个名字把概念说窄了**。图形不是选项的附属品：
同一个东西在答疑场景卡、课件画廊里都要用，它**只与渲染有关**。

**实证：前端早就有一个通用图形模型**——`FigureShape`（`frontend/lib/shared/domain/figures.dart:23`），
注释原文即「渲染层消费的图形模型（**画廊 / 画板 / 编辑器 / 选项组共用**）」。所以 v2 的命名
是后端单方面造了个更窄的投影，与前端既有模型错位。本决策把它对齐。

```python
# app/domain/figures.py（新，纯数据、零依赖）
class Figure(SQLModel):
    """一个**可独立渲染的平面图形快照**：图库行的几何投影。

    与它挂在哪里无关——它不是"选项的图形"，它就是"图形"。
    渲染只吃 ``points`` / ``edges``；``key`` 只作身份与溯源，渲染**不据此回查**。
    """
    key: str                     # figure_library.key —— 身份/溯源
    label: str | None = None     # 中文名（无障碍朗读 + 画廊标签）⚠️ 对齐图库行与前端的 label，不叫 caption
    points: list[list[float]]    # 归一化顶点（内联，离线可用）
    edges: list[list[int]]       # 顶点索引对；空 → 按序闭合


class QuestionOption(SQLModel):
    text: str                            # 选项文字：作答与评分的**唯一**依据
    figure: Figure | None = None         # 可选；有则渲染成平面图形
```

**字段对齐三处既有事实**（这是改名的实质收益，不只是换个词）：

| 字段 | 后端 `Figure` | 图库行 `figure_library` | 前端 `FigureShape` |
|---|---|---|---|
| 身份 | `key` | `key` | `key` |
| 中文名 | `label` | `label` | `label` |
| 顶点 | `points` | `points` | `vertices`（`[[x,y]]` → 元组） |

⚠️ 字段名统一为 **`label`**（v2 写的 `caption` 是错觉：图库行与前端都叫 `label`）。
`edges` 后端保留（与 `SceneSpec` / `SceneOptionItem` 同形状），前端 `FigureShape` 无此字段
（多边形按序连线），解析时忽略即可——**前端零新增类型，直接复用 `FigureShape`**。

**三个挂载点（同一类型，不同挂载）**：

| 挂载点 | 形态 | 本 ADR |
|---|---|---|
| 题目选项 | `options[].figure` | ✅ 本 ADR 落地 |
| 答疑场景卡 | `scene_spec{kind, points, edges}` 的几何部分 | ✅ 本 ADR 落地 |
| 课件环节 `optionGroup` | `SceneOptionItem{label,caption,points,edges}` | ⛔ Out of Scope（ADR-0076，遗留统一项） |

**与 `scene_spec` 的关系（关键澄清）**：`Figure` 是 `scene_spec` 的**几何子集被抽出来复用**。
`scene_spec = kind 外壳 + 一个主 Figure 的几何`，即 `scene_spec_from_figure(key)` 产出的就是
`{kind, **figure几何}`。两者不是竞争关系：`Figure` 回答"画什么形状"，`scene_spec` 回答"演什么场景"。

**关于 `key` 与 ADR-0083 决策 6**：决策 6 说"内联几何不带图库 key"——本 ADR **收窄**该条：
`Figure` **带** key，因为选项需要它做**全-or-无校验的输入**（哪个选项配了哪个图形）与**溯源**。
**渲染层行为不变**：仍只吃 `points/edges`。
（**ADR-0091 后续**：`SceneSpec` 改为直接持有 `Figure`，于是 spec 也带上了 key；
决策 6 进一步收窄为「**渲染不消费 key**」——带 key 只为身份，"零图库依赖"这条不变量没动。）

线上下发形态：

```json
"options": [
  { "text": "A. 正方形",     "figure": { "key": "square", "label": "正方形",   "points": [[0.28,0.28],[0.72,0.28],[0.72,0.72],[0.28,0.72]], "edges": [[0,1],[1,2],[2,3],[3,0]] } },
  { "text": "B. 平行四边形", "figure": { "key": "para",   "label": "平行四边形", "points": [[0.30,0.40],[0.70,0.40],[0.82,0.70],[0.42,0.70]], "edges": [[0,1],[1,2],[2,3],[3,0]] } },
  { "text": "C. 一般四边形", "figure": { "key": "quad_gen", "label": "一般四边形", "points": [[0.25,0.30],[0.80,0.40],[0.70,0.74],[0.30,0.66]], "edges": [[0,1],[1,2],[2,3],[3,0]] } }
]
```

其余设计要点不变：

- **`text` 永远存在**：它是判题与无障碍的依据。选项前缀（"A."）保留在 `text` 里
  （`normalize_options` 刻意不剥，答案同带前缀，剥离会破坏判题比对，ADR-0061 §T）。
- **`figure` 内联几何而非只存 key**：渲染契约只认 `{points, edges}`、零图库依赖
  （`SceneInterpreter` 已如此，`scene_interpreter.dart:139`）。存 key 再回查 = 把渲染重新绑回数据源，
  且离线课堂不可用。
- **`figure` 不带 `kind`**：演示场景的 kind 由**题目级** `scene_spec.kind` 决定——选项点开后弹的对折
  演示沿用题目的 kind 外壳。避免"每个选项各说一份 kind"的第二事实源。
- **整题全-or-无仍在，但挪到校验层**：数据形状允许逐项可空（混合题型），
  但**落库前校验**：一道 choice 题若只有部分选项带 figure → **全部丢弃 figure**，退纯文字。
  理由不变：半套图会把"这个选项没图"误导成"这个选项不是图形"。

**落库与兼容**：`options` 仍是同一个 JSON 列，只是元素从字符串变对象，**无 DDL 迁移**。
`tolerant read`：升级 `app/domain/structured.py:normalize_options`，
`str` → `{"text": s, "figure": null}`，`dict` → 校验后保留。判题路径改用 `option_texts(options) -> list[str]`。
开发期可选做一次幂等回填把存量 `list[str]` 行改写成 `list[{text}]`，**不做也能跑**。

### 3. 目录投影 / 校验 / 盖章：`figure_stamp.py`（回应"能否直接用场景库"）

**关联本来就在用，且不需要新关联**——`KnowledgePoint.scenes` 就是知识点↔场景的关联。
场景库页面上的 `associated_knowledge_points` 是**扫 `kp.scenes[].kind` 反查出来的**（`service.py:729-744`）：
数据流方向是 `kp.scenes` → 场景库，**库是派生视图，不是来源**。

所以分三句回答：

1. **关联可以直接用**：本模块不新增任何关联表、不新增列，它的输入就是 `kp.scenes` + `figure_library`。
2. **但场景库本身不能被生成直接消费**：
   - **方向反**：读派生视图 = live binding，ADR-0073 明确否决（改库配置会波及已生成内容）；
   - **粒度不对**：库给的是 kind 级**一个** `default_figure_key`（演示用默认图形），
     而选项需要的是**本题这一组**图形（如 4 个选项 4 个图形）；
   - **职责不同**：库是作者辅助 + 浏览聚合，没有"校验 key 合法性 + 盖章取几何 + 落快照"的能力。
3. **模块只装三件事**：**目录投影**（`kp.scenes` curated 图形优先 → 回落图库全量，产出给模型的
   `key + 中文名` 清单）、**校验**（key ∈ 目录）、**盖章**（key → 权威几何 → `Figure` / `scene_spec`）。

**模块命名**：v2 叫 `scene_options.py`——随 `Figure` 与选项解绑，它也不该叫 "options"。
改名 **`app/features/materials/figure_stamp.py`**（投影 + 校验 + 盖章）。
不并入既有的 `scene_figures.py`（222 行）：那文件是**内置种子 + `figure_geometry` 读取**，
把"改种子"和"给 AI 盖章"放一起，改种子的人会碰盖章逻辑。

**能否省掉这个模块？** 能——但只在只有一个消费方时。本 ADR 有两个消费方：
**出题**与**答疑**，两边需要**完全相同**的"投影 + 校验 + 盖章"逻辑。
若只做一边，直接调既有的 `list_figure_library` + `scene_spec_from_figure` 加五行校验即可，不必建模块。

### 4. AI 怎样识别"这次回答该不该带交互式图形"

这是本 ADR 唯一**新增**的智能环节。核心立场一句话：

> **模型有建议权，没有决定权。** 决定权在后端校验层——这与"防臆造"是同一条纪律：
> 模型可以提议，但几何必须来自 `figure_library` 单一权威，且必须落在目录内。

#### 4.1 粒度分工：两级问题分开答

| 层级 | 问题 | 谁答 | 依据 |
|---|---|---|---|
| **知识点级** | 这一类内容配不配演示？演示哪个场景？ | **数据**（教师配置的 `kp.scenes` + 图库） | 确定性、零成本 |
| **提问级** | **这一问**要不要出示图形？出示哪个？ | **模型** + 后端校验 | 需要理解语义 |

"知识点配了场景"只能说明**这一类**可演示，无法区分"问定义"和"问有几条对称轴"——
所以提问级判定不可省。反过来，提问级判定不该重新回答知识点级的问题
（目录已经由知识点算好了，模型只在目录里挑）。

#### 4.2 三层识别

**L0 · 确定性门控（不调模型，零成本）**——决定"值不值得问模型"：

1. 能否**解析出知识点**：课件上下文（`AssistantCoursewareContext.knowledge_point`）/
   题目上下文 / 学生当前知识点；都无 → 自由提问走**资料片段检索命中知识点**
   （沿用「开放语义检索命中 KP」口径）。
2. 该知识点能否**投影出非空图形目录**（`kp.scenes` curated 优先 → 回落图库全量）。

任一不满足 → **不发起微调用，也不发射场景卡**。

> ⚠️ **删掉 v2 写的"意图关键词门控"（对称轴 / 对折 / …）**。两条理由：
> ①它跟"后端不再从文本猜"的纪律自相矛盾——关键词仍然是猜，只是猜的是"要不要问"；
> ②`kp.scenes` 是**更强且零成本**的信号：它由教师显式配置，直接回答"这个知识点配不配演示"，
> 而关键词只能判断"这话听起来像不像图形问题"。
> 关键词在 L0 唯一残留的合理位置是**成本护栏**，而 L0 已经用"有无知识点"把成本管住了。

**L1 · 模型判定（一次结构化微调用）**：

```python
class SceneIntent(SQLModel):
    """这次提问要不要出示交互演示、演示哪个图形。"""
    should_show: bool = False      # 模型整体判断：这一问该不该出图
    figure_key: str | None = None  # 只能取目录里的 key
    rationale: str = ""            # 仅调试/轨迹用，不进正文
```

给模型的输入只有四样：**知识点名 + 图形目录（只给 `key` + `label`）+ 学生原话 + （有则）课件/题目上下文**。
**顶点绝不进 prompt**（防模型编坐标）。

判据写进 prompt（正面 + **反面例子必给**，反例是"该不该"这类判定的主要精度来源）：

- ✅ 出：理解这一问**依赖看着图形操作**——数对称轴、对折是否重合、数边/角、比面积、判断某图形是否属于某类。
- ⛔ 不出：问定义 / 问作业 / 程序性事务；图形只是举例而非对象；目录里没有能表达它的图形。
- 反例（明确列出）：「今天的作业是什么」「这个词怎么读」「帮我算 25×4」→ `should_show=false`。

**L2 · 后端校验与盖章（最终决定权）**：

1. `should_show` 与 `figure_key` **必须自洽**：`should_show=false` 或 `figure_key=None` → 不发射。
   两者冲突（说要出但不给 key，或说不出却给了 key）→ **取保守，不发射**。
2. `figure_key ∈ 目录`；图库有该行（`figure_geometry` 非 None）。任一不过 → 不发射。
3. 通过 → `scene_spec_from_figure` → `data_event(scene, extra={"type": "interactive_scene"})`。
4. **任何异常 → 不发射**，讲解正文照常（保留现有 try/except：场景卡是增强，绝不吞掉讲解）。

**kind 怎么定**：模型**不输出 kind**（它是稳定契约，不是模型的判断）。首版唯一 kind 是 `reflection`，
`scene_spec_from_figure` 恒给；多 kind 落地后由**目录投影时带上知识点 `scenes[0].kind`**决定——
这是扩展点，不在本 ADR 范围内。

**时序与成本**：沿用现状——场景卡 DATA 帧**先于正文**下发（学生先看到图形再读讲解）。
代价是**首个 token 延迟 + 一次微调用 RTT**（微调用很短：短 prompt + 3 字段 schema）。
若实测不可接受，可选优化：与讲解流并行、谁先到谁先发（前端卡槽是追加式 DATA 帧，晚到也能渲染，
只是不再"先于正文"）。**首版串行**。

**去重护栏**：同一会话内与上一条**已发射**的 `figure_key` 相同 → 不重复发射
（追问时反复弹同一个图会干扰阅读）。同 key 但间隔多轮 → 正常发射。

**课件场景（你举的例子）全链路**：`AssistantCoursewareContext` 带 `knowledge_point`
→ `courseware_hint` 意图 → tutor 拿知识点 → L0 过（有 KP + 目录非空）→ L1 模型判出 `para`
→ L2 校验盖章 → 前端弹出可拖轴的对折演示。

#### 4.3 出题侧不需要"识别"

出题本来就是结构化输出（`TaskSpec` + output_schema，ADR-0081）：模型的判断通过
**填不填 `figure.key`** 表达，无需另一次调用。只需两步：

1. 把 `options[].figure.key`（**只给 key，不给顶点**）加进出题 output_schema；
2. 把决策 3 的**可用图形清单**注入出题 prompt：
   "若本题选项可用图形表示，请为每个选项填 `figure.key`，只能从下列 key 中选：square / para / …"。

落库前（`tasks/service.py:546` 附近）校验 + 盖章 + 全-or-无。

#### 4.4 被否决的"识别"方案

- **让主讲解模型顺带输出结构化字段**：流式讲解第一个 token 就要下发，而结构化字段要等完整输出，
  场景卡必然落后于正文，破坏"先图形后讲解"。→ 否决（除非接受图后到）。
- **关键词/规则表（现状正则的同类）**：命中依赖措辞，自绘图形进不来。→ 否决（本 ADR 要删的就是它）。
- **只靠 `kp.scenes` 非空就出图**（不要模型）：粒度错——同一个知识点下"问定义"也会弹图。→ 否决。
- **让模型自由选任意图形名**（不约束在目录内）：必然出现图库没有的 key → 渲染不了或被迫兜底。→ 否决。

### 5. 复用的既有资产（不重造）

- `resolve_kp_scene`（`scene_fusion.py:42`）——场景唯一读取入口，不动。
- `scene_spec_from_figure`（原 `default_scene_from_figure`）——盖章原语，不动逻辑只改语义/名。
- `scene_spec_for_read`（`:118`）——读路径统一口径（快照优先），不动。
- `figure_geometry`（`scene_figures.py:204`）——几何权威读取，不动。
- `list_figure_library`（`service.py:804`）——目录的全量来源，不动。
- `FigureShape`（前端 `shared/domain/figures.dart:23`）——**前端通用图形模型已存在**，选项直接复用，零新增类型。
- `AssistantInteractiveSceneCard` / `assistant_card.dart`——前端卡槽已就绪，不动。

## 类型与签名草图

```python
# app/domain/figures.py（新，纯数据、零依赖；与前端 shared/domain/figures.dart 对称）
class Figure(SQLModel):
    key: str
    label: str | None = None
    points: list[list[float]]
    edges: list[list[int]]


# app/features/materials/figure_stamp.py（新模块）
class FigureRef(SQLModel):
    """给模型的目录条目：**只有 key + label**。

    刻意不是 Figure：类型层面就保证"顶点进不了 prompt"（Figure 带着几何，
    直接序列化进 prompt 就会漏；FigureRef 里根本没有几何字段）。
    """
    key: str
    label: str

def available_figures(session, *, teacher_id, kp) -> list[FigureRef]:
    """可用图形清单：kp.scenes curated 优先 → 回落 figure_library 全量。"""

def render_figure_catalog(figures: list[FigureRef]) -> str:
    """清单渲染进 prompt：只给 key + 中文名。"""

def stamp_figures(session, figures: list[Figure | None],
                  *, allowed: set[str]) -> list[Figure] | None:
    """按 figure.key 盖几何章。全-or-无：任一不合法 → 返回 None（调用方整体丢弃）。"""

def stamp_scene_spec(session, figure_key: str | None,
                     *, allowed: set[str]) -> dict | None:
    """答疑侧：key → scene_spec{kind,points,edges}；不合法返回 None（不发射）。"""


# app/features/materials/scene_fusion.py（改签名）
def build_scene_spec_for_question(session, *, teacher_id, subject, grade,
                                  knowledge_point, semester,
                                  figure_key: str | None = None) -> dict | None:
    """去掉 stem/options 形参（那是给正则的），改收 AI 显式给的 figure_key。"""


# ai/subagents/tutor/agent.py（替换 _interactive_scene_for）
async def resolve_scene_intent(provider, *, message: str, catalog: str,
                               kp_context: str) -> SceneIntent:
    """结构化微调用 → SceneIntent；未命中/异常 → SceneIntent()（默认不出图）。"""
```

## 模块边界

| 模块 | 改动 | 说明 |
|---|---|---|
| `domain/figures.py` | **新增** | `Figure`：通用渲染载荷，纯数据、零依赖 |
| `materials/figure_stamp.py` | **新增** | 目录投影 / 校验 / 盖章（出题 + 答疑共用） |
| `materials/scene_extract.py` | **整个删除** | 文本抽取整族 |
| `materials/scene_fusion.py` | 改 | 删正则依赖；`build_scene_spec_for_question` 改签名；`default_scene_from_figure` → 盖章原语 |
| `domain/structured.py` | 改 | `normalize_options` 支持 dict；新增 `option_texts` |
| `ai/subagents/question/parsers.py` | 改 | 解析 `options[].figure.key` |
| `tasks/service.py` | 改 | 注入清单 + 落库前校验盖章（`_valid_choice_options` 改用 texts） |
| `ai/subagents/tutor/agent.py` | 改 | `_interactive_scene_for` → 三层识别（L0/L1/L2） |
| `db/models/question.py`·`task.py` | 改类型 | `options: list[dict]`（同列，无迁移） |
| `features/questions|tasks|review` schemas | 改 | `options` 类型 + `QuestionResp`/`WrongQuestionResp`/`TaskQuestionEdit` |
| 前端 `question.dart`/`wrong_question.dart` | 改 | 选项模型持 `FigureShape`；`AppOptionTile` 渲染内联图形、点击弹对折演示 |

分层纪律：`figure_stamp` 属 `features/materials`（场景域），被 `features/tasks` 与 `ai/subagents` 单向消费；
`Figure` 属 `app/domain`（渲染契约），谁都能引。归属判定仍只走 `core.guard`。
改 `features/*/service.py` 必跑 `tests/ai/`（分层不变量 9）。

## 被否决的候选

- **并行数组 `options: list[str]` + `option_figures: list[...]`**：两个数组靠下标对齐，
  是同一事实的两份表达，必然漂移（编辑选项文字后图形错位）。→ 否决。
- **继续扩词表强化抽取**：零建模但仍是猜，且自绘图形永远进不来。→ 否决。
- **模型自由输出顶点**：必然错，且与 `figure_library` 单源冲突。→ 否决。
- **图形只存 `key`、渲染时回查图库**：把渲染重新绑回数据源，且离线课堂不可用。→ 否决。
- **保留 `OptionFigure` 命名**：与"选项"绑定，答疑场景卡与课件画廊要用同一个类型时会名不副实；
  且前端已有通用 `FigureShape`，后端造窄名会造成前后端概念错位。→ 否决。

## 测试决策

- `stamp_figures`：合法 keys → 几何正确内联、顺序 == 选项顺序；
  **部分有图 → 返回 None**（全-or-无）；未知 key / 图库无此行 → None。
- `normalize_options`：`str` → 包成 `{text, figure:null}`；`dict` 保留；判题用 `option_texts` 不变。
- 快照不可变：改 `figure_library` 顶点 → 已落库 options 内嵌几何不变。
- **L0 门控**：无知识点 → 不发起微调用（断言微调用 0 次）；目录为空 → 不发起。
- **L2 校验**：`should_show=false` / `figure_key=None` / 两者冲突 / key 不在目录 / 图库无行 → **均不发射**。
- **异常态**：微调用抛错 → 不发射**且讲解正文完整照常**（绝不吞讲解）。
- **去重**：连续同一 key → 第二次不发射。
- 接口级：`GET /questions` 与任务详情下发 `options[].figure`（沿袭 `test_questions_bank_scene.py`
  的接口级口径——历史教训是只测 service 会漏掉端点整段漏写）。
- 删除后：`test_scene_extract.py` 随模块删除；`test_scene_fusion.py`/`test_scene_fallback.py`
  改为测盖章原语；全量 pytest 与 `flutter analyze` 不回归。

## 迁移与删除清单

1. 删 `scene_extract.py` 及 `test_scene_extract.py`。
2. `scene_fusion.py`：删两处 import 与 `extract_*` 调用；`build_scene_spec_for_question` 去掉
   `stem`/`options` 形参；`default_scene_from_figure` → `scene_spec_from_figure`（改 4 处调用 + 测试）。
3. 新增 `app/domain/figures.py`（`Figure`）；`domain/structured.py`：`normalize_options` 升级 + `option_texts`。
4. 新增 `app/features/materials/figure_stamp.py`。
5. 出题侧：schema 加 `figure.key` + prompt 注入清单 + 落库盖章。
6. 答疑侧：`_interactive_scene_for` → 三层识别（L0 门控 + L1 微调用 + L2 校验）。
7. 前端：选项模型持 `FigureShape` + `AppOptionTile` 内联图形（点击弹 `ReflectionSceneDialog`）。
8. 可选：幂等回填存量 `options` 为对象形态。

## Out of Scope

- 新增可渲染 `kind`（开发者工作流 + 前端渲染器发版，ADR-0073）。
- 注册表运行时编辑 / live binding（ADR-0073 已拒）。
- 课件环节的 `optionGroup`（curated 多图画廊，ADR-0076）**不动**——本 ADR 只改题目选项；
  统一到 `Figure` 形状列为遗留。
- 多 kind 时的目录投影（首版恒 `reflection`）。

## 后果

- 后端：删掉一个模块与两个函数，新增两个模块（`domain/figures.py` 纯数据 + `figure_stamp.py`）；
  出题与答疑共用一套"投影 + 校验 + 盖章"。
- 前端：`options` 形状变更（有 tolerant 兼容路径一次过渡）；`AppOptionTile` 首次能画平面图形；
  **零新增图形类型**（复用 `FigureShape`）。
- 行为：图形命中从"看模型措辞的运气"变为"模型显式引用 + 后端校验"；教师自绘图形首次可被引用。
- 成本：答疑有知识点上下文时多一次结构化微调用（L0 门控挡掉无知识点的提问）。
- 概念：`Figure` 成为"可独立渲染的平面图形快照"的单一名字，前后端对齐（`FigureShape`）。
- 不变：`scenes` 唯一事实源、快照不可变、`kind` 稳定契约、渲染零图库依赖。
