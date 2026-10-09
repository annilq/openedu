# ADR-0076 课件多图演示（有序图形集）与只读画廊 play 进编辑

- 状态：已采纳（实现完成，已合入 main @ d0197ed）
- 日期：2026-10-08
- 关联：ADR-0067（课件编辑器 · 环节内容块统一化）、ADR-0061（交互图形讲解 §O 选项组 / §V 画廊 / §U 读路径唯一入口）、ADR-0058（文件规模棘轮）、ADR-0051（空态）、ADR-0044/0046（视觉与选中/焦点语言）、ADR-0059（单源导航）、ADR-0073（场景快照不可变）

## 1. 背景（Context）

课件「讲课」页当前一个环节只演示**一张**图形：`section.scene` 是教师从知识点模板**快照式复制**进来的一份 ADR-0061 SceneSpec（`courseware_section_edit_dialog.dart:157-160`），`resolvedScene` 原样取出后交给 `SectionInteractiveScene` → `SceneInterpreter`，最终渲染单个 `ReflectionSceneWidget`（`scene_interpreter.dart:62-64`）。

教学诉求（本 ADR 的驱动力）：

1. 同一场景要**同时摆出多张图形**，让学生**对比着找规律**（哪些是轴对称、哪些不是）。
2. 摆出来的图形应当是**只读**的；每张右上角给一个 play 入口，点开才进入可操作状态（旋转 / 平移对称轴）。

**关键发现：这两件事的主体在仓库里已经存在，不必从零实现。**

- `SceneInterpreter.build` **第一行就先判 `optionGroup`**：非空则渲染 `SceneOptionGroup`，而不是单场景（`scene_interpreter.dart:51-61`）。
- `SceneOptionGroup` 渲染的就是**只读缩略图网格**（静态 CustomPaint，无滑块、无判定），点击整卡弹 `ReflectionSceneDialog`——弹窗里是同一个 `ReflectionSceneWidget`，交互一件不少（`scene_interpreter.dart:139-157`、`reflection_figure_gallery.dart:245-298`）。

即"多图 + 只读 + 点开进编辑"已是 on-the-shelf 能力，缺的只有三件事：**数据从哪来**、**能否编排成有教学意图的子集**、**显式的 play 提示**。

可行性已核实（两条硬前提）：

| 前提 | 结论 | 证据 |
|---|---|---|
| 课件环节能否承载多图数据 | ✅ `CoursewareSection.scene: dict \| None` 是**裸 dict 透传、无多态校验、不剥 key** | `backend/app/features/courseware/schemas.py:58` |
| 讲课页是否需要改造 | ✅ 零改造即自动生效（`section.resolvedScene` → `SectionInteractiveScene` → `SceneInterpreter` 已按 `optionGroup` 分支） | `courseware_present_widgets.dart:132`、`scene_interpreter.dart:51` |

另外两条现存约束决定了方案边界：

- `optionGroup` 目前**只由后端从「题目的选项」抽取**（`scene_extract.py:119-154`）。课件环节没有题目、没有选项 → **没人供给这个列表**。
- `SceneOptionGroup` **硬编码整库 11 个图形**（`figures: kFigureShapes`，`scene_interpreter.dart:141`），且 `_ordered()` 只做"选项置顶 + 库序"，**不支持教师编排子集与顺序**。

## 2. 决策（Decision）

### 2.1 复用 `optionGroup` 作为课件多图的载体，不新增 kind、不改后端 schema

新增一个 kind 或新增独立字段都会把「同一模板派生多份实例」这件事变成第二份平行表达（`optionGroup` 的语义本就如此）。故：

- 课件环节勾选的图形**就地写入本环节 `section.scene['optionGroup']`**；
- 后端**零改动**（`scene` 已是 dict 透传）；
- `item` 形状与后端 `extract_option_group` 完全一致（`label` / `caption` / `figureKey` / `points` / `defaultAxisAngle`），保证 `SceneOptionItem.fromJson` 与门禁 frontend/backend parity 都不用改。

课件语境下没有 A/B/C 选项，故 **`label` 留空串**，`caption` 用图形中文名，**顺序 = `items` 的数组顺序**（教学编排意图就落在顺序里）。

> 与 ADR-0073 快照不可变无冲突：`section.scene` 是"关联时快照复制"进来的**环节级副本**，写入只看本课件的本环节，绝不回写 `kp.scenes` / `Question.scene_spec`。

### 2.2 `optionGroup` 增开 `curated` 开关区分「整库探索」与「教师编排」

`SceneOptionGroup` 现有"整库铺开"是**刻意**的产品决策（`scene_interpreter.dart:104-113`：儿童应能自由探索任意图形）。直接改成按 items 裁剪会**静默改变题库 / 错题路径的行为**——那条路径的 items 是选项，剪掉其余等于剥夺探索。

故加显式开关，`SceneInterpreter` 就地读取后传参，**`SceneInterpreter` 的对外签名不变**（它被多处调用，加参会波及全部消费方）：

```jsonc
"optionGroup": {
  "curated": true,   // true = 只按 items 顺序渲染（课件）；缺省/false = 整库（题库现有行为）
  "items": [ { "label": "", "caption": "正方形", "figureKey": "square",
               "points": [[x,y]…], "defaultAxisAngle": 90 } ]
}
```

`curated: true` 时由 items **按其数组顺序**解析出 `List<FigureShape>` 传给画廊，不再走 `_ordered()` 的库序重排。

> **为什么必须是显式开关而不是「有 items 就裁剪」**：题库路径的 items 恰好也非空（= 选项），两种语境无法靠 items 有无区分，只能靠显式声明。这句是本次改动最容易出静默回归的地方，必须有测试守。

### 2.3 讲课页按数据动态分派（单图 / 多图），不加「大画布 + 画廊」混合形态

> 用户决策原文：**「讲课页面可以根据数据动态判断图就显示网格，而且目前也不一定是交互动画，交互动画也是配置的」**

- 环节**没有** `optionGroup` → 现状单场景渲染路径，**是否可交互仍由 spec 的 `editable` 决定**（`ReflectionSceneData.fromSpec:141`），本 ADR 不改这条口径；
- 环节**有** `optionGroup`（无论 `curated` 与否）→ 画廊网格。

因此**不引入**「上方保留一块 520px 大画布 + 下方画廊」的混合形态：那会把竖直空间翻一倍，且与"是否可交互由配置决定"的现状割裂。

### 2.4 只读卡加 play 角标：统一改共享画廊

> 用户决策：统一改 `ReflectionFigureGallery`（题库 / 错题 / AI 讲解 / KP 编辑器 / 课件共用同一份），不另起平行组件。

- 卡片 `Stack` **右上角**加 play 角标（`LucideIcons.play`，非 Material 控件）；左上角「默认讲解」角标保持不动，两者不冲突。
- **保留整卡可点**（`AppFocusableAction`）：play 是**可见性提示**，不是唯一的命中区——只留小图标做命中区会显著削弱触屏可用性。`AppFocusableAction` 仍是全站可点区唯一语言（ADR-0046），不额外套 `GestureDetector`。
- `semanticLabel` 同步改写（如"播放${figure.label}的对折演示"），保住键盘可达性。

### 2.5 只读视图不标答案，守"只画不判"

> 用户决策：**不在只读卡上标「✓ 轴对称 / ✗ 不对称」**。

一旦标了，学生扫一眼网格就拿到答案，"点开亲手折"这个动作当场死亡，"找规律"退化成"看答案"——这与 ADR-0061 §O 的教学意图（`reflection_figure_gallery.dart:246-248` 的「只画不判」）正面冲突。图形与我是否为轴对称的判断，**只能由学生在弹窗里亲手折出来**。

### 2.6 每张图打开时用「图形自带默认轴」，不用本环节场景配置的轴

`SceneOptionGroup` 与 `KnowledgePointSceneEditor` 目前口径不一致（前者用 `figure.defaultAxisAngle`，后者用面板调出来的轴）。课件多图沿用前者（图形自带默认轴）的原因有实证：

> 若统一套用场景轴（如 90° 竖轴）打开横向的箭头（唯一对称轴是 0° 横轴），画面一开始就不重合，儿童会以为"题目错了"（`scene_interpreter.dart:151-153`、`knowledge_point_scene_editor.dart:288-291` 同口径注释）。

故：`curated` 模式下每张图打开时初始轴取**该图形自己的 `defaultAxisAngle`**，学生进弹窗后可再旋。

## 3. 非目标（Out of scope）

- ❌ 不支持教师上传任意位图当图形——多图集合被锁在内置图形库（`kFigureShapes` / 后端 `FIGURES`，11 个）。自定义顶点是另一条独立议题。
- ❌ 不改后端：不新增端点、不改 `CoursewareSection` schema、不碰 `extract_option_group`（它仍只服务题目）。
- ❌ 不新增 kind、不动 `SceneInterpreter` 对外签名、不改造题库/错题路径的现有观感（整库探索行为必须一字不变）。
- ❌ 不在画廊里做"分组/分类"视觉（如"这组对称/那组不对称"）——那等于变相给答案，违反 §2.5。

## 4. 红线（改动前必读）

1. **零回写**：只写本环节 `section.scene`，绝不 `PATCH` 知识点 `kp.scenes`（ADR-0073）。
2. **离线可用**：`items.points` 在保存时由前端 `kFigureShapes` **展开写入**（它由后端 `scene_figures.py` 经 `gen_figures.py` 构建期生成，`test_frontend_figures_are_not_stale` 钉住 parity）。不要只存 key 让渲染层运行时回查——走廊网络不能成为"图形出不来"的理由。
3. **文件规模**：`reflection_figure_gallery.dart` 现 330 行，加 play 角标与 `curated` 相关参数后逼近 ADR-0058 的 400 行棘轮；超限须按既有先例抽 part 文件（`scene_library_detail_view` 曾因此抽 `_DefaultFigureSection`），不得直接上调基线绕过。
4. **非 push 路由页面禁裸 `Navigator.pop`**：新增的编辑器选择 UI 若在弹窗态，回落 `onBack` 单一出口（ADR-0059）。

## 5. 验证清单

- [ ] `SceneInterpreter`：`curated: true` 只渲染 items 指定图形且**保序**；缺省时题库路径**仍整库 + A/B 角标**（行为零变更）。
- [ ] 讲课页三态：无 `optionGroup` → 单场景；有 `curated` → 子集网格；有非 curated → 整库网格。
- [ ] 只读卡无任何"是否对称"判定标记；点在图形上去旋转/平移轴仍可用。
- [ ] play 角标在触屏与键盘两条路径都可达（`AppFocusableAction` + `semanticLabel`）。
- [ ] 保存后 `items.points` 已展开（离线断网仍能渲染），且不回写 `kp.scenes`。
- [ ] `flutter analyze` 0 issue；全仓 `flutter test` 无回归（含 `scene_option_group_test`、`scene_library_t04_test`、`file_size_guard_test`）。

## 6. 状态（实现记录）

- **状态**：已采纳。实现由 5 个垂直切片票（01 持久化验证 / 02 画廊 play+保序 / 03 解释器 curated 三态 / 04 编辑器勾选写 optionGroup / 05 端到端+回归）落地，经 5 个子代理实现并合入 `feat/courseware-scene-figures`（15 commits，tip `9ad2c28`），已快进合入 `main`（`0cefb81..9ad2c28`）。
- **图标纪律修复**：`scene_interpreter.dart` 2 处遗留 Material 图标（`Icons.help_outline`）由 `fix/scene-interpreter-material-icons` 替换为 `LucideIcons.circleHelp`，合入 `main` @ `d0197ed`（`9ad2c28..d0197ed`）。当前 `main` 远端 = `d0197ed`。

### 6.1 验证结果（全绿）

| 项 | 结果 |
|---|---|
| `flutter analyze` | 0 issue（集成 worktree + fix worktree 两次验证） |
| `scene_interpreter_curated_test` | 10/10 通过（curated 三态：无组→单场景 / curated→子集保序 / 非 curated→整库） |
| 讲课页改造 | `section_interactive_scene.dart` diff 为空——零业务代码改动，ADR-0067 熔断条件守住 |
| 后端改动 | 零功能改动（仅新增 `backend/tests/.../test_courseware_scene_persistence.py` 验证裸 dict 透传） |
| 全仓定向回归 | 10 文件 +83 −4；4 失败 == 文档化基线（`courseware_editor_page_test` 3 条源自 aa23a29 + `no_bare_gesture_guard_test` 1 条 `draggable_assistant_fab` 裸 GestureDetector），**零新增失败** |
| 硬守卫 | `file_size_guard_test` + `feature_boundaries_test` 全绿 |

### 6.2 落地文件

- `frontend/lib/shared/widgets/scene_interpreter/scene_interpreter.dart`（237）：就地读 `optionGroup['curated']` 透传；`AppEmptyState` fallback 图标已转 Lucide。
- `frontend/lib/shared/widgets/scene_interpreter/reflection_figure_gallery.dart`（375）：加 play 角标（`LucideIcons.play`）+ `preserveOrder` 参数；守住 ≤400 行棘轮。
- `frontend/lib/features/courseware/presentation/pages/section_scene_figures_picker.dart`（361，新建）：仅 `kind=='reflection'` 显示，勾选定序写 `optionGroup`。
- `frontend/lib/features/courseware/presentation/pages/courseware_section_edit_dialog.dart`（394）：接入选择器。
- `frontend/lib/features/courseware/domain/models/courseware_section.dart`：`copyWith` 的 `_unset` 哨兵（区分「没传」与「显式 null」）。
- 测试：6 前端（`*_model_test` / `*_picker_test` / `_shared_map_test` / `reflection_figure_gallery_test` / `scene_interpreter_curated_test` / `courseware_present_multi_figure_test`）+ 1 后端。

### 6.3 红线遵守

1. **零回写**：只写本环节 `section.scene['optionGroup']`，未触碰 `kp.scenes` / `Question.scene_spec`（ADR-0073）。
2. **离线展开**：`items.points` 保存时由前端 `kFigureShapes` 展开写入，断网仍可渲染。
3. **文件规模**：画廊 375 / 选择器 361 / 弹窗 394 / 解释器 237，均 ≤400，未上调 `file_size_guard` 基线。
4. **非 push 路由**：新增选择器在弹窗态回落 `onBack` 单一出口（ADR-0059）。
