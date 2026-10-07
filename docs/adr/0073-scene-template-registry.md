# ADR-0073：场景库——单一「场景」概念，`scenes` 为唯一事实源，注册表仅作作者辅助库

状态：草案 v3（收敛为「scenes 为唯一事实源 + 注册表仅作者辅助 + kind 标识存于 scenes[].kind + 去掉 scene_name 列与逃生口双语义」），待评审与实施排期。

## 背景：当前「模板」藏在两处、且「场景」与「模板」是同名不同义的分裂

ADR-0061 确立了知识点场景的三层：声明式 SceneSpec（kind 注册表）+ 知识点模板（`KnowledgePoint.scenes`）+ 题目/课件实例（`Question.scene_spec` / `Courseware.sections`）。落到代码有两处「模板来源」长期并存且语义重叠：

1. **教师模板**：`KnowledgePoint.scenes: list[dict] | None`（`models/material.py:186`），教师基于知识点编写并落库，整份 SceneSpec（含 `kind`）直接挂在知识点行上。
2. **内置兜底**：`default_scene_from_figure`（`scene_fusion.py`，ADR-0061 §U.3）+ `scene_figures.py` 顶点库——题面命中图库图形时，按图库合成一份默认 `reflection` 场景。

两处都围绕同一个 `kind=reflection` 反复描述「默认轴 90° / 默认图形 house / 默认位置 0.5」。而**实测真库 `scenes` 非空 0 条**（ADR-0061 §U.2）——生产里「教师模板」几乎永远为空，真正在用的「默认 reflection」其实只存在于 `scene_figures` + 兜底合成逻辑里，却从没被显式命名为「模板」。

由此引出两议：

- **议①**：是否把「场景」与「模板」收敛成单一「场景」domain，避免冗余？
- **议②**：场景注册表能否放到后台、以 `kind` 为稳定标识（`scenes[].kind` 即该标识）、经接口下发前端；每个 scene = `{kind, list:[{name, value}]}`，前端提供与 `kind` 对应的组件渲染器，并据 `list` 渲染该 scene 包含的图形？

经代码实证与多轮 grill，两议**均可实现**，且边界已逐步收敛（见 §决策与 §已知遗留）。最终拍板：**`scenes` 是唯一事实源，注册表仅作作者辅助库，去掉独立 `scene_name` 列与「逃生口双重语义」**。

### 代码实证（决定可行性的硬事实）

- **「场景」「模板」本就是同一类型**：两者都是 `SceneSpec` dict（`kind`/`title`/`inputs[]`/`controls`/`narrative`/`outputs`/`editable`）。所谓冗余是**命名与解析逻辑的分裂**，不是类型分裂——收敛是概念/解析统一，不是结构重写。
- **`kind` 标识今天已活在 `scenes[].kind`**：`schemas.py:131` 注释 `scenes = [{kind, inputs, controls, ...}]`；编辑器 `_buildSpec`（`knowledge_point_scene_editor.dart:108`）永远写 `kind:'reflection'`。**无需新增列来承载 kind**——它本就在 `scenes` 内部。
- **前端「按 kind 分派渲染器」已是现状**：`SceneInterpreter` 的 `switch(kind){ case 'reflection': ReflectionSceneWidget }`（`scene_interpreter.dart:62`）就是「每 kind 一个组件渲染器」；`ReflectionSceneData.fromSpec`（`reflection_scene_data.dart:90`）读 `inputs[]` 的 `figure`/`points`/`axisAngle`/`axisX`/`axisY`，经 `figures.dart` 顶点库画出图形——正是「据 list 渲染图形」。
- **全工程只有 `reflection` 一个可渲染 kind**：`enum SceneKind { reflection, unknown }`（`scene_interpreter.dart:19`），任何其他 kind 一律 `unknown`→开发者指引空态。**教师今天在任何界面都只能产出 reflection**，写别的 kind 只会静默降级成开发者指引——「教师自定义新类型场景」从未真实存在（见 §决策 7 与已知遗留 7）。
- **当前 SceneSpec 比 `{name, value}` 多三层结构**：`controls`/`narrative`/`outputs`/`editable`/`title` 是**行为/结构**字段，不在 `inputs[]` 里；且 `inputs[]` 原带 `key`/`label`/`type`（议②简化为 `name`/`value`）。
- **图形几何是双副本**：`scene_figures.py`(后端) 与 `figures.dart`(前端) 同一份顶点，靠 parity 测试钉住（ADR-0061 §O）。

## 决策

### 1. 收敛为单一「场景」domain；`scenes` 是唯一事实源

- 收敛后只有一种概念：**场景（Scene）**，其两种存在形态：
  - **命名场景（registry scene）**：存于场景库（作者辅助库），以 `kind` 标识，是默认/共享版，**仅服务于作者体验**（编辑器预填、浏览页枚举）。
  - **实例场景（instance scene）**：落库于题目/课件的快照，是 `scenes` 的深拷贝。
- ⚠️ **`KnowledgePoint.scenes` 始终是唯一事实源**：它永远存「已解析、自包含、完整的 SceneSpec 数组」（含 `kind`/`title`/`inputs[]`/`controls`/`narrative`/`outputs`）。**渲染、题目生成、课件生成只读 `scenes`，永不回查注册表。**
- ⚠️ **命名场景（注册表）绝不参与渲染与生成**——它只是作者辅助库。彻底消除「live 绑定 / 取值引用」的诱惑，快照铁律天然保住（本来就是拷贝 scenes，与注册表无运行时耦合）。
- ⚠️ 致命红线：实例场景（题目/课件）必须存 `scenes` 里解析后的整份副本，绝不可退化为「只存 kind、渲染时回查注册表」。

### 2. 场景库 = 后端注册表，以 `kind` 为稳定标识，经接口下发

- 新增后端模块 `app/features/materials/scene_templates.py`：`BUILTIN_SCENES: dict[str, SceneDef]`，键为 `kind`（与 `scenes[].kind` 同约定），值为该命名场景的定义。`reflection` 为首个种子。
- 经 `GET /materials/scene-library` 下发全部命名场景（含 `kind` + 默认 `list` + `structure` + 关联知识点 + 实例数）；前端拉取后缓存。
- `kind` 为**稳定契约**（如 `reflection`），不随版本重命名；重命名即破坏存量数据与前端分派。**parity 测试钉死 `kind` 不变**。
- ⚠️ **「后台」= 后端模块经 HTTP 暴露，不是 DB 表**（与「无 DB 表」拍板一致：改动随发版，不引入迁移/FK）。
- ⚠️ **后端 API 不能单方面新增「可渲染场景」**：前端必须存在对应的 `XxxSceneWidget` 分派。API 的价值在于①集中下发默认参数值、②给编辑器下拉枚举「后端已知场景」、③给浏览页列内置场景与关联知识点——**不解除前端渲染器注册表这道闸门**（新 `kind` 仍需前端发版）。

### 3. 前端渲染器按 `kind` 分派（已实现，仅是收敛）

- `SceneInterpreter` 的 `switch(kind)` → `ReflectionSceneWidget` 已是「每 `kind` 一个渲染器」的架构。新增场景 = 在 `SceneKindX.fromName` + `SceneInterpreter` 加 case + 新增 `XxxSceneWidget` + `XxxSceneData`。
- 渲染器**从 `scenes[i].inputs[]` 取参数、从图形库取几何**：渲染时只读 `scenes`，`kind` 来自 `scenes[i].kind`。`{kind, list}` 即驱动渲染的数据。

### 4. 场景数据模型 = `{kind, list:[{name, value}], structure?}`

- `list`：可变参数袋（议②核心）。`name`≈原 `inputs[].key`，`value` 为 **JSON 联合类型**（`num`/`str`/`array`）：`axisAngle=90`(num)、`figure="house"`(str)、`points=[[...]]`(array)。**`value` 必须声明为 `any`，不可窄化为 string**（否则 `points` 数组无法表达）。
- 可选 enrich：`{name, value, type?, label?}`——`type`/`label` 供自描述（编辑器回显），渲染器可忽略、自硬编码。保留向后兼容。
- `structure`（建议保留，非议②原始模型）：`controls`/`narrative`/`outputs`/`editable`/`title` 等**行为/结构**字段。两种落点（见遗留 2）：
  - **(A) 移入前端渲染器硬编码**（推荐）：注册表只持参数值，结构由 `ReflectionSceneWidget` 自定。代价：教师不能再按知识点定制 narrative/controls（只能调参）。
  - **(B) 留在场景 JSON 的 `structure` 子对象**：保留 per-KP 覆盖结构能力，但扁平 `list` 表达不了嵌套 → 需 `structure` 独立成块。
- ⚠️ **`figure`/`points` 不预填进注册表条目**（继承 §决策 6「house 实为前端兜底」结论）：注册表只定义结构与中性种子（轴 90°/位 0.5），`figure` 留空，由题面 stem 注入或在编辑器预览时回落前端 `house` 网。

### 5. 生成时取值——直接拷贝 `scenes`，不再 live 解析

- 题目生成：`Question.scene_spec = deepcopy(kp.scenes[0])`（已是完整解析副本）。
- **`resolve_kp_scene(kp)` 退化为薄读取器**：返回 `kp.scenes`（校验为完整 SceneSpec 数组），**不再做「registry base + override 合并」**——因为 `scenes` 本身即完整真相，override 在编辑器保存时已并入完整 scenes。
- 读路径 `scene_spec_for_read` 仍「快照优先」（不变）。
- 注册表改动**绝不影响已存 `scenes`**（scenes 从不引用注册表）→ 快照不变量比早期草案**更强**（早期草案还预留了 registry base 取值路径，本 v3 彻底切断）。

### 6. 后端兜底与注册表的关系（重构而非并存）

`default_scene_from_figure` **不再是并行硬编码合成器**，而是重构为 `instantiate_builtin("reflection", overrides={figure, points, axisAngle…来自 stem})`——即以 `SCENE_LIBRARY['reflection']` 为**结构基** + 注入题面图形，产出**完整 resolved SceneSpec**（不是引用）。此路径与 KP 的 `scenes` 无关（stem 驱动、无 KP 关联），`house` 兜底只存在于前端 `ReflectionSceneData`（永不空网），后端在 stem 无图形时返回 `None`（与现状一致，不退化成 house）。

### 7. 编辑器：下拉选 `kind` + 预填 + 调参 + 实时预览

- 判定「未配置」= `scenes is None/空` → 弹开发者指引、不渲染表单（逐字保留用户约束）。
- 配置态：从注册表下拉选 `kind`（如 reflection）→ 编辑器以 `SCENE_LIBRARY[kind]` 预填**完整 scenes**（默认参数 + 结构）→ 教师微调 override 参数 → **保存时回写完整 resolved scenes**（含 `kind`）。`scenes` 始终是完整自包含场景。
- **教师 UI 只提供注册表内置 `kind`；无法造出非内置 kind**（与今天 `_buildSpec` 永远写 `reflection` 的行为一致）。这正契合「交互类型由开发者定、教师端很难自定义」——新增 kind = 开发者工作流（前端 `SceneKind` 加枚举 + 实现渲染器 + 后端词汇表对齐 + 几何同步），教师不参与。

### 8. 图形几何来源（建议吸收进后端，消 parity，可选增强）

- 当前 `scene_figures.py`(后端) 与 `figures.dart`(前端) 是同一份顶点的**双副本**，靠 parity 测试钉住（ADR-0061 §O）。
- 建议：场景库同时下发图形几何（`GET /materials/scene-library/figures` 或 scene 内 `figure` 解析为 points），后端成为图形顶点**单一事实源**，前端 `figures.dart` 退场 → 消除 parity 负担。此为可选增强、扩大本 ADR 范围；**完整功能差异与收口方案见遗留 4**，若暂不做，图形库仍双副本。

## 迁移与兼容性

- **不新增任何列**：删除 ADR-0073 早期草案的 `scene_name` 列方案——`kind` 标识直接来自 `scenes[].kind`，无需独立列，亦无需把 `scene_name` 持久化进落库快照。
- **`scenes` 恒为完整自包含场景**：不再有「空 `scene_name` → 整份逃生口」双重语义；`scenes` 永远是完整 resolved 副本（无论来自教师编辑还是 stem 兜底）。
- **`none_as_null=True`**：`scenes` 列已带（ADR-0061 §N）。
- **存量兼容**：真库 `scenes` 非空 0 条（ADR-0061 §U.2），无需数据迁移；既有 `scenes[].kind='reflection'` 存量原样有效，与注册表 `kind='reflection'` 自然对齐。
- **前端**：`SceneInterpreter` 分派已就绪；编辑器交互形态见决策 7（下拉选 kind + 预填 + 调参 + 回写完整 scenes）。

## Consequences

- **后端新增/改动**：`scene_templates.py`（`BUILTIN_SCENES` + `get_builtin_scene` + `GET /materials/scene-library` + 关联知识点/实例数聚合）；`resolve_kp_scene(kp)` 退化为薄读取器（返回 `kp.scenes`）；`scene_fusion.py` / `scene_spec_for_read` / 课件生成改读 `kp.scenes`；`default_scene_from_figure` 重构为注册表消费者。
- **前端新增/改动**：`knowledge_point_scene_editor.dart` 从「编写整份」改为「下拉选 kind + 注册表预填完整 scenes + 调 override + 回写完整 scenes」；`SceneInterpreter` 分派按 `kind`；其余题卡/错题卡/课件渲染零改动（只读 `sceneSpec`）。
- **约束/兼容性**：快照不变量不变且更强（scenes 从不引用注册表）；「未配置弹指引」UX 不变；注册表仅作者辅助、绝不参与渲染/生成；`kind` 走注册表、不接受自由字符串（ADR-0061 §E）。
- **不在本 ADR 内（首批实施范围）**：DB 支撑的模板表 / 运行时编辑 / 版本化（与「无 DB 表」拍板冲突，另立 ADR）；多对多关联（推迟）；`structure` 落点选择（遗留 2）。图形几何吸收进后端**建议并入本 ADR 作为子阶段**（详见遗留 4），而非另立 ADR。

## 验证判据

- 后端 `tests/features/materials/test_scene_template_registry.py`：
  - `get_builtin_scene('reflection')` 返回权威默认 `list`（轴 90°/位 0.5、中性种子、figure 为空）；未知 `kind` → `None`；
  - `GET /materials/scene-library` 返回结构与 `BUILTIN_SCENES` 一致，且 `associated_knowledge_points` / `instance_count` 由扫描 `scenes[].kind` 聚合正确；
  - `resolve_kp_scene(kp)` 返回 `kp.scenes`（完整副本），不再做 registry 合并；**改写 `BUILTIN_SCENES['reflection']` 后，已落库的 `Question.scene_spec` 快照断言不变**（更强：因从不引用注册表）；
  - **`kind` 稳定性断言**：重命名/版本变更不破坏存量 key。
- 复用：`test_scene_fusion.py` / `test_scene_figures.py` 仍绿；`test_scene_extract.py` 不受影响。
- 前端：`flutter analyze lib` 零 issue；`scene_editor_dialog_test` 断言「选 kind + 预填 + 调 override + 回写完整 scenes」形态、`scenes` 空时仍弹开发者指引；全量 311 例不回归。

## 已知遗留

1. **立即收益有限、基础设施近乎免费**：真库仅 1 个轴对称知识点，`reflection` 共用收益要等 ≥2 个知识点设 `scenes[].kind='reflection'` 才显著。推进性价比：① 隐式兜底显式化；② 统一题目/课件解析入口（修 ADR-0061 §U.4 散落根因）；③ 为将来多图形 kind 铺「定义一次、编辑器枚举」骨架。
2. **`structure` 落点未定（A 移前端 vs B 留 JSON）**：直接决定教师能否按知识点定制 narrative/controls。议②原始模型偏 A（注册表只持参数），但会收窄 override 能力。需拍板。
3. **后端 API 不能新增可渲染场景**：新 `kind` 仍需前端 `XxxSceneWidget` 发版。API 仅做参数集中与编辑器枚举、浏览页聚合。
4. **图形几何是否吸收进后端（消 parity）——强烈建议做，且与本 ADR 同源**

   当前 `scene_figures.py`(后端) 与 `figures.dart`(前端) 是同一份「轴对称教学图形几何库」的 **Python / Dart 双语孪生副本**。顶点逐点相同，但角色与一处行为存在真分歧。本 ADR 收敛的是「场景定义/默认参数」，而**真正的「前后端双份手写副本」其实在几何库这里**——注册表收敛并不能消掉它，须单独处理。

   **① 各自在系统里的功能**
   - 后端 `scene_figures.py`（`materials` 模块内）：`figure_by_key(key)` 供 `default_scene_from_figure` 兜底合成；`FigureShape.to_dict()`（`scene_figures.py:42`）把几何序列化为 `{"key","label","points":[[x,y]...],"defaultAxisAngle","axisAngles","axisCount"}`，**经线上下发**（选项组 `optionGroup` 每项 `points` 即来自此，`SceneOptionItem` 消费）。角色 = 几何数据的**发货源**（wire format 权威）。
   - 前端 `figures.dart`（`shared/domain`）：`kFigureShapes` 供 `ReflectionFigureGallery` 渲染**整库网格**（ADR-0061 §V，离线无需联网）；`figureByKey(key)` 被 `SceneOptionGroup._matchFigures` 用于把后端下发的 `points` 反查回图形（取 `label` 角标），并被 `ReflectionSceneData` 当**永不空兜底**。角色 = **离线画廊源 + 解析兜底**。

   **② 共同点（确实同一份数据，parity 测试钉死）**
   - 图形集一致：house / kite / arrow / para / square / iso_triangle / eq_triangle / rectangle / iso_trapezoid / trapezoid_gen / quad_gen（11 个）。
   - 坐标系统一致（0..1 归一化、y 向下）；11 个图形 `vertices` 逐点值**实测一致**（含 square 0.28/0.72）。
   - `axis_angles`（para / trapezoid_gen / quad_gen 故意空 = 真无对称轴）、`axis_count` 如实返回 0（不兜底成 1，防教错）、设计意图注释（para 刻意错切、arrow 故意水平）两端一致。

   **③ 差异（三处，第一处是真分歧）**
   - **差异 1（真分歧｜行为）**：`figure_by_key` 未命中时，后端返回 `None`、调用方据此降级**不静默回落**（`scene_figures.py:232-236`）；前端返回 `kFigureShapes.first`（**house**）「避免空场景」（`figures.dart:213-216`）。→ 题面无图形时后端合成不出图（`None`），前端若拿空 figure 却渲染成房子。这正是「`house` 实为前端兜底、后端注册表绝不预填 figure」（决策 6）的根因。
   - 差异 2（实现）：后端 `NamedTuple` + `to_dict()` 序列化器；前端 `const class` + `const` 列表，原生无需序列化。
   - 差异 3（风格）：square 后端 `_square_vertices()` 程序生成（cx/cy=0.5, half=0.22），前端字面写死同一 4 点（输出一致）。

   **④ 为什么今天必须两份（文件头自述）**
   - 部署隔离：运行时后端读不到前端源码目录，无法 import Dart。
   - 教学素材非算法产物：顶点人工设计（para 刻意错切、arrow 故意水平），须固化存储。
   - 前端须离线渲染整库画廊：不能每次渲染都问后端要几何。

   **⑤ 收口提案（后端成为几何单一事实源）**
   让后端 `to_dict()` 经 `GET /materials/scene-library/figures`（或场景内 `figure` 解析为 `points`）下发，前端 `figures.dart` 退场、改为**拉取缓存**（沿用决策 2「随包内置缓存」部署形态）。收益：① 顶点只维护一份，消除 parity 负担；② 差异 1 的 house 兜底分歧可统一——几何来自后端同一份，查不到即真无图，前端不再需要「永不空」网。此为可选增强、扩大本 ADR 范围，但**比「参数集中」收益更大**，建议并入而非另立。若暂不做，几何库仍双副本、parity 测试继续钉死。
5. **「关联」语义必须锁定为 scenes 拷贝（致命）**：题目/课件只拷贝 `kp.scenes`，绝不持有对注册表或 `kind` 的 live 引用。`kind` 仅作分类/分派标识，不作为数据来源。
6. **override 合并不再发生于生成期**：override 在编辑器保存时即并入完整 `scenes`；`resolve_kp_scene` 仅做薄读取校验。校验点转为「编辑器回写的是完整 resolved scenes（含 kind）」，而非生成期合并逻辑。
7. **教师自定义场景逃生口已删除**：因「所有交互都需前端组件、kind 由开发者定、教师端难自定义」已被代码实证（全工程仅 `reflection` 一个可渲染 kind，教师 UI 只能产出它）。故不再保留「非内置自定义 scenes」逃生口概念；`scenes` 始终是完整自包含场景，无论 kind 是否在内置注册表中（非内置 kind 仅渲染时走 `unknown`→开发者指引，不报错）。
