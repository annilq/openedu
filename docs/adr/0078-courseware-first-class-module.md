# ADR-0078 课件模块一等化：独立新增入口 + 课件信息编辑 + 手动添加环节 + AI 作辅助

- 状态：提案（待评审）
- 日期：2026-10-09
- 关联：ADR-0067（课件编辑器 · 环节内容块统一化）、ADR-0076（课件多图演示 / 只读画廊）、ADR-0077（课件素材库 · 纯教师上传 + 多选 picker）、ADR-0074 v4（知识点场景配置收拢到场景库详情页）、ADR-0066（空课件纪律）、ADR-0059（单源导航）、ADR-0051（空态）、ADR-0044/0046（视觉与选中/焦点语言）

## 1. 背景（Context）

课件模块当前不是一个一等公民，而是「从知识点行进入 → AI 代写」的副作用产物。四件用户反馈其实是同一个根因的四种表现（已读代码核实，非凭记忆）：

1. **新增入口散落**：左侧「课件」菜单页（`CoursewareCenterScreen`）只有列表 + 每卡「编辑/讲课」，空态文案还写「去资料库选知识点」。真正的创建入口藏在 `knowledge_point_row.dart` 的「课件」**行内动作**里 → `CoursewareEditorPage(knowledgePointId)`。课件模块自身没有"新增"动作。
2. **课件信息无编辑入口**：编辑器页标题直接用 `widget.kpName`，从不展示/编辑课件级信息（标题、状态）；中心卡的「编辑」只 push 编辑器（编辑的是**环节**不是课件信息）。后端 `PATCH /{id}` 已支持 `title`/`status`，但前端没接。
3. **讲解环节只能删不能加**：`editor_section_list.dart` 头部只有「选择」(批量删)，没有「添加环节」。环节只能来自 AI 起草/重起草。
4. **AI 是唯一作者**：后端 `create_courseware` **强制** AI 起草整份（标题 + 全部环节）；前端 `_createFirst` 点「新增课件信息」即全量 AI。用户无法"先选知识点 + 填信息，再让 AI 补充"。

此外，两点核实结论影响方案：

- **`kind` 字段并非结构驱动**：渲染层 `PresentStage._buildBody` 实际「按填了什么渲染」（有素材→图廊、有场景→交互演示），`kind` 只影响编辑器列表的标签/图标、以及 present 里一句不同的空态文案。`CoursewareSectionKind` 只有 `mediaGallery / interactiveScene / practice` 三种，没有"纯讲解话术"类型。用户明确：环节内容都是配置选择的（提问/素材/场景），**无需类型化** → 去掉 `kind`。
- **AI 起草当前不回填素材/场景**：`draft_sections` 只从教材召回**文本片段**当 prompt 上下文，AI 产出 `kind+title+话术+payload`，`materials`/`scene` 留空（service 注释：「LLM 当前不生成，留作前向兼容」）。用户期望的"AI 从服务端拿提问/素材/场景三项数据回填"**尚未实现**。
- **`practice` 环节在演示页不可见**：`SectionPractice` 部件已实现，但 `PresentStage._buildBody` 没有调用它（present 只渲染素材+场景）。去掉 `kind` 后练习内容（`qtype/count`）需要新归宿。

## 2. 决策（Decision）

### 2.1 课件成为一等模块：中心页新增「新增课件」主入口（问题1）

- `CoursewareCenterScreen` 顶部加「新增课件」主按钮（`AppPrimaryButton`）。点击 → 新建表单 `courseware_create_sheet.dart`：
  - **选知识点**：列出本人已转正知识点（可按学科·年级·学期/名称检索），必选；后端 `CoursewareCreate.knowledge_point_id` 本就必填。
  - **标题**：可选，留空则回落知识点名（沿用 `create_courseware` 现有回落逻辑）。
  - **教学目标/备注**：可选自由文本，传给 AI 当起草依据（见 2.5）。
- 保留 `knowledge_point_row.dart` 的「课件」行内入口作为次级快捷（两者通向同一新建流程）。
- 空态文案改为「点上方『新增课件』，选一个知识点即可备课」。

### 2.2 课件信息可编辑（问题2）

- `CoursewareEditorPage` 顶部加「课件信息」卡片：标题（=`displayTitle`）+ `学科 · 年级 · 学期` + 状态（`草稿`/`可上讲台`）+「编辑」动作。
- 「编辑」→ 小弹窗改 `title` 与 `status`，经已有 `PATCH /{id}` 落库（**无需新端点**）。
- `subject/grade/semester` 是知识点快照、展示用，不在课件信息里改（避免与知识点源脱节）。

### 2.3 环节去 `kind` 化（用户拍板：无需类型化）

- **后端**：`CoursewareSection.kind` 由必填改为**可选**（`kind: str | None = None`）；`SECTION_KINDS` 注册表与 `validate_section_kinds` 放宽（未知/空 kind 不再 422，旧数据带 kind 也照常读）；AI 起草 `_DraftSection` 不再输出 `kind`。
- **`compute_section_diff` 匹配键**：由 `(kind, title)` 改为 `(title)`，避免去 kind 后把所有环节判成新增；同名多段仍按出现顺序消费。
- **前端**：`CoursewareSectionModel.kind` 保留为可空只读字段（兼容旧数据），**渲染与编辑都不依赖它**；`editor_section_list` 列表标签/图标改为按「填了什么」推断（有场景→交互、有素材→素材、否则→讲解）；`PresentStage` 删除 `kind == interactiveScene` 分支，统一走"按内容渲染"的空态文案；`CoursewareSectionKind` 枚举标记 `@deprecated`，不再新增调用点。
- 旧课件（`kind` 非空）照常工作；新课件 `kind` 落 `null`/省略。

### 2.4 手动添加环节（问题3）

- `editor_section_list.dart` 头部加「添加环节」按钮（与「选择」并列）。点击 → 打开现有 `CoursewareSectionEditDialog`，传入一个**空白 `CoursewareSectionModel`**（无 kind、无内容）→ 教师配提问/素材/场景 → 保存即 append 到 `sections` 并经 `PUT /{id}/sections` 整体覆盖写。
- 因 2.3 已去 kind，添加环节**不需要 kind 选择器**，与用户"每个环节的内容都是配置选择的"一致。

### 2.5 AI 降为辅助：先空壳，再「AI 补充讲解」（问题4）

- **新建改空壳**：`create_courseware` 新增 `draft: bool = True` 参数；`draft=False` 时只按知识点快照建一个**零环节**课件（不调 AI、不抛 LLM_UNAVAILABLE）。前端 `_createFirst` 改为 `createCourseware(draft: False)` → 进入空课件。
- **「AI 补充讲解」按钮**：空课件（或任意课件）点此按钮 → 复用现有 `redraft_diff`（空课件时 diff 全为 `added`）→ 教师逐段接受 → `PUT /sections` 写回同一课件。**AI 不再进入即自动起草**，完全由用户显式触发。
- **三项数据回填**（后端增强）：`draft_sections` / `redraft_diff` 起草前先查该知识点的
  - 素材库 `CoursewareAsset`（`knowledge_point_id` 过滤），取 `(id, name)` 候选；
  - 场景库场景模板（`get_knowledge_point_scenes`）；
  把候选 id 清单喂给 LLM，让其在产出里**引用真实 `materials[].asset_id` 与 `scene`**，而不是留空或编造。`_recall_snippets` 继续作为话术依据保留。
- 编辑器空态：无课件的「新增课件信息」→ 改为「新增课件」（建空壳）；有空课件的提示改为「点『AI 补充讲解』按知识点生成环节草案」。

### 2.6 课堂练习在演示页可见（2.3 的连带决策）

- 去 `kind` 后 `practice` 类型消失，`SectionPractice` 与 `payload={qtype,count}` 需新归宿：**把"课堂练习"作为环节的第四个可选内容块**（练习配置：题型 + 题量 + 提示），由 `PresentStage` 显式调用 `SectionPractice` 渲染（闭合当前 present 不可见的潜在 gap）。
- 若本轮不想引入练习内容块，则明确**暂不支持练习环节**（ADR-0067 既有的 `practice` 起草在 AI 起草里停用，已存在的练习课件降级为"只有话术"空态）。本 ADR 默认走"练习内容块"路线；具体取舍在 T06 落地时由本会话最终确认。

## 3. 后果（Consequences）

### 正面
- 课件成为一等模块：新增/编辑/手动增删环节全部在课件内闭环，不再依赖"先去知识点行"。
- AI 定位清晰：默认不自动写，教师先选知识点+填信息，再按需「AI 补充讲解」，符合"辅助"定位，也满足 ADR-0066「不伪装空课件」纪律。
- 环节模型更简单：去掉 `kind` 后，环节 = 统一的 {标题, 话术, 素材, 场景, 练习} 内容块容器，编辑器/演示/AI 三处逻辑收敛。

### 负面 / 风险
- **2.3 是最大改动面**：动后端契约（`CoursewareSection.kind` 可选）+ 前后端渲染/编辑 + diff 匹配键 + 测试（含 `file_size_guard`、`test_layering_invariants`）。必须保留旧数据兼容（旧 `kind` 照读）。
- **2.5 后端增强**：AI 起草要查素材/场景候选并让 LLM 引用真实 id，起草 prompt 与 `_DraftSection` 契约要扩；未配模型时"AI 补充"仍走 `LLM_UNAVAILABLE`，不落空课件。
- **2.6 取舍未完全闭合**：练习到底是内容块还是暂不支持，需在 T06 实现前在本会话确认（不得静默丢弃已有练习课件）。
- 新增「新增课件」表单需要**知识点选择器数据源**：列出本人已转正知识点、可按名称检索。复用 `knowledgeManageProvider` 的加载/检索逻辑，或新增一个轻量 `GET /knowledge-points`（按教师 + 可选检索）端点；T01 落地时定。

### 验证纪律（各票共同）
- `flutter analyze lib/features/courseware` 0 issue；编辑器/中心/演示测试全绿；
- 后端 courseware 模块 + 分层守卫（`tests/ai/test_layering_invariants.py`）通过；
- 全程不引入 Material 系控件；`presentation/` 不 import `*/data/`；单文件 ≤400 行（ADR-0058）；
- 去 kind 后补回归测试：旧带 kind 课件仍能演示、新无 kind 课件能与 AI 补充互写。

## 4. 文件级改动清单（概览）

**前端**
- `courseware_center_screen.dart`：加「新增课件」按钮 + 空态文案 + 卡片跳转。
- 新增 `courseware_create_sheet.dart`：知识点选择器 + 标题 + 教学目标。
- `courseware_editor_page.dart`：顶部「课件信息」卡片 + 编辑；空态改建空壳；「AI 补充讲解」按钮。
- `editor_section_list.dart`：加「添加环节」；列表标签/图标按内容推断。
- `courseware_present_widgets.dart`：删 `kind` 分支，统一按内容渲染；显式调用 `SectionPractice`。
- `courseware_section.dart` / `courseware_section_kind.dart`：`kind` 转可空只读 + 枚举标记 deprecated。
- `courseware_repository_impl.dart`：`createCourseware(draft:)` 透传；如需新增 KP 检索端点则接上。

**后端**
- `schemas.py`：`CoursewareCreate.draft: bool = True`；`CoursewareSection.kind: str | None = None`。
- `service.py`：`create_courseware` 支持 `draft=False` 建空壳；`draft_sections`/`redraft_diff` 查素材+场景候选并让 LLM 回填；`validate_section_kinds` 放宽；`compute_section_diff` 匹配键去 kind。
- `router.py`：如 T01 需知识点检索端点则新增（默认复用既有）。

**文档**
- `CONTEXT.md` 课件术语段：去掉 kind 分类，改为"环节 = 内容块容器（提问/素材/场景/练习）"。
