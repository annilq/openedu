# ADR-0061：交互式图形讲解——知识点场景编写、出题融合与双模式求解

状态：草案（Proposed），待评审与实施排期。

数学题解析需要图形化 / 交互式讲解（例如四年级数学『平均数与条形统计图』中，拖动改变各组数据 → 条形实时变化、红色平均数线随之移动，直观建立『平均数是整体水平』的概念）。当前 `Question.explanation` 是纯文本、题卡用 `Text()` 渲染，AI 伴学讲解只有 markdown 气泡，全工程无任何图表 / 公式 / 动画渲染能力。本 ADR 确立「教师基于知识点编写基础交互演示 → 出题时融合题面输入 → 用户可改变量并执行分析」的三阶段方案，并定义声明式 SceneSpec、知识点 / 题目双存储、kind 注册表与「按 kind 内置求解」的纪律。

## 背景：四处理状缺陷

1. **讲解是纯文本，无图形能力**：`Question.explanation: str`（`app/db/models/question.py:36`），题卡解析用纯 `Text()` 渲染（`assistant_question_card.dart:140`）；tutor 气泡仅 `AppMarkdown`（`assistant_message_list.dart:251`）。全工程无 `flutter_math` / LaTeX、无 charts 库——数学式只能以 `$v=s/t$` 字面串呈现，更无交互图。
2. **知识点是自由文本且双口径**：`Question.knowledge_point: str` 与 `KnowledgePoint.name`（`app/db/models/material.py:145`）靠同名匹配，存在拼写漂移（ADR-0055 §背景缺陷 2：「两位数加减法」≠「两位数加法」）。交互讲解若直接堆在题上会重复 / 缺失。
3. **卡片协议无「下发图形参数」通道**：ADR-0042 确立 `DATA` 帧 + `kind` 分派，但 `actions.target` 是纯导航枚举，没有「把图形参数下发给前端自行渲染」的出口——须新增 `kind`，不能复用 `actions`。
4. **出题 / 答疑无离线 mock**（ADR-0039 立法目的）：讲解生成不能假设「模型一定能画对场景」，生成侧必须可降级。

## 决策

### 1. 三层解耦：声明式 SceneSpec + 知识点模板 + 题目实例

SceneSpec 只描述「画什么」，不写 Flutter 代码。核心字段：

- `kind`：选哪个渲染器（走注册表，非自由字符串）。
- `inputs[]`：可编辑的场景变量（如 `v`、`T`），含 `key/label/value/min/max/step/unit`。
- `controls{}`：时间轴控制开关（`play/pause/scrub/speed`）。
- `timeline[]`：叙事 / 标注关键帧（`{t, text}`）。
- `narrative`：讲解文案。

渲染器是声明式解释器，与场景内容无关——这就是复用发生的位置，而非场景本身。

### 2. 场景锚定知识点（模板），题目持有融合实例；不污染 `explanation`

- `KnowledgePoint.scenes: list[dict] | None`（JSON 列，沿用 ADR-0055 §10「快照不建外键」思路）：存教师编写的「基础交互演示」，含默认 `inputs`。一个知识点可被多题复用。
- `Question.scene_spec: dict | None`（JSON 列，可空）：是「融合产物」——引用 `ref_kp_scene` + 覆盖后的 `inputs` + `locked_answer`（本题正确答案）。
- **不把交互图塞进 `explanation` 纯文本**：避免与三处约束冲突——字段白名单只放行 4 字段（`features/tasks/service.py:1080`）、导出刻意剔除（`features/export/document.py:7`）、题卡 `Text()` 纯文本渲染。

### 3. 三阶段工作流：AI 起草 + 教师调参、生成时融合（非 AI 自由发明场景）

- **阶段① 编写（AI 起草 + 教师调）**：上传资料 → 知识点抽取（ADR-0055）→ **AI 基于知识点（名称 / 学科 / 年级 / 学期 + 关联资料片段，经 `retrieval.py:110` 按 `knowledge_point` 过滤召回）生成 SceneSpec 草稿**：从 `kind` 注册表选类型 + 默认 `inputs` + `controls` + `narrative`。草稿受 kind schema 约束 + 校验（ADR-0042 双登记口径），**仅对「可图形化」的知识点产出**（如运动 / 数线 / 面积模型 / 比例），不可图形化的 KP（如文言文词义）返回无模板；失败 / 不可图形化 → 无模板，教师可重生成或手动编。教师在预览中**调交互体验**（调 `inputs` 范围 / `controls` / `narrative`）后确认落 `KnowledgePoint.scenes`。
- **阶段② 生成（AI + 融合）**：出题时按 `knowledge_point` 精确匹配查对应知识点（`find_knowledge_point`，生成时 KP 已确定不漂移）→ 抽取本题输入值（`v` / `T` / 已知条件）→ 覆盖 KP 场景默认 `inputs` → 产出 `Question.scene_spec` + `locked_answer`。**出题侧 AI 角色收窄为「参数提取 + 绑定」，不是场景发明**——可靠性远高于让模型凭空画场景。
- **阶段③ 使用（学生 / 用户）**：打开题目场景，仍可改 `inputs`（`editable=true`）→ 执行分析流程求解；伴学讲解错题时场景经题卡内联（c1）与聊天内嵌卡（c2）两路呈现（见可行性分析 §C）。
- **数据依赖**：`KnowledgePoint.scenes` 必须先于题目生成存在（编写是上游），正好对齐用户「先上传资料、AI 起草并调好交互、再生成题」的顺序。

### 4. 融合算法：纯数据覆盖，不碰渲染

融合 = 取 KP 场景模板，用题面抽取的输入值覆盖 `inputs[].value`，保留 `kind` / `controls` / `timeline` / `narrative`，附 `locked_answer`。**不改变渲染逻辑**。若知识点无场景或抽取失败 → `scene_spec = null`，降级为纯文本讲解（不破解出题 / 答疑，契合 ADR-0039 纪律）。

### 5. 双交互模式：被动播放 vs 主动执行分析 / 求解

- **被动播放（体验）**：由 `controls{}` 驱动的播放 / 暂停 / 拖拽 / 倍速，展示概念动态——阶段①教师在调的正是这层。
- **主动执行分析（讲解落点）**：用户改完 `inputs` 后点「分析」，渲染器用当前 `inputs` 算 `outputs`、更新读数与讲解，并可与 `locked_answer` 对照验证。
- **区分本质**：`inputs[]` 定义「场景是什么」（场景级参数）；`controls{}` 控制「动画进行到哪」（时间轴进度，所有 kind 共享）。改 `inputs` 时重算 `T` / `maxS` 并把当前 `t` clamp 到新区间后重绘。

### 6. 求解按 kind 内置，不下发可执行表达式

`outputs` 的推导（如 `s = v·T`）由 `kind` 对应的渲染器**内置**，SceneSpec 只声明「哪些 `inputs` 可编辑、哪些 `outputs` 显示」。理由：零任意代码执行（安全）、可离线、前后端口径一致。禁止在场景里下发可执行表达式 / 计算公式——呼应 ADR-0042「不做通用 GenUI」，不把计算逻辑推到数据层。

### 7. 传输：新增卡片 `kind=interactive_scene`，复用 `DATA` 帧

- 讲解 / 题目解析下发交互场景走 ADR-0042 的 `DATA` 帧，新增 `kind=interactive_scene`；结构化数据走 `result`（含 `kind` + `inputs` + `controls` + `timeline` + `narrative` + `locked_answer` + `ref`）。
- 后端 `render.py#_KIND` 与前端 `AssistantCardKind` **双登记**（契约测试对齐，ADR-0042 §Consequences）；旧前端走降级卡（ADR-0042 §决策 4），不丢内容。
- 讲解正文仍走 `ASSISTANT_MESSAGE`（markdown），场景描述走 `DATA` 帧，避免被 `AppMarkdown` 当文本渲染。

### 8. 渲染：shared/widgets 落 SceneInterpreter，按 kind 分派

- 新建 `shared/widgets/scene_interpreter`（须满足「≥2 调用点、不 import features/」才进 `shared/`：题目解析卡、tutor 讲解卡、知识点复习卡均用），按 `kind` 分发到具体绘制器（如 `bar_chart_painter`）。
- 复用 `app_motion.dart` 的 `ConfettiBurst` 模式：`CustomPainter` + `AnimationController` + `AnimatedBuilder` + `reducedMotionOf`（`app_motion.dart:192-329`），减弱动画兜底已有。
- 配色 / 间距走设计令牌（`AppColors` / `AppText` / `AppSpacing`，ADR-0004 / 0014）；交互热区走 `AppIconAction` / `AppFocusableAction`（禁裸 `GestureDetector`，ADR-0046）；遵守卡片 760px 宽度（`assistant_message_list.dart:41,88-91`）与 ADR-0058 文件规模（单文件 ≤400 行、单文件 ≤3 个私有 widget、`App*` 前缀只给 `shared/`）。

### 9. kind 注册表与首个真实 kind = bar_chart（平均数与条形统计图）

- `kind` 取值走注册表（后端 `_KIND` + 前端 `AssistantCardKind` 同源，契约测试对齐，ADR-0042 §Consequences）。首个落地 kind = **`bar_chart`**——源于资料库真实入库的「四年级数学（上）·平均数与条形统计图」知识点（`KnowledgePoint.id = f24c1077ef85420d8756850cff49a650`，见 §E.1 候选词表）：给定若干组数据，画条形统计图并叠加、实时更新「平均数线」，直观诠释「平均数是移多补少后的整体水平」。后续 kind 按同一协议追加（见 §E.1）。
- `bar_chart` 字段草案：
  - `inputs` = `[{ "key":"data", "label":"各组数据", "value":[{"label":"小红","v":14},{"label":"小明","v":12},{"label":"小刚","v":11},{"label":"小军","v":15}], "min":0, "max":30, "step":1, "unit":"个" }]`（`data` 为数组型输入，`min/max/step/unit` 作用于每个 `v`；渲染器内置解析）。
  - `controls` = `{play, pause, scrub, speed}`：`play` 触发条形从 0 生长到目标高度的入场动画（`t:0→1`，条形高 = `v·t`），便于逐步揭示。
  - `outputs`（渲染器内置求解，不下发表达式）：`sum = Σv`、`count = n`、`mean = sum/count`；界面叠加红色虚线平均数线 + 数值标签。
  - `timeline` = `[{t:0.0,"text":"开始绘制各组条形"},{t:0.5,"text":"条形生长中"},{t:1.0,"text":"标出平均数线"}]`。
  - `locked_answer` = 本题所求（如 `{mean:13, unit:"个"}` 或 `{sum:52}`），供「执行分析」对照。
- 完整 SceneSpec 示例（基于该真实知识点，AI 起草草稿即此结构，教师微调后落 `KnowledgePoint.scenes`）：

```json
{
  "kind": "bar_chart",
  "title": "平均数与条形统计图",
  "inputs": [
    {"key":"data","label":"各组数据",
     "value":[{"label":"小红","v":14},{"label":"小明","v":12},{"label":"小刚","v":11},{"label":"小军","v":15}],
     "min":0,"max":30,"step":1,"unit":"个"}
  ],
  "controls": {"play":true,"pause":true,"scrub":true,"speed":true},
  "timeline": [{"t":0.0,"text":"开始绘制各组条形"},{"t":0.5,"text":"条形生长中"},{"t":1.0,"text":"标出平均数线"}],
  "narrative": "把 4 个同学的瓶子合起来（14+12+11+15=52），再平均分成 4 份，每份 13 个就是平均数。拖动任意一条形改变数量，看红色平均数线如何移动——它代表『移多补少』后的相等水平。",
  "outputs": {"mean":13,"sum":52,"count":4,"unit":"个"}
}
```

> 注：早期草案曾以 `linear_motion`（速度—时间—路程）作为举例占位；该 kind 仍属候选词表（§E.1），用于未来物理 / 行程类知识点，但首版不实现。

### 9.1 第二个 kind = reflection（图形的运动·轴对称）

- 源于真实知识点「图形的运动（轴对称）」（`KnowledgePoint.id = 357dd9129061452ea9ec35a881548f9c`）。四年级上轴对称单元核心是：认识对称轴、补全轴对称图形（找关键点 → 数格找对称点 → 连线）、理解「对称点连线垂直于对称轴且被对称轴平分」。
- 交互演示形态（核心：**单个图形沿内部对称轴对折**，而非整图镜像反转）：
  - **被动播放**：画布上呈现**一个完整的轴对称图形**（如小房子 / 风筝 / 箭头），图形内部画一条对称轴。点击播放，图形被轴划分为「静止侧」与「折叠侧」——**静止侧顶点保持不动**，折叠侧顶点**沿折痕翻折**（2D 投影：`沿轴分量 u 不变，法向分量 v' = v·cos θ`，θ:0→π：θ=0 在原位，θ=π/2 塌缩到轴线上，θ=π 跨过轴落到另一侧）。θ=π 时折叠侧盖到静止侧之上：若图形关于该轴对称，则**两侧完全重合**（演示「轴对称」定义）；否则错位（演示「这条线不是对称轴」）。⚠️ **只翻折一侧、另一侧保持静止**——这才是「沿折痕对折」的纸感；若把全部顶点一起镜像（整图绕轴反转），看起来是「旋转整图比对原图」，并非对折，属错误呈现（早期原型根因）。**面重合（非线段重合）**：图形**按对称轴裁剪成两个填充半区**（多边形对半平面裁剪，Sutherland–Hodgman），静止半 / 折叠半以两种填充色块（青 / 橙）半透明叠加；翻折后看「折叠半的面积是否完全覆盖静止半」——是面积重合，而非仅轮廓线重合。
  - **主动分析（讲解落点）**：① 旋转 + 平移对称轴，观察只有轴落在图形真正的对称线（方向 + 位置都对）时，翻折后两侧才重合（训练「找对称轴」，覆盖竖直 / 水平 / 斜轴等所有对比场景）；② 切换 / 构造不同图形，判断「是不是轴对称图形」。
- `reflection` 字段草案：
  - `inputs` = `[{ "key":"axisAngle", "label":"对称轴角度", "value":90, "min":0, "max":180, "step":1, "unit":"度(0=水平,90=竖直)" }, { "key":"axisX", "label":"对称轴水平位置", "value":0.5, "min":0.3, "max":0.7, "step":0.02, "unit":"比例" }, { "key":"axisY", "label":"对称轴垂直位置", "value":0.5, "min":0.3, "max":0.7, "step":0.02, "unit":"比例" }, { "key":"figure", "label":"图形", "value":"house", "options":["house","kite","arrow"], "unit":"预设" }]`（对称轴由「**角度 axisAngle + 中心点 (axisX,axisY)**」定义，可**旋转任意角度 + 平移**，覆盖所有对比场景；`figure` 为**单个完整图形**的预设名，渲染器内置其对称轮廓——首版预设 `house`/`kite`/`arrow`，后续可扩展为自定义顶点数组）。
  - `controls` = `{play, pause, scrub, speed}`：`play` 触发「对折」动画（θ:0→π，**仅折叠侧**沿折痕翻折，静止侧不动），`scrub` 可手动拖到任意折叠角度。
  - `outputs`（内置求解）：**是否轴对称判定**——θ=π 后程序化校验（把「折叠半」关于当前轴反射，其面积多边形是否完全落在「静止半」面积多边形内且面积相等，即面重合；等效实现：将图形全部基础顶点关于当前轴反射，逐点取与任一原顶点最近距离，最大距离 < 阈值即判定为两侧重合 / 轴对称），不硬编码；重合 / 不重合提示文字；轴偏离真正对称线时提示「这条线不是对称轴」。⚠️ **重合判定严格门控于 θ=π（即对折进度 100% = 对折角度 180°）**：折叠角必须 `θ = 进度 × 180°`，且仅在该端点、且「折叠半 vs 静止半」比对（**禁止**与折叠半自身反射像比对、或折叠仅到 90° 半边塌到轴线上就判重合）——否则会出现「进度未到 180° 就已重合」的错误（早期原型根因）。
  - `locked_answer`：`{isAxisymmetric:true, axisAngle:90, axisX:0.5, axisY:0.5}`（融合时附本题所求，如「判断下列图形是否轴对称」「画出对称轴」）。
- 完整 SceneSpec 示例（可直接落 `KnowledgePoint.scenes[0]`）：

```json
{
  "kind": "reflection",
  "title": "图形的运动（轴对称）",
  "inputs": [
    {"key":"axisAngle","label":"对称轴角度","value":90,"min":0,"max":180,"step":1,"unit":"度(0=水平,90=竖直)"},
    {"key":"axisX","label":"对称轴水平位置","value":0.5,"min":0.3,"max":0.7,"step":0.02,"unit":"比例"},
    {"key":"axisY","label":"对称轴垂直位置","value":0.5,"min":0.3,"max":0.7,"step":0.02,"unit":"比例"},
    {"key":"figure","label":"图形","value":"house","options":["house","kite","arrow"],"unit":"预设"}
  ],
  "controls":{"play":true,"pause":true,"scrub":true,"speed":true},
  "timeline":[{"t":0.0,"text":"展示轴对称图形与对称轴"},{"t":0.5,"text":"沿对称轴翻折"},{"t":1.0,"text":"两侧完全重合"}],
  "narrative":"这是一个轴对称图形，中间虚线是它的对称轴。点击播放，静止的一半不动，另一半沿对称轴翻折盖到这一半上——若两边完全重合，就是『轴对称』；只有真正的对称线（方向＋位置都对）才能让两边重合。旋转或平移对称轴，观察何时能对折重合。",
  "outputs":{"isAxisymmetric":true,"axisAngle":90,"axisX":0.5,"axisY":0.5}
}
```

> 该 kind 复用与 `bar_chart` 同一 `SceneInterpreter` 框架，差异仅在绘制器 `reflection_painter`；`inputs` 的数组型（`vertices`）与 `data` 同受渲染器内置解析约定。

#### 9.1.1 实现状态（Flutter 骨架，2026-10-04 落地）

- 渲染器已落 `frontend/lib/shared/widgets/scene_interpreter/`：
  - `reflection_scene.dart` —— `_ReflectionPainter`（`CustomPainter`）+ `_ReflectionSceneWidget`（stateful，`AnimationController` 驱动对折进度，复用 `reducedMotionOf` 兜底）+ `ReflectionSceneData`（与 SceneSpec JSON 解耦，可测试）+ 几何工具（半平面裁剪 / 折叠顶点 / 轴对称判定）。
  - `scene_interpreter.dart` —— `SceneInterpreter` 按 `kind` 分发（前后端双登记，见决策 7），未识别 kind 走 `AppEmptyState` 降级。
- 几何严格对齐已验证的 `prototypes/reflection_demo.html`：折叠角 `θ = 进度 × 180°`（重合仅门控于 θ=π）、静止侧（青）/ 折叠侧（橙）双填充半区、重合判定「折叠侧 vs 静止侧」而非自身反射。
- 令牌合规：描边走 `AppElevation.borderWidth/Hairline`、配色走 `AppBrutal`、控件热区走 `AppIconAction`（禁裸 GestureDetector）、空态走 `AppEmptyState`；`flutter analyze lib/shared/widgets/scene_interpreter/` 零 issue。
- `KnowledgePoint.scenes` / `Question.scene_spec` 存储 DDL：已于 2026-10-04 落地（启动期幂等 ALTER + 读写 + 迁移已对真实 `app.db` 验证），见 §G。
- 助手卡 `interactive_scene` 接入：已于 2026-10-04 落地（前后端双登记 + 前端渲染分派 + 测试），见 §G。
- 遗留（骨架未含）：① 三处消费方接线（出题解析卡 / 错题本 / AI 伴学讲解卡接入 `SceneInterpreter`）；③ 控制条 `Slider` 替换为 `ShadSlider` 贴合设计系统。

### 10. 公式渲染缺口：单独立项

全工程无 `flutter_math` / LaTeX，数学式只能以字面串呈现（`AppMarkdown` 不支持）。若场景需配公式，需另行引入公式渲染方案，**不在本 ADR 首版内**，与图形渲染解耦。

### 11. 题→知识点归一仍是前置依赖，但不在本 ADR 解决

`KnowledgePoint.scenes` 的复用价值依赖「题 → 知识点同名匹配」准确（ADR-0055 §背景缺陷 2 已点名拼写漂移）。本 ADR 复用 ADR-0055 的「待审知识点转正」机制保证同名对齐；更彻底的归一（别名表 / 合并）属后续议题。每题生成场景**不依赖**该归一（阶段②失败即降级），故不阻塞本 ADR 落地。

## 可行性分析（2026-10-04 增补）：为现有 RAG 知识点挂载默认讲解并在三处消费

> 用户现状：资料库已含学科 / 年级 / 知识点（`KnowledgePoint` 目录），希望「为 RAG 入库的知识点添加默认交互讲解案例」，使生成题目、错题本、AI 伴学讲解错题三处都能按题生成特定交互解析。以下为读代码后的可行性核查与落点。

### A. 现状事实核查（已读代码确认）

- **`KnowledgePoint` 现有字段**（`app/db/models/material.py:145`）：`id / parent_id / subject / grade / semester / name / status / source / created_at`。**无 `scenes` 字段、无 `embedding`**。知识点是家长私有目录行（唯一约束 `parent_id+subject+grade+semester+name`），不是向量。
- **「RAG 入库」的真相**：向量化发生在 `MaterialChunk.embedding`（`material.py:135`）；`KnowledgePoint` 本身**不进向量库**，而是在 `retrieval.py:110` 的 `retrieve(...)` 中作为**过滤维度**（chunk 带 `knowledge_point` 字符串标签）。即知识点**组织并限定** RAG 检索范围，但不入向量空间——场景应挂在 KP 目录行上，而非写进向量。
- **题 → 知识点关联**（`app/db/models/question.py:31`）：`Question.knowledge_point: str` **非外键**；出题时经 `find_knowledge_point(parent_id, subject, grade, semester, name)`（`features/materials/repository.py:155`）在作用域内**精确匹配**。因此「生成题目」这一步目标知识点是确定且精确的，融合查表**不漂移**——这是本方案可行性的关键支点（题面已知 KP，无需事后归一）。
- **三处消费方现状**：
  - 生成题目：出题管线产出 `Question`（带 `knowledge_point` 字符串），题目详情经题卡解析区渲染（`assistant_question_card.dart`）。
  - 错题本：错题经 `tasks` / `review` 持有原题引用（`features/review/repository.py:11` `list_due_wrong_questions`），错题卡走 `wrong_question_list`（`app/ai/subagents/query/render.py:37`）。
  - AI 伴学讲解：学生提问走 `tutor` subagent（`domain/tutor.py:104` `aexplain`），自由文本 → `ASSISTANT_MESSAGE`；错题列举走 `query` 的 `list_wrong_questions` 工具 → `wrong_question_list` 卡。讲解目前只有 markdown 气泡 + 题目卡，**无结构化场景通道**（新增 `interactive_scene` kind 即补此通道，见决策 7）。

### B. 结论：可行，且天然三层挂载

为知识点挂「默认交互讲解」= 给 `KnowledgePoint` 加 `scenes` JSON（模板，含默认 `inputs`）；三处消费时取该模板 → 融合题面输入 → `Question.scene_spec` → 各自渲染。与决策 2/3 完全一致，无需推翻，且因生成时 KP 已精确，不依赖题→知识点归一（决策 11）。

### C. 三处消费的可行性（含落点）

- **(a) 生成题目**：出题管线生成 `Question` 后调融合函数（查 `find_knowledge_point` → 抽题面输入 → 覆盖 `inputs` → 写 `Question.scene_spec` + `locked_answer`）。落点 `question/pipeline.py`（RAG 接缝旁，类比 `rag_context` 注入）。**可行，且不依赖归一**。
- **(b) 错题本**：错题持有原题（`Question`），渲染场景只需读 `Question.scene_spec`——**无需任何新关联**。落点：错题详情 / `practice_review_view` / 复习卡内联 `SceneInterpreter`。降级：无 `scene_spec` 时维持原纯文本解析。
- **(c) AI 伴学讲解错题**，两条路径：
  - **c1 题目卡内联**：讲解伴随某具体题（tutor 讲错题、或 `question` 卡展示）时，题卡解析区检测 `scene_spec` 内联渲染（与 b 同机制）。**改动最小，优先**。
  - **c2 聊天内嵌交互演示**：tutor 讲解时若当前题有 `scene_spec`，经 `DATA` 帧下发 `interactive_scene` 卡（决策 7）。需：① 把 `scene_spec` 注入 tutor 上下文（`aexplain` 已能取题面）；② `render.py#_KIND` 与 `AssistantCardKind` 双登记 `interactive_scene`；③ `SceneInterpreter` 处理「分析流程」按钮。工作量中等，但复用决策 7/8 同一通道，不引入新架构。
  - **可行性结论（2026-10-04 拍板：两者都要）**：c1 题卡内联优先落地（改动最小），c2 聊天内嵌卡随后追加；两路共用 `SceneInterpreter` 与 `interactive_scene` 卡片 kind，渲染器零差异。

### D. 必需的存储变更（澄清）

- `KnowledgePoint` 与 `Question` 均为**已存在表**，新增 `scenes` / `scene_spec` 列须走**启动期幂等 ALTER**（沿 `Question.source_refs` 先例，入 `app/core/db.py`），**不能**靠 `create_all`（那是给全新表的，见 `material.py:9`）。
- 两列均 JSON、默认 `null`、不建外键（快照口径，与 ADR-0055 §10 一致）。删知识点不影响已生成的题（题只快照 `ref_kp_scene`）。

### E. 关键设计杠杆：场景 = 有限 `kind` 词汇表的参数化实例

「为每知识点添加默认讲解」之所以可行且可维护，前提是**不**为每知识点手写独立动画，而是：教师在知识点上「选一个 `kind`（如 `bar_chart`）+ 填默认 `inputs/controls/narrative`」，渲染器按 `kind` 内置求解（决策 6）。否则 N 个知识点 = N 套动画，不可持续。**首版须先固化一个 `kind` 词汇表（`bar_chart` 起，候选见 §E.1），并给知识点打「是否有默认场景 / 哪个 kind」标记**。AI 起草阶段即从该注册表选 `kind` 并生成默认 `inputs`，教师确认 / 微调而非从零手选——但词汇表必须先固化，否则 AI 无枚举可选（决策 3 阶段①）。

### E.1 四年级数学（上）候选 kind 词表（基于资料库真实入库知识点）

从资料库 `KnowledgePoint`（grade=4, subject=数学，共 29 个，source=emerged）中，以下知识点天然适合图形化 / 交互式讲解，按首版优先级排序：

| 真实知识点（KP.name） | KP.id（前 8 位） | 候选 kind | 交互演示形态 | 首版 |
|---|---|---|---|---|
| 平均数与条形统计图 | f24c1077 | **`bar_chart`** | 改数据 → 条形实时变化 → 平均数线移动 | ✅ 实现 |
| 图形的运动（平移） | d054cd30 | `translation` | 方格纸拖动图形，显示平移方向与格子数 | 候选 |
| 图形的运动（轴对称） | 357dd912 | `reflection` | 单个轴对称图形 + 内部对称轴（可旋转任意角度+平移），播放时沿轴翻折、两半重合（找对称轴/判断是否轴对称） | ✅ 已落地（渲染器+编辑器） |
| 观察物体（二） | 99d90750 | `observation_3d` | 旋转查看三视图（需 3D，暂缓） | 候选 |
| 数位顺序表 | ca74c700 | `place_value` | 数字占位 / 进率可视化 | 候选 |
| 四舍五入 | c46978f2 | `rounding` | 看尾数位、舍 / 入判定 | 候选 |

> 抽象规律类（加法运算律 / 乘法运算律 / 末尾零的处理等）交互价值低，首版不纳入候选；它们仍可走纯文本 / markdown 讲解。候选词表随教材单元扩展，但**任何新 kind 须先入注册表并双登记**，AI 起草只能从表中选。

### F. 术语（glossary）

- **知识点默认场景 / KP 场景**：挂在 `KnowledgePoint.scenes` 的模板，含默认 `inputs`，一个知识点可服务多题。
- **题目场景实例 / scene_spec**：挂在 `Question.scene_spec` 的融合产物（`ref_kp_scene` + 覆盖 `inputs` + `locked_answer`）。
- **融合（fusion）**：出题时把题面输入覆盖 KP 场景默认 `inputs` 的过程。
- **kind**：场景渲染器枚举（`bar_chart`…），前后端双登记。
- **交互演示 / 交互讲解**：本能力统一命名（不叫「动画」，避免与 Lottie / 视频混淆）。
- **interactive_scene**：承载场景下发的卡片 `kind`（`DATA` 帧）。

## Consequences

- **后端新增**：`KnowledgePoint.scenes` 列、`Question.scene_spec` 列（启动期幂等 DDL，沿 ADR-0053 / 0055 纪律，不引 alembic）；`render.py` 加 `interactive_scene` kind + 融合函数（抽题面输入 → 覆盖模板）；出题管线 `question/pipeline.py` 在生成后调融合（RAG 接缝旁，类似 `rag_context` 注入点）。
- **前端新增**：`shared/widgets/scene_interpreter` + 各 kind 绘制器；`AssistantCardKind` 加 `interactive_scene` + 渲染分派；题卡解析区检测 `scene_spec` 内联渲染；知识点管理页加「添加图形讲解」（选模板 + 填默认 `inputs` / `controls` / `narrative` + 实时预览）。
- **约束 / 兼容性**：题卡解析渲染从纯 `Text` 改为「`Text` + 可选场景」，须保证无场景时与原行为完全一致；新增 JSON 列默认 `null`，旧数据无需迁移。
- **不在本 ADR 内**：公式渲染（§10）；更彻底的题 → 知识点归一（§11）；其余 kind（函数图像 / 几何等）；教师编写 UI 的完整形态（首版先做 `bar_chart` 闭环）。
- **命名红线**：场景统一叫「交互演示 / 交互讲解」，不叫「动画」（避免与 Lottie / 视频动画混淆）；`kind` 走注册表，不接受自由字符串；术语不与 ADR-0055 的资料库词汇（资料 / 资料片段 / 知识点目录）冲突。

## 验证判据

- 后端：`tests/.../test_scene_fusion.py`（融合 = 覆盖 `inputs` + 附 `locked_answer`；无场景 / 抽取失败 → `null` 降级）；`tests/ai/test_assistant_card.py`（`interactive_scene` kind 双登记、降级卡）。
- 前端：`test/scene_interpreter_test.dart`（`kind` 分派、未知 kind 降级、`reducedMotionOf` 兜底、`inputs` 改值重算 + clamp）；`test/assistant_card_test.dart`（`interactive_scene` 解析 + 内联渲染不破无场景态）。
- 分层不变量：`frontend/test/feature_boundaries_test.dart` R1/R2/R3 仍成立（`shared/` 不 import `features/`）。

## 已知遗留

1. 公式渲染未解决（§10）。
2. 题 → 知识点归一未彻底（§11）。
3. 教师编写 UI 首版形态未定：先做最小可用——选 `kind` + 表单填默认 `inputs` / `controls` / `narrative` + 实时预览，打通 `bar_chart` 闭环。
4. 「分析流程」的讲解文案动态改写（改 `inputs` 后 `narrative` 如何随 `outputs` 更新）需在各 kind 渲染器内定义，属渲染器契约的一部分。
5. **authoring 机制（2026-10-04 拍板：AI 起草 + 人工调参，两者结合）**：为现有知识点「添加默认场景」= AI 基于 KP（名称 / 学科 / 年级 / 学期 + 关联资料片段，按 KP 过滤召回）生成 SceneSpec 草稿（从 kind 注册表选类型 + 默认 `inputs`），教师再调交互体验后确认落库；不可图形化 KP 不产出。仍须先固化 `kind` 词汇表并为 `KnowledgePoint` 加「是否有默认场景 / 哪个 kind」标记（决策 E）。公式渲染维持 §10 字面串占位（用户拍板首版不引入 flutter_math）。

### G. 实现进度（2026-10-04）

决策 9.1 的 `reflection` 已完成**端到端 MVP**：教师可在知识点上编写并保存默认交互讲解，出题 / 错题 / 伴学消费待接。

- **后端（已落地 + 验证）**
  - `KnowledgePoint.scenes` 列、`Question.scene_spec` 列（JSON、可空、不建外键，与 `source_refs` 同口径）。
  - 迁移：`app/core/db.py` 启动期幂等 ALTER（SQLite `PRAGMA` + Postgres `IF NOT EXISTS` 双分支）；已对真实 `app.db` 执行验证，存量数据两列均默认 `null`。
  - 读写：`schemas.KnowledgePointScenesUpdate` + `service.update_knowledge_point_scenes`（owner 隔离校验）+ `router.PATCH /materials/knowledge-points/{kp_id}/scenes`；`KnowledgePointResp` 已带 `scenes`。
  - 验证：`ruff` 全清、`import` smoke 通过、`run_migrations` 实际加列成功。

- **前端（已落地 + `flutter analyze` 全清）**
  - 渲染器：`shared/widgets/scene_interpreter/reflection_scene.dart`（`ReflectionSceneData` + `ReflectionSceneWidget`；几何严格对齐已验证原型——折叠角 = 进度×180°、半平面裁剪双填充、重合门控于 180°）。
  - 解释器：`shared/widgets/scene_interpreter/scene_interpreter.dart`（`SceneInterpreter` 按 `kind` 分派，`unknown` 走 `AppEmptyState` 降级）。
  - 教师调参 UI：知识点管理视图已落库知识点（id≠null）行加「讲解」入口 → 弹窗编辑器（`knowledge_point_scene_editor.dart`：选图形 + 调默认对称轴参数 + `SceneInterpreter` 实时预览 + 保存）；`KnowledgePointOption` / `MaterialRepository` / `knowledgeManageProvider` 已接 `scenes` 读写。

- **仍待做（不在本轮）**
  - 三处消费方接线（§C：出题融合写 `scene_spec` / 错题本内联 / 伴学 c1+c2）。
  - `bar_chart` 等其余 kind（§E.1）。
  - 公式渲染（§10，首版字面串占位）。

### H. 助手卡 `interactive_scene` 接入（2026-10-04 落地）

ADR-0061 决策 7 的后端 DATA 帧 + 前端渲染分派已打通（任务 ②）。本次只做**卡片协议层**接入；真正「从讲解 / 题目解析下发 SceneSpec」的生产者（伴学 c2 路径）仍属 §C 三处消费方接线（任务 ③）。

- **前端（已落地 + `flutter analyze` 全清 + 单测全过）**
  - `domain/assistant_card.dart`：`AssistantCardKind.interactiveScene = 'interactive_scene'`（与后端 `render.py#INTERACTIVE_SCENE_KIND` 逐字双登记）；`hasContent` 对 `interactive_scene` 以「内层 `rawPayload['kind']` 为字符串」判定，缺内层 kind 不挂空壳卡。
  - `presentation/widgets/assistant_interactive_scene_card.dart`（新建）：卡头（`LucideIcons.shapes` + 标题取自 SceneSpec 的 `title`）+ `SceneInterpreter(kind: 内层kind, spec: rawPayload)`；复用 `AssistantCardShell` 容器。
  - `assistant_card_header.dart`：`interactiveScene` 加图标 `shapes`、归「结构 / 对话」中性族（不抢色相）。
  - `assistant_cards.dart`：`switch` 加 `interactiveScene` 分派到新卡；`shared/` 不 import `features/`（分层不变量保持）。
  - 验证：`test/assistant_card_test.dart` 增「外层 kind + 内层 scene kind 落 rawPayload」「缺内层 kind → 无内容」两组。

- **后端（已落地 + `ruff` 全清 + 单测全过）**
  - `ai/subagents/query/render.py`：增 `INTERACTIVE_SCENE_KIND` 常量（`render_scene_card` 与之同义，双登记）+ `render_scene_card(spec)` 构建器（畸形 spec 不崩、空 payload 降级）；导出入 `__all__`。
  - 生产者约定：讲解 / 题目解析侧拿到 `scene_spec` 后 `data_event(card.payload, extra={"type": INTERACTIVE_SCENE_KIND})`，前端 `fromData` 把 `result` 原样放入 `rawPayload`。
  - 验证：`tests/ai/test_assistant_card.py` 增常量对齐 / 包裹 / 拷贝隔离 / 畸形 spec 四组。
