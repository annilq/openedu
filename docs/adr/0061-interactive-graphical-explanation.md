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

### I. 消费方接线（2026-10-04 落地）

任务 ③ 的首个切片已打通**读路径解析**形态（ADR-0061 §C 的 (b) 错题本 + (c1) 题卡内联）：

- **融合内核**：`app/features/materials/scene_fusion.py`
  - `fuse_scene_spec(kp_scenes, overrides)`：纯函数，取知识点模板首条、深拷贝、用题面输入覆盖同名 `inputs[].value`（无 overrides 即原样拷贝）；缺模板 / 畸形一律 `None`。
  - `resolve_scene_spec_for_question(session, parent_id, subject, grade, knowledge_point, cache)`：按 `(parent_id, subject, grade, name)` 查家长私有知识点（**忽略 semester**——`Question` 不携带学期维度，与绝大多数知识点默认 `semester=''` 一致），命中取最新一条；带 `cache` 避免一页错题对同一知识点反复查库。
- **后端错题本响应**：`WrongQuestionResp` 加 `scene_spec` 字段；`tasks/service.py#wrong_question_to_resp` 解析并附上（三处调用点同步：`list_wrong_questions` / `list_wrong_questions_page` / `rejoin`）；`WrongQuestionListResp` 透传。
- **前端**：`WrongQuestionModel` / `QuestionModel` / `QuestionPreview` 加 `sceneSpec`（fromJson/toJson）；`wrong_questions_screen._WrongQuestionCard` 与 `assistant_question_card._QuestionBody` 在 `sceneSpec` 存在时内联 `SceneInterpreter`（带「交互讲解」标签，无场景时维持原纯文本行为，零回归）。
- **验证**：后端 `tests/features/materials/test_scene_fusion.py`（6/6，纯函数 + stub session 缓存/命中/缺失三态）；前端 `test/assistant_card_test.dart`（题卡携带 scene_spec 解析断言）；`ruff` 全清、`flutter analyze lib` 零 issue、改动涉及的 `test_pagination` / `test_archive` 16/16 全过。

**形态决策（MVP，待确认）**：本轮采用**读路径按知识点解析场景**，而非 ADR-0061 决策 2/3 原规划的「出题时融合写 `Question.scene_spec` 快照」。理由：零表结构改动（`Question.scene_spec` 列虽已建但本轮未写）、对历史题即时生效、不依赖重建题。代价：知识点模板改动会即时反映到所有历史错题（非快照语义）。若需严格快照语义，后续可加写出题时持久化。

**仍待做（下一切片）**
- (c2) 伴学讲解经 `DATA` 帧下发 `interactive_scene` 卡（决策 7 的生产者）：tutor 讲解当前题时若 `scene_spec` 命中，经 `data_event(card.payload, extra={"type": INTERACTIVE_SCENE_KIND})` 下发；后端 `render.py#_KIND` + 前端分派已就绪（任务 ②），只差生产者接线。
- 出题融合写 `Question.scene_spec`（ADR-0061 决策 2/3 原规划）：在 `_gen_for_swap` / `create_from_generated` 落库缝注入；与读路径可并存（写优先、读兜底）。
- `bar_chart` 等其余 kind（§E.1）。
- ~~教师端「按学期维护知识点讲解模板」的 UI 收口~~ → **已落地（§K）**：弹窗暴露作用范围（学期 tag + 生效条件说明），列表行加学期徽标；不做学期切换（知识点学期建行即定，唯一约束含 semester）。

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

### I. 发布任务对接资料库：学期维度打通（2026-10-05 落地）

让「发布任务」表单里的学科 / 年级 / 知识点与资料库目录联动，并加**学期**选项，使任务里的题与知识点关联，讲解时能按知识点预设的交互场景演示。

- **学期贯通全链路**（`''` = 不限 / 整学年；`'上学期'` / `'下学期'`，与后端 `KnowledgePoint.semester` 同源）：
  - 存储：`Question.semester` + `TaskQuestion.semester` 两列（启动期幂等 ALTER，SQLite PRAGMA / Postgres `IF NOT EXISTS` 双分支；已对真实 `app.db` 验证）。`TaskQuestion` 也带学期是因`promote_task_question` 把TaskQuestion 字段拷贝进题库 `Question`。
  - 出题链路：`GeneratedQuestion` / `QuestionOut` / `QuestionSpec` / `TaskSpec` 全加 `semester`；`expand_specs`（dict + 对象两路）逐项保留；`build_question_prompts` 同时把学期写进 `QuestionSpec`（供装配回填）与 prompt 语境（`(上/下)学期`，未指定时说「整学年」）；`stream_question` / `SchemaQuestionParser` 把学期回填到题卡。
  - 落库：`_question_fields` 白名单加 `semester`（覆盖 `_question_from_payload` / `_task_question_from_payload`）；`from-generated` 直建 `TaskQuestion` 与 `promote_task_question` 均写入；`_gen_for_swap`（单题重生成）沿用 `tq.semester`。
  - 场景解析：`resolve_scene_spec_for_question` 改**学期感知**——优先精确命中 `(subject, grade, name, semester)`，否则回落 `semester=''` 整学年模板；`cache` 键含学期。
- **前端**：
  - `knowledgePointsProvider` family 键 `(String, int)` → `(String, int, String)`（学期进 key，同学期只取同学期目录）。
  - `TaskSpecRowEditor` 拆**两行**布局（学科/知识点/题型 + 题数/年级/学期/删除）并加学期 `AppPickerField`——一行塞 7 个字段在紧凑档（<700）每格仅 ~45px、选项文字被截断。新增 `kTaskSemesters` / `kTaskSemesterLabels`（`''` → 「不限学期」）。
  - `TaskSpecModel` / `QuestionModel` / `QuestionPreview` 加 `semester`（fromJson / toJson）→ 学期随流式题卡回传 `/tasks/from-generated` 落库。
- **顺带修复**：`materials/service.py#update_knowledge_point_scenes` 内联比较 `parent_id` 违反分层不变量 9（`tests/ai/test_layering_invariants.py`）——改用 `core.guard.require_owned`。此为更早「存储 DDL + 教师调参 UI」轮次引入、当时未跑该守卫的既存欠账。
- **验证**：迁移已对真实 `app.db` 跑通（两列均在）；`ruff check app` 全清；`flutter analyze lib` 零 issue；后端 `test_question_semester.py`（5/5：规格展开 / prompt spec+语境 / 流式回填）+ `test_scene_fusion.py` 增学期四组（精确命中 / 回落整学年 / 无学期单查 / 缓存键含学期）共 15/15；前端 `test/task_semester_test.dart` 6/6。**全量pytest 3 个 vectorize/retrieval 用例失败为既存测试顺序污染**（干净树同样失败、单跑通过），非本次引入。

### J. 布置任务排列调整 + 知识点按学期联动修复（2026-10-05）

用户报障：「4年级上学期数学资料库有 12 个知识点，但布置练习任务里知识点不随学期切换」。两处改动：

- **排列改为填写顺序**：`年级 → 学期 → 学科` 三个范围项在第一行，`知识点 → 题型 → 题数` 在第二行。理由：前两者决定知识点的可选集，先摆它们家长才「先定位范围、再挑知识点」；知识点紧跟其后，中间不插别的控件。仍用**两行**（非一行）——6 字段挤紧凑档（<700）每格仅 ~60px、选项文字被截断。
- **根因修复：不限学期原本是「精确匹配空串」**。`repo.list_knowledge_points` 对 `semester=''` 也做 `== ''` 匹配，而资料涌现的知识点几乎都带「上/下学期」——于是表单默认态永远只拿到 6 个泛化骨架兜底，家长看到的就是「不随学期切换」。改为：
  - `semester=''`（不限）→ 返回该 (学科, 年级) 下**所有**学期的知识点（并集，按学期排序）；
  - `semester='上/下学期'` → 精确匹配该学期。
  - 实测 4年级数学：不限 29（15 上 + 14 下）、上学期 15、下学期 14。
  - `KnowledgePointResp` 加 `semester` 字段随行下发，前端在**不限学期**的跨学期并集里给非当前学期项加「（X学期）」后缀标注，限定学期时不加（无噪声）。
- **顺带的分层修复**（ADR R4 棘轮，`_knownR4` 自 2026-09-15 起为空、不得回退）：为拿 `KnowledgePointOption.semester`，presentation 一度 import `data/repositories/material_repository_impl.dart` → 把**接口 + 选项模型**移到 `domain/repositories/material_repository.dart`，`data/` 只留 `MaterialRepositoryImpl`。
- **顺带的文件拆分**（ADR-0058）：`parent_task_form_view.dart` 因加学期涨到 410 行、触发 400 行守卫 → 把持两个 `TextEditingController` 的 `_SpecRow` 提成 `task_spec_row_data.dart` 的 `TaskSpecRow`（与纯展示的 `TaskSpecRowEditor` 构成数据/视图一对），表单回到 355 行。
- 验证：`test_materials.py::TestKnowledgePoints::test_semester_scope_union_vs_exact` 钉住并集/精确两态 + 响应带 semester；`ruff check app tests` 仅余 1 处既存未用 import（`tests/domain/test_subject_qtypes.py`，非本次引入）；前端 `flutter analyze lib` 零 issue、**全量 277 例全过**（含 `file_size_guard_test` 与 `feature_boundaries_test` R4 棘轮）。

### K. 教师调参弹窗暴露学期维度（2026-10-05）

把 §I 遗留的「教师调参弹窗默认落整学年」收口。**先厘清一件事**：弹窗不做学期**切换**——模板挂在**某个具体知识点**上，而知识点的学期在建行时就定了（唯一约束 `(parent_id, subject, grade, name, semester)`）。在弹窗里改学期等于「移动知识点」，会撞唯一约束、且语义上不是调参。因此本轮做的是**把作用范围显式摆出来**。

- **弹窗头部作用域条**（`knowledge_point_scene_editor.dart`）：标题下补知识点名 + 一条作用域条（`年级 / 学科 / 学期` 三个 tag），并按学期给一句话预期：
  - 整学年（`''`）：「整学年兜底模板：仅当题目没有同学期的专属模板时才生效。」
  - 上/下学期：「仅作用于此学期（X）的题目；其他学期若有专属模板则不生效。」
  这段文案对应后端 `resolve_scene_spec_for_question` 的「先精确同学期 → 回落整学年」规则——教师不知道当前配的是哪个学期的模板，就无法预期讲解时会不会命中。
- **列表行学期徽标**（`material_knowledge_manage_view.dart`）：`km.semester.isEmpty && kp.semester.isNotEmpty` 时给该行加一个学期 tag。**这是上一轮并集改造的必要补丁**：整学年视图同屏混着上/下学期的点（实测 4年级数学 = 上15 + 下14），光看名字分不出归属。限定了学期范围时后端只回该学期的行，徽标即冗余，不画。
- 弹窗入参从 `kpId + initialScenes` 扩到 `kpId / kpName / subject / grade / semester / initialScenes`；`semester` 传**知识点自身的** `kp.semester` 而非当前范围筛选值（范围可能是并集，弹窗要显示的是这份模板实际作用的那个学期）。
- 验证：`flutter analyze lib` 零 issue、全量 277 例全过；两文件 290 / 252 行（守 ADR-0058）。真实数据实测：`图形的运动（轴对称）` = 数学 4年级**下学期**，整学年并集响应里 `semester='下学期'` 且 `scenes` 随行下发，弹窗能同时拿到学期与既有模板。

### L. 报障排查：改学期后知识点 options 不变（2026-10-05）

**逐层排除**（先测后判，不靠猜）：① provider 层三元组 key → 三次请求三份数据 ✅；② 视图层编辑器 getters → 随 options 变化 ✅；③ `ShadSelect` 是否缓存旧下拉 → 实测能刷新 ✅（**排除**了「StatefulWidget 缓存」这个想当然的猜测）；④ 真实 HTTP → **根因浮出**。

- **根因**：并集/精确过滤本身是对的，但**作用在空集上**。某些 (学科, 年级, 学期) 范围还没有资料知识点，真实行数为 0，下拉只剩 `skeleton_names(subject, grade)` 骨架兜底——而**骨架函数不吃学期参数**，于是三个学期返回**逐字相同**的 6 个泛化条目。§J 修的是「有数据时按学期切」，没覆盖「无数据时看起来没切」。
- **修法 = 把沉默变可见**，而不是给 108 个 (学科×年级×学期) 格编骨架课表（自编课表容易教错，且违背骨架「冷启动不空窗、不充当权威课标」的定位）。`KnowledgePointListResp` 加 `notice`：
  - 某学期**无真实知识点** → 明说「该学期还没有资料知识点，以下是**不分学期**的通用目录；上传对应学期的资料并向量化后，这里才会按学期变化」；
  - 「不限学期」（并集语义）与「已有真实知识点」→ `notice` 为空，不制造噪声。
- **前端**：新增 `KnowledgePointDirectory`（`items` + `notice`）取代裸 `List`，`knowledgePointsProvider` 返回它；`DirectoryNoticeBar`（弱一档 secondary 描边 + info 图标）在布置任务表单与知识点管理页展示。
- 验证：后端 `test_notice_explains_skeleton_only_scope` 钉住 notice 三态（空目录给 / 不限学期不给 / 有真实点后消失）；前端 `task_semester_options_test.dart`（5）+ `select_options_refresh_test.dart`（1）；`flutter analyze lib` 零 issue；后端全量 480 passed。
- **未解决（留待产品决策）**：若希望「无数据时切学期也给出不同骨架」，需要真正的学期课表数据源（教材目录），不属于本ADR 范围。当前形态是如实告知而非伪造。

### M. 关联度自查：题目 ↔ 知识点 ↔ 交互场景（2026-10-05，实测）

用户问：「为『图形的运动（轴对称）』出一道选择题有 4 个选项，讲解时会不会为 4 个选项各生成交互讲解？」**答案：不会，而且当前连 1 个场景都不会出。** 逐段核实如下（`backend/app.db` 实测，非推断）。

| 环节 | 现状 | 证据 |
|---|---|---|
| 题目 → 知识点 | ✅ **已关联** | `Question.{subject,grade,semester,knowledge_point}` 四元组随规格落库（§I） |
| 知识点 → 场景模板 | ⚠️ **形同虚设** | 205 个知识点里 `scenes` 非空的只有 **1** 条，且它是 JSON 字符串 `'null'`（不是 SQL NULL）→ `fuse_scene_spec` 拿到 `None` 一律返回 `None` |
| 题目 → 场景实例 | ❌ **从未写入** | `Question.scene_spec` 列存在（§I 建的），但全库 **8 道题非空数 = 0**；代码里 `scene_spec=` 唯一出现在 `tasks/service.py:158`，那是**读路径**的 `WrongQuestionResp` 响应字段，不是落库 |
| 题目数值 → 场景 inputs | ❌ **没接上** | `resolve_scene_spec_for_question` 调 `fuse_scene_spec(kp.scenes)` **不传 `overrides`**（`scene_fusion.py:106`）。`fuse_scene_spec` 的 `overrides` 参数（按题面数值覆盖默认 inputs）**全仓无调用方**——这是 ADR §C 决策 2/3 规划、至今未实现的那一步 |
| 选项 → 场景 | ❌ **结构上不可能** | 场景由 `knowledge_point` 单键解析，**与 `options` 无关**；前端 `_QuestionBody` 里 `options` 只喂 `_QuestionOptions`（纯文本选项），`sceneSpec` 只喂 `SceneInterpreter`（kind + inputs），两条互不相交 |

**结论**：当前形态是「**一个知识点 → 一份通用场景模板**」，不是「**一道题 → 一份贴合该题的场景**」。所以 4 个选项不会被分别讲解；即便模板配好了，也只会出现**一个**场景，且用的是知识点模板里的默认轴参数（house / 90°），**与这道题的具体图形、具体选项无关**。

**要达到「每题各自贴合」需要补的三步**（均未做）：
1. **出题时抽题面数值** → `overrides`：从 stem/options 里抽出图形与轴参数（选择题还要逐选项抽，这是最难点）；
2. **落库快照** → 在 `_gen_for_swap` / `from-generated` 缝把融合结果写进 `Question.scene_spec`（顺带获得快照语义：模板改了不影响已生成的题）；
3. **选择题的逐选项场景**：需要 SceneSpec 表达「一组候选图形 + 判定哪几个轴对称」，即 `kind` 从单图 `reflection` 扩到集合语义（`options[]` + `locked_answer`），这是**新的 kind** 而非现有 kind 的参数扩展。

⚠️ 另发现一个数据缺陷：把 JSON `null` 存进 `scenes` 会让「非空计数」失真（`IS NOT NULL` 为真但内容是空）。写入侧应统一 `scenes or None`（`update_knowledge_point_scenes` 已是这么写的，是历史数据或绕过该端点写入的）。

### N. 落库快照 + 题面数值抽取（§M 第 2 / 1 步，2026-10-05 落地）

补上 §M 诊断出的前两步。第 3 步（选择题逐选项场景 / 新 kind）**仍未做**。

- **① 题面数值抽取**（新 `app/features/materials/scene_extract.py`）：纯函数 `extract_scene_inputs(stem, options) -> overrides`，抽 `figure`（房子/风筝/箭头/平行四边形，中英词表）与 `axisAngle`（`45°`/`60度`，**负号一并捕获**否则 `-30°` 会被当成 `30°` 把轴画到镜像位置）。
  - **只抽「抽得到且不矛盾」的**：`axisX/axisY` 是归一化对称轴位置，题面极少精确表述 → **永不从题面抽**，只由教师在调参面板手摆。抽不到就返回空 dict让模板默认值留着——给一个与题目无关的图形比不给场景更糟（会教错）。
  - 角度只接受 `0..180`：`360°` 是旋转题不是轴对称题，不覆盖。
  - 选择题取**第一个**命中的图形（题面优先于选项）：逐选项各配一个场景需要 SceneSpec 表达「候选图形集合 + 判定哪几个对称」，是**新 kind**（第 3 步），单 kind 结构上做不到。
- **② 落库快照**：
  - `TaskQuestion` 新增 `scene_spec` 列（`Question` 早有）。草稿期就带上——否则确认前的预览/草稿审核拿不到场景（`Question` 要等 promote 才有行）。启动期幂等 DDL，SQLite/Postgres 双分支。
  - 三处落库缝写入：`create_from_generated`（主路径，优先用前端回传的、否则就地融合）、`_gen_tq_for_spec_item`（整卷生成/重生成，经新增的 `scene_ctx=(session, parent_id)`）、`_gen_for_swap`（单题重生成，**必须重算**——新题 stem/options 与旧题不同，不能沿用旧快照）；`promote_task_question` 把草稿快照带进题库 `Question`。
- **③ 读路径快照优先**：`wrong_question_to_resp` = `q.scene_spec or build_scene_spec_for_question(...)`（老数据无快照时回退实时解析，存量题仍能出图）。`question_to_resp` 直接下发草稿快照。
- **④ 缓存纪律**：`overrides` 非空时**绕过** `cache`——缓存键只含 (知识点, 学期)，带题面值时同一知识点不同题目结果不同，混用会串味。故 `build_scene_spec_for_question` 透传 `cache`，仅在抽不到题面值时生效。
- **⑤ 根因修复：`JSON(none_as_null=True)`**。§M 发现的「文本 `null`」不是历史脏数据，而是 **SQLAlchemy `JSON` 类型默认把 Python `None` 序列化成字符串 `'null'`**——清空模板写进去的就是文本，`IS NOT NULL` 为真而内容是空。三个场景列（`KnowledgePoint.scenes` / `Question.scene_spec` / `TaskQuestion.scene_spec`）全部加上 `none_as_null=True`，实测「写内容 → typeof=text / 清空 → typeof=null 且值为真 NULL」。存量 1 条脏数据已清洗。
- 实测（同一知识点「图形的运动（轴对称）」、同一模板，三道不同题各自抽到的场景**互不相同**）：

  | 题面 | 抽到的场景 |
  |---|---|
  | 房子沿 45 度的线对折 | `figure=house, axisAngle=45.0` |
  | 下图是风筝，判断是否轴对称 | `figure=kite`（角度沿用默认 90） |
  | 平行四边形是轴对称图形吗 | `figure=para` |

- 验证：新 `test_scene_extract.py` **17/17**（含 `none_as_null` 真 SQL NULL 的底层 `typeof` 断言、以及「`axisX/axisY` 永不被抽」「负角度被拒」「超范围角度被拒」）；`test_scene_fusion.py` 增 overrides 覆盖 / 读路径生效 / **带overrides 绕过缓存** / 端到端四组；后端全量 **502 passed**（3 个 vector 既存顺序污染同前）；前端 `analyze lib` 零 issue、283 passed（1 failed 仍是并行会话的 `parent_question_bank_view` 棘轮，非本次引入）。前端**无需改动**——`QuestionModel`/`WrongQuestionModel`/`QuestionPreview` 早已读 `scene_spec` 且题卡/错题卡都会内联 `SceneInterpreter`。

### O. 选项组：同一模板派生 N 个独立可交互场景（2026-10-05 落地，§M 第 3 步）

用户澄清了第3 步的真实需求：**不是**让程序判定「哪几个选项轴对称」并报答案（我原先设想的集合语义新 kind），而是「每个选项都能单独演示、用户自己拖轴验证」。核查发现该能力**早已内建**（`_isAxisymmetric` 吃任意多边形 + 3 个轴slider + 实时「✓ 是轴对称 / ✗ 不是」判定），缺的只有「**图形切换**」与「**选项各自的几何**」。

- **纯顶点驱动，不内置图形概念**（用户决策）：渲染器不再认识「房子/风筝」。图形顶点下沉为**数据**：
  - `frontend/lib/shared/domain/figures.dart` + `backend/app/features/materials/scene_figures.py` —— 同一份几何的两个副本（运行时后端读不到前端源码）。`ReflectionFigure` 枚举删除，退化为教师面板的「预设选择器」。
  - `ReflectionSceneData` 核心变成 `points`，`fromSpec` 优先级：`inputs[].points`（后端下发）→ `figure` 预设 key（兼容旧 spec）→ 房子兜底。**永不出现空场景**。
  - ⚠️ **副本漂移会改判定**（学生拖轴永远对不上）→ `test_scene_figures.py` 做**跨语言逐字比对**（正则解析 Dart 源与 Python 侧对齐），并钉住「`para` 必须保持错切（上边中点 0.50 / 下边 0.62）——它就是那道『不是轴对称』的干扰项，被修正成矩形题目就废了」。
- **选项组 `optionGroup`**：`extract_option_group(options)` 逐项识别图形 → 附**该图形自己的顶点 + 默认轴角度**；`build_scene_spec_for_question` 把它挂在 spec **顶层**（不放`inputs`——那会被当单图输入解析）。实测同一模板 + 4 选项 → A房子(5顶点,90°) / B风筝(4,90°) / C箭头(7,**0°**) / D平行四边形(4,90°)。
  - **全-or-无**：任一选项识别不出 → 整体不生成（退回单场景）。半套选项组比没有更容易误导。
  - 标号优先取选项原文前缀（`A.` / `A、`），无前缀则按序回退 A/B/C。
- **前端 `SceneOptionGroup`**：`SceneInterpreter` 见`optionGroup` 即展开为 N 个 `ReflectionSceneWidget`（各自 State → 拖 A 不影响 B），**Wrap** 排布（用户决策③）。每项用**该图形自己的默认轴**而非模板的（否则箭头停在竖轴、一开始就不重合，学生会以为题目错了）。
  - ⚠️ **实测发现并修**：`ReflectionSceneWidget` 画布是「边长 = 宽度」的**正方形**，两列并排在 1200 宽屏上每个高达~590px，一屏放不下 4 个 → `_itemWidth` 夹在 [240, 360]。
- **①A `editable: true`**（用户决策）：教师面板保存时不再写 `false`——那会把轴控制控件整个藏掉，学生只能看不能试，等于掐掉题目最核心的动手环节。
- **spec 格式变更安全性**：改动前确认三张表 `scenes`/`scene_spec` **存量为 0**（仅 1 条测试残留，已清），故直接改格式无需兼容旧快照；`fromSpec` 仍保留 `figure` 预设 key 回退以防将来。
- 验证：后端 `test_scene_figures.py` **8/8**（含跨语言 parity + para 错切守卫）、`test_scene_extract.py` 增选项组 **8 组**（四选项各自顶点/箭头横轴/点与图库一致/中文分隔符标号/无前缀回退/**全-or-无**/≥2 选项）；前端 `scene_option_group_test.dart` **7/7**（渲染 N 个而非 1 个 / 各用自己默认轴 / 顶点不共用 / 标号图形名可见 / 无 optionGroup 零回归 / 无效 points 走空态不崩 / editable 轴控件可见）；后端全量 **518 passed**、前端 **290 passed**（1 failed 仍是并行会话的 `parent_question_bank_view` 棘轮）。
- **遗留**：`optionGroup` 目前只在题目**选项文字里能识别出图形**时生成；识别不出（如「如图所示」）就退回单场景。真正的按图演示需要图形识别能力（视觉/OCR），不在本轮。

### P. 修：教师调参弹窗溢出（①A 的副作用）

把 `editable` 改成 `true`（①A）之后，`KnowledgePointSceneEditor` 的 Column **溢出 306px**（536×808 弹窗装不下）。根因是 `_buildSpec()` 被**预览与保存共用**：预览因此也长出 3 个轴滑块，而面板上方本来就有同样的 3 个（纯重复），叠加「预览画布是边长 = 宽度的正方形」（536 宽 → 536 高）直接顶爆。

修法（三处，缺一仍会在某类屏高下复发）：
1. `_buildSpec({required bool editable})` —— **保存传 `true`**（学生端要能拖轴，①A 本意）、**预览传 `false`**（不重复滑块）。两者语义本就不同，不该共用一个默认值。
2. 预览外包 `Center + ConstrainedBox(maxWidth: 300)`，压窄正方形画布。
3. 弹窗内容套 `SingleChildScrollView` 兜底——任何屏高/字号组合都不再溢出。

**教训**：`editable` 是「**存进 spec 的值**」，不是「面板自己的预览行为」。凡是「同一份 spec 同时供预览与持久化」的地方，都要显式区分这两个用途。

验证：`test/scene_editor_dialog_test.dart` **6/6** —— 弹窗不溢出 / 预览**不重复**轴滑块（断言轴滑块恰好 3 个而非 6）/ **保存的 spec 是 `editable: true`** / 保存带 `points` / 短屏 700×560 不溢出 / 换图形轴角度跟随默认轴。`flutter analyze lib` 零 issue、全量 **296 passed**。

### Q. 家长端「查看解析」出图 + 正方形（程序生成的第一例）

诉求：「正方形有几条对称轴」（答案 C，4 条）在查看解析时能拖轴试出 4 条，而不是给一行文字。

- **两端分叉是主因**：学生端错题卡早有场景（`wrong_questions_screen.dart:277`），**家长端完全没接**（只有 `解析：{文字}`）。抽出 `WrongQuestionExplanation`（含展开态 + 文字 + 图形）接上，判定条件与学生端一致。**顺序：文字解析在前、图形在后**（先给结论、再给可动手验证的图形）；**有图但文字为空也能展开**。
- **正方形：程序生成（决策 A 轴对齐零微扰）**。分界线是「几何定义是否唯一且无歧义」：
  - 规则图形（正方形/正三角形/圆）→ **程序生成**，任何实现都必然正确，还能参数化位置朝向；
  - `para` 这类**不对称是教学设计意图**的→ **必须手写**，算法只会把它"修好"。

  故新增 `_square_vertices(cx, cy, half)`，**刻意不接受 rotation 参数**（要转就转画布，别动顶点）。
- **`axisAngles`（全部对称轴）字段**：`FigureShape` 从「一条 `defaultAxisAngle`」扩到「**一组** `axisAngles`」，因为「有几条」要数它。第二层（计数反馈）将来加不用改结构。
  - ⚠️ **必须如实下发**（para = `[]`、count = 0）：曾写 `axis_angles or [default]` → para 谎报「有 1 条轴」，而这份数据唯一的用途就是回答「有几条」——那是**教错**。渲染要的「初始轴」另有 `defaultAxisAngle`，**两者语义不同，别用兜底混掉**。
- **figure 命中必须连带下发 `points`**：前端 `fromSpec` 的几何优先级是「`points` > `figure` 预设」，只覆盖 `figure` 会让画面仍是模板里那个图形（题干讲正方形、画着房子）。
- **`fuse_scene_spec` 支持 overrides 新增 input key**：老模板没有 `points` input 时，覆盖会被**静默丢弃**（改动没生效且无任何报错）。
- 实测（教师模板=房子 + 题干「正方形有几条对称轴」）：`figure=square` / `points` 4 顶点 / `axisAngles=[90,0,45,135]` / `axisCount=4`。
- **ADR-0058 两次踩线**（基线只许下调，故拆文件而非调基线）：`reflection_scene.dart` 618>567 → 抽出 `ReflectionSceneData` 到 `reflection_scene_data.dart`（数据层与渲染层分开）；`parent_wrong_questions_view` → 抽出 `WrongQuestionExplanation`。
- ⚠️ **测试里解析 Dart 源的正则回溯**：`arrow` 的 `axisAngles` 前有注释 → 跨字段大正则的 `.*?` 回溯把**下一个图形（`para`）整块吞掉**，误报「图形 key 不一致」。改为**先 `split('FigureShape(')` 切块、再逐字段独立解析**。
- 验证：后端 `test_scene_figures.py` **13/13**（正方形 4 轴 / 轴对齐 / para 0 轴 / 跨语言 parity 含 `axisAngles`）、`test_scene_extract.py` 增 4 组；前端 `wrong_question_explanation_test.dart` **6/6**；后端全量 **533 passed**（3 vector 既存污染）、前端 **303 passed**（1 failed 为并行会话的 `parent_question_bank_view` 棘轮）。
- **第二层按用户决定暂不做**（「已发现 2/4 条」计数反馈）；数据层 `axisAngles` 已就位。

### R. 修：知识点 UNIQUE 约束缺 semester（§J 遗留的静默故障）

报障：`UNIQUE constraint failed: knowledgepoint.parent_id, .subject, .grade, .name`（确认知识点 500）。

- ⚠️ **根因：SQLite 没有 `ALTER TABLE ... ADD CONSTRAINT`**。§J 加学期维度时只补了**列**（`ADD COLUMN semester``），而 `ADD COLUMN` 里写的 `UNIQUE(...)` 子句会被**静默忽略**。于是所有在加学期维度**之前**建库的库（本机 dev 库即是）唯一约束仍是旧的**4 列** `UNIQUE(parent_id, subject, grade, name)`。
  - **新建库没事**（`create_all` 按模型建 5 列）→ 这正是它长期测不出来的原因。
  - `ix_knowledgepoint_scope` 同样过期（老库 3 列、模型 4 列）。
- ⚠️ **后果不是报错，而是静默废掉 §J 承诺的核心能力**：同一知识点**无法**按学期各存一份（上/下学期模板）——名字一撞就撞唯一约束。
- **修法**：`_rebuild_kp_unique_with_semester(conn)`。SQLite 改约束只有一条路：**重建表**（建新表 → `INSERT..SELECT` 拷数据 → 删旧 → `ALTER..RENAME` → 重建 `ix_knowledgepoint_scope` 为 4 列版）。
  - **幂等**：先读 `sqlite_master` 判 UNIQUE 里有没有 `semester`，缺才动手；表未建 / 列都还没有则跳过（偏序迁移纪律）。
  - **数据安全**：只搬行不改值；旧 4 列约束**更严**（同一名字在旧库不可能有多行），故新约束下必然仍成立 —— 不会出现迁移后立刻违约。
- 实测：迁移后约束 5 列、索引 4 列、**205 行守恒**、连跑 3 次幂等；HTTP 复现原崩溃路径（上/下/整学年各确认一次同名知识点）全 200。
- 回归测试 `tests/core/test_kp_semester_unique_migration.py` **9/9** —— 在临时库上**手工造出老库形状**（4 列约束）再跑迁移：老库必撞 / 迁移后能共存 / **同学期同名仍被拒**（补 semester ≠ 放弃唯一性）/ 幂等且行数守恒 / **`scenes` 列不丢**（教师模板会整列消失）/ 表缺失是 noop。
- **教训**：SQLite 迁移里「加列」不等于「加约束」；且这类问题**在新建库环境测不出来**，回归测试必须手工造老库形状。

### S. 题库题目详情（含知识点信息 + 交互讲解）

题库列表是**扫描式**的（题干截 2 行、只有标签），但「这题讲什么」需要**停留式**阅读 —— 列表里既没有选项/答案/解析，也没有任何图形。

- **数据链路诊断**：`list_bank_questions` 用 `select(Question)` 取整行，`Question.scene_spec` **本来就在库里**，但 service 手工列字段时**漏了它**（`semester` 也漏）→ 后端补上下发；前端 `BankQuestionItem` 补 `sceneSpec` / `semester`。
- **入口不劫持整卡 onTap**：题库整卡点击是「**多选**」（批量归档/删除/导出），改成打开详情会让家长没法多选题 → 走行内显式入口「查看详情」。
- 新增 `BankQuestionDetail`（独立文件，避 ADR-0058 棘轮）四块内容：
  1. **题目本体**：题干全文 + 选项（标号按**位置**生成，与做题/纸质导出一致）+ 答案 + 解析；
  2. **知识点信息**：学科 / 年级 / **学期** / 知识点 / 被引用次数。学期是 §J 的第四维，**必须展示** —— 它同时决定讲解匹配哪份知识点模板；`''` 显示成「**整学年**」而不是空标签（空标签看起来像 bug）；
  3. **交互讲解**：读落库快照（模板后续改动不影响已生成的题）；
  4. 无 `scene_spec` 时**不占位** —— 「没配模板」是常态，不是异常，不该给空态。
  - 画布**压窄到 300**：正方形边长 = 宽度，不压会把弹窗顶出屏幕（同 §O / §P / §Q 的教训）。
- 实测确认**不是 bug**：题目 `semester=''` **不该**匹配「下学期」的知识点模板 —— §J 的规则是「同学期优先 → 整学年兜底」，**不反向跨学期**。
- 验证：`bank_question_detail_test.dart` **7/7**（题干/选项/答案/解析、知识点信息、`''`→整学年、有场景出图、无场景不占位、画布压窄、关闭按钮）；后端实测响应带 `semester` + `scene_spec`（正方形题= 4 顶点）；`flutter analyze lib` 零 issue；前端 **310 passed**、后端 **542 passed**。
- ⚠️ 过程中试图把题库卡片抽成独立文件以压回行数基线，**失败两次**（行号切片吞掉了相邻方法体 → 58 个编译错），已回滚。教训：**多行切片改文件前必须 assert 首尾锚点**；且并行会话正在改的文件**不做大段抽取**。最终只做最小增量（+10 行）—— 该文件本就超基线（既存状态）。

#### S.1 补做：拆 `BankQuestionRow`，把题库视图压回棘轮基线以下

上一节留的尾巴（题库视图 866 行 > 基线 838，棘轮一直红）已做掉：

- 拆出 `BankQuestionRow`（156 行）= 卡片 `_buildItem` + `_tag` + `_usageTag`，回调全部**构造注入**（`onToggle` / `onShowUsages`），本文件不依赖视图私有状态。
- `parent_question_bank_view.dart` **866 → 759**；按 ADR-0058「拆小了就把基线跟着调小」**基线 838 → 759**。
- 结果：**前端全量 311 passed**（此前整轮会话都带着这 1 个棘轮失败）。
- ⚠️ **搬代码块时禁用正则删方法**：`re.sub(r"...标签.*?\n  \}\n", ..., re.S)` 在 DOTALL 下 `.*?` 匹配不到本方法结尾的 `  }` 就**跨进下一个方法**、把 `_buildActionFooter` 方法体吞进删除区 → 58 个编译错（行边界断言是对的，错的是删除用的正则）。**正确做法：块逐行原样搬，只对要改的行做单行精确替换，helper 一律保留只改签名。**
- 另两个小坑：`sed -n 'a,bp'` 输出带尾随换行会让 `split('\n')` 末元素为 `''`（assert 前先 pop）；`AppTheme.colorsOf(context)` 返回 **`AppColors`** 而非 `ColorScheme`。
- 行为等价性逐项核对：多选 onTap / 复选框 / 「用过 N 次」/ 查看详情 / 已归档标签 / 选中描边变 primary，全部确认在新文件内（顺手把 `() => onToggle` 这类冗余 lambda 简化）。

### T. 修两个报障：题库详情无图 + 选项「A. A.」重复标识

#### T.1 题库详情没有交互展示

- **根因**：`list_bank_questions` 返回 `Question.scene_spec` **原始值**，**没有实时回退**；而 `tasks`/`review` 路径是「快照优先 + `build_scene_spec_for_question` 回退」。快照只在**出题那一刻**生成，而模板往往是**之后**才配的 → **题库里的存量题永远出不了图**。
- **修法**：与 tasks/review 同一口径（`q.scene_spec or build_scene_spec_for_question(...)`，带 `scene_cache` 避免同页几十道同知识点题各查一次）。
- 实测（`Question.scene_spec` 仍为 NULL 的老题）：「正方形有几条对称轴」→ **4 顶点**；「下面哪个图形是轴对称图形」→ **选项组 4 项**；「下面哪个英文字母…」→ 5 顶点（arrow 兜底，字母词不在图库）。三档输出同时验证了抽取链路。
- ⚠️ 排查时连踩两个坑（都不是 bug）：模板配在了**别的 parent** 下；题是 `semester=''`（整学年）而模板配在下学期 —— §J 是「同学期优先 + 整学年兜底」，**不反向跨学期**。**验证场景解析前先对齐 parent 与 semester。**

#### T.2 选项重复标识「A. A. 房子」

- **既有契约**：后端 `normalize_options` **刻意不剥**前缀（docstring 明说：答案字段也带前缀，剥离会让判题比对失配）→ 渲染层负责剥 `cleanOptionText`。
- **本次补上 2 处**：① 题库详情弹窗（§S 新写时漏了）；② **助手纯文本题卡 `card_payload.dart`** —— 既存漏网之鱼，自己画了标号却没剥，靠新写的守卫测试才被发现。
- **守卫测试 `tests/ai/test_option_prefix_contract.py`（23/23）**：
  - 7 处渲染点**逐个**断言调用了 `cleanOptionText`；
  - 正则**不误剥正文**（`Apple` / `三角形ABC` / 单个 `A`）；
  - 不变量写成「**画标号 ⊆ 剥前缀**」—— 不是「禁止手工画标号」，因为纯文本卡片没有 `AppOptionTile` 可用，手工编号是合法的。

#### T.3 连带修好：可空 JSON 列写出文本 `'null'`（ADR-0061 §N 全仓）

- `Question.options` 等**12 个可空JSON 列**都缺 `none_as_null=True` → Python `None` 被序列化成**文本 `'null'`** 而非 SQL NULL → `IS NOT NULL` 为真而内容为空。实测 `question.options` 有 **5 行是文本 `'null'`**，读出来是字符串 `'null'` → 任何「这题有选项」的判断都走偏（这正是 §S 排查时偶然撞见的）。
- 模型层**全量统一** + 新增幂等启动迁移 `_nullify_text_json_nulls` 收拾存量（24 行）：只 `UPDATE` 值**恰为** `'null'` 的行，表/列不存在则跳过。实测清零、连跑两次幂等、真选项未被误清。
- ⚠️ 批量改模型声明时翻车两次（正则吞掉 `sa_type=JSON)` 的右括号 → 86 错；补回后又给已正确的行多加括号）。教训同 §S.1：**批量改声明式代码也要逐行判定 + 全仓 grep 复查**。

**验证**：后端 **576 passed**（3 个 vector 既存顺序污染）、前端 `analyze lib` 零 issue + **311 passed 全绿**；`ruff check app` 干净（2 个既存 I001/F401 位于非本次改动文件）。

### U. 修「仍然没有图形」：REST 端点漏字段 + 图库兜底（2026-10-05）

§T 之后用户仍报「没有图形」。两个**独立**根因叠在一起，只修 §T 那一个当然还是没图：

#### U.1 根因一：修错了文件 —— 前端打的是 REST 端点，改的是助手工具

- 前端题库走 `GET /questions` → `features/questions/router.py` + `schemas.py`，而 §T 改的是 `features/questions/service.py`（**助手查询工具**的投影）。两条路径**各有一份 `BankQuestionItem`**，`schemas.py` 那份**根本没有 `scene_spec` / `semester` 字段** → 响应里连 key 都没有，前端 `BankQuestionItem.fromJson` 永远拿到 null。
- ⚠️ **教训**：「下发了 X」必须**打到端点验**（响应体里真的有这个 key），不能只测 service 函数——单测全绿也照漏不误。本次补 `tests/api/routes/test_questions_bank_scene.py` 就是为此：它断言的是**端点响应**，不是 service 返回值。

#### U.2 根因二：库里一条模板都没有 —— 回退解析也救不了

- 实测真库：`knowledgepoint.scenes` **非空 0 条**、`question.scene_spec` / `taskquestion.scene_spec` **非空 0 条**。也就是说「快照优先 + 实时回退」两级**都是空的**，回退查模板必然查不到 → 必然无图。**光修链路不出图是正确行为，不是 bug。**
- 但家长的观感就是「功能没做」：讲解的**几何权威来源是图库**（`scene_figures` ↔ 前端 `figures.dart`），教师模板只提供**默认参数**（默认哪个图形、轴多少度）。题面明写「正方形」时，图库里本来就有权威顶点——**没配模板就不出图**等于让「正方形有几条对称轴」这类最典型的题裸奔。

#### U.3 修法：图库兜底（新增 `default_scene_from_figure`）

- 教师**没配模板**时，若题面/选项**命中图库图形**，按图库合成默认 `reflection` 场景：顶点、默认轴角度、`axisAngles/axisCount` 全部取自图库（§Q 决策 A：轴对齐、零微扰），`editable=true`（学生能自己拖轴去试）。
- **边界（防臆造，与 `extract_scene_inputs` 同纪律）**：命中不了图形就返回 `None`。纯计算题「图书馆有 86 本书」没有图形可讲，硬塞一个图形就是编。
- **不泄题**：引导语只说「点播放看两侧能否重合 / 自己旋转找出所有能重合的角度」，**不出现条数**（「正方形有几条对称轴」的答案就是那个数）。
- **如实**：`outputs.isAxisymmetric = axis_count > 0`（平行四边形 = False）；**带选项组时去掉 `outputs`**——每个选项判定不同（房子对称、平行四边形不对称），父级给统一结论就是替学生答。
- **优先级不变**：教师模板 > 图库兜底（`derivedFrom` 标记来源，便于排查「这图是谁给的」）。

#### U.4 顺带收口：四条读路径共用一个函数

- 新增 `scene_spec_for_read(session, snapshot=..., ...)` = 「快照优先 → 实时解析 → 图库兜底」。此前 `tasks` / `review` / 助手工具**各内联一份** `q.scene_spec or build_...`，`questions` REST **整段漏写** —— 这正是「同一道题换个地方就没图」的成因。
- `review`（错题本）此前**只发快照**、连回退都没有 → 老错题永远没图，一并按同一口径接上（`review_item_to_resp` 新增可选 `session` / `scene_cache`）。

**验证**：真库实测（无任何模板、无快照）——「正方形有几条对称轴」→ square + 4 顶点；「长方形…」→ rectangle；「下面哪个图形是轴对称图形」→ **选项组 4 项**；「英文字母…」→ 无图（字母不在图库，**不臆造**）。后端 **589 passed**（3 个 vector 既存顺序污染）、`ruff` 仅 2 个既存（已核对 HEAD 版本同报）。前端本轮未改动。

**待办（backlog）**：英文字母（H/N/F/G…）尚未进图库，故「哪个字母是轴对称」这类题仍无图——补图库即可，与本次修复无关。
