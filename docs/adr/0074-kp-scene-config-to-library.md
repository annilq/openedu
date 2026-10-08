# ADR-0074：交互讲解配置入口从知识点管理迁移到场景库

状态：草案（基于 ADR-0073 收敛后的 UX 整合；待评审与实施排期）

修订：第 2 版——新增 §7「kind 级默认图形管理」，修正原 §3/§4「注册表不动、库不预填图形」的表述：
kind 级默认图形需可写持久化（新增 `scene_template_config`），但注册表作为结构种子源的身份不变，
`kp.scenes` 仍唯一事实源（默认图形只经 seed 注入 KP 实例，不构成 live binding）。

## 背景

知识点管理行内有一个「讲解」按钮（`knowledge_point_row.dart`），点开 `KnowledgePointSceneEditor`
为某个已落库知识点编写默认交互讲解模板（写入 `KnowledgePoint.scenes`）。同时，场景库
（`scene_library_view` / `scene_library_detail_view`，ADR-0073）已经以只读方式列出每个内置场景
被哪些知识点引用、以及它们的图形与预览。

两处指向**同一个概念**——知识点的交互讲解实例——却分散在两个入口：

1. **知识点管理行**：负责「写」（`scenes` 的编写/覆盖）。
2. **场景库详情页**：只负责「看」（聚合 `kp.scenes` 反查出的关联知识点，只读预览）。

由此带来两个问题：

- 教师要在两个地方理解「场景」这件事，概念被拆散；场景库本应是一站式管理面，却只能看不能改。
- 场景库详情页已天然按 kind 把「所有关联知识点的实例」收拢在一处，是比知识点行更合理的
  配置落脚点——但当前它缺写能力，导致「配置」只能绕回知识点行。
- **场景与图形割裂**（用户补充）：讲解弹窗的图形画廊（`ReflectionFigureGallery`，11 图形）只活在 KP
  编辑器里，场景库看不到也管不了图形——「场景类型」在库、「图形选择」在 KP 弹窗，两件事被拆到两处。

用户诉求（经 grill 钉死）：把「讲解」配置从知识点管理挪到场景库，在场景库里统一配置实例（含图形与默认图形），
知识点管理行去掉「讲解」按钮。

## 决策

### 1. 场景库详情页升级为「可写配置入口」

`scene_library_detail_view` 从只读列表升级为配置面，具备两种能力：

- **编辑已关联实例**：点任一 `_InstanceCard` 打开 `KnowledgePointSceneEditor`（复用，传入该
  KP 的 `id/name/subject/grade/semester/scenes`），改完经现有 `saveScenes` 写回。
- **新增「关联知识点」**：把尚未关联某 kind 的知识点加进该场景——选一个未关联的 KP，写入一份
  seed 场景（`kind` + 注册表中性轴参数 + §7 的库默认图形），使其进入库清单。

### 2. 知识点管理行去掉「讲解」按钮

`knowledge_point_row.dart` 删除「讲解」`AppTextAction` 及其打开编辑器的整条链路（含「尚未配置
讲解资源」确认框、`kp.semester` 传参等）。保留「课件」入口。「未配置弹开发者指引」的空态逻辑
迁移到场景库详情页：当某 kind 的 `associated_knowledge_points` 为空时，显示「在场景库给某知识点
关联此场景」（文案更新：原「去知识点管理」改为「在场景库关联」）。

### 3. 事实源不变（不碰 ADR-0073 红线）

- 写入仍落 `KnowledgePoint.scenes`；渲染、出题、课件生成只读 `scenes`，**永不回查注册表**。
- 后端 `scene_templates.py` 注册表仍只作**结构种子源**（inputs 骨架）——所谓「库变可写」是
  **前端多了一个写 `kp.scenes` 的入口** + §7 新增的 kind 级默认图形配置，不是注册表变成事实源。
  （注：原稿此处写「注册表本身不动」，第 2 版修正为「注册表作为结构种子源的身份不变」，
  因 §7 需新增持久化的 `scene_template_config`；详见 §7。）

### 4. 图形 `figure/points` 按知识点各自选，库默认仅作 seed

库详情页的编辑器内仍用 `ReflectionFigureGallery` 逐个 KP 选/改图形（grill 已确认：保留 KP 可覆盖）。
注册表中性种子仍 `figure=''`（ADR-0073 决策⑥）；**关联写 seed 时**，`figure/points` 改从 §7 的
`scene_template_config.default_figure_key` 注入（不再是空占位）。库不预填图形到注册表、不统一图形——
避免「平移类点也显示房子」的误导。

### 5. 学期沿用各知识点自身学期，匹配规则不变

每个实例卡携带的 `semester` 即该 KP 的学期；改 scene 不移动知识点，匹配规则「先同学期→回落整学年」
不变（ADR-0061 §J）。

### 6. 不新增「库级默认实例」实体

注册表 seed（轴 90°/位 0.5）即是共享默认；per-KP 通过「选图形 + 调轴」做 override。用户原话
「在场景库设置默认」在此模型下由 §7 的 `default_figure_key`（种子）满足，而非新增「库级默认实例」
这一会诱发 live binding 的概念。

### 7. kind 级「默认图形」管理（消除场景 / 图形割裂）

背景：讲解弹窗的图形画廊（`ReflectionFigureGallery`，11 图形）只活在 KP 编辑器里，场景库看不到也管不了
图形——用户感知为「场景与图形管理割裂」。本扩展把图形选择上提到场景库：库在 kind 层级展示该场景的图形集
并标记一个默认图形，使场景库成为「场景 = kind + 图形集 + 默认图形」的唯一管理面。

决策（经 grill 钉死）：

- **库详情页 kind 层级展示图形画廊 + 默认图形**：教师在此把某个图形标为 `default_figure_key`。
- **默认图形 = 种子，非事实源**：KP 关联该 kind 时，seed 场景的 `figure/points` 从该默认图形注入
  （复用 `knowledge_point_scene_editor._pickScene` 的同款注入逻辑）。库改默认**只影响新关联 / 显式
  「重置为库默认」**，绝不回写已落库的 `kp.scenes` 与 `Question.scene_spec` → ADR-0073 快照铁律守住。
- **保留 KP 可覆盖**（grill 确认）：关联后的 KP 在库内编辑实例时仍可改成自己的图形（如 house→butterfly）。
  库默认只是起点，不是强制唯一。
- **仅设默认图形、不裁剪可用集**（grill 确认）：库不维护 per-kind allow-list，11 图形全开放；管理深度到此为止。
- **图形几何不搬进库**：仍由共享图形库 `scene_figures.py`（`kFigureShapes`）提供顶点；库只存 `default_figure_key`
  （引用 key），不复制顶点。ADR-0073 边界③（注册表不预填 figure）维持——注册表中性种子仍 `figure=''`，
  默认图形来自下方新增的持久化配置，而非注册表本身。

对原 §3 / §4 的修正：kind 级默认图形需要**可写、持久化**，而当前 `SCENE_LIBRARY` 是 `scene_templates.py`
里的代码常量（只读、非持久化）。故新增轻量持久化配置 `scene_template_config(kind PK → default_figure_key)`，
由库 UI 读写；注册表本身仍只作**结构种子源**（inputs 骨架），不承载默认图形。这是对 0074 原 §3
「注册表不动」的修正——本扩展确实引入一处小的数据模型新增（kind 级配置），但注册表作为结构种子源的身份不变，
且 `kp.scenes` 仍是唯一事实源（默认图形只经 seed 注入 KP 实例，不构成 live binding）。

## 与 ADR-0073 的关系

- **扩展**其 UX 边界：场景库从「只读浏览/聚合」变为「可写配置入口」，并新增 kind 级默认图形管理。
- **不改**其红线：`scenes` 唯一事实源；渲染/出题/课件永不回查注册表；实例存完整副本（快照不可变）。
- **显式排除**「库做事实源 / live binding」解读——那会让已出题目随库默认改写，破坏快照不可变，
  ADR-0073 Out-of-Scope 已明确拒绝。本 ADR 只动前端入口位置、库详情页能力，以及 §7 一处小的
  kind 级配置（默认图形经 seed 注入，不回写已落库）。
- **新增**一处小的数据模型：`scene_template_config`（kind 级默认图形，可写持久化），修正本 ADR 原 §3
  「注册表不动」的表述；注册表仍只作结构种子源，红线（scenes 唯一事实源 / 快照不可变）不受此影响。

## 实施要点

### 前端

- `scene_library_detail_view.dart`：每个 `_InstanceCard` 可点进 `KnowledgePointSceneEditor`（复用，
  传 `id/name/subject/grade/semester/scenes`）；新增「关联知识点」入口（选未关联 KP → 写 seed 场景）。
  **kind 层级新增图形画廊 + 默认图形标记**（§7）：读取 `SceneLibraryItem.default_figure_key`，提供「设为默认」。
- `knowledge_point_row.dart`：删「讲解」按钮 + 确认框 + `kp.semester` 传参；保留「课件」。
- `knowledge_point_scene_editor.dart`：无需大改，仅调用方从 KP 行变为库详情页；空态开发者指引保留在
  编辑器内（未配置时仍弹 `SceneDeveloperGuide`）；关联写 seed 的图形成因从 §7 默认图形取（见 §4）。
- 库详情空态文案更新（指向「在场景库关联」，而非「去知识点管理」）。

### 后端

- 编辑 / 新增实例均复用现有 `PATCH /materials/knowledge-points/{kpId}/scenes`
  （`update_knowledge_point_scenes`）。
- **新增 `scene_template_config` 表与读写端点**（§7）：`kind` 主键 + `default_figure_key`；
  `GET /materials/scene-library` 的 `SceneLibraryItem` 附带 `default_figure_key`；
  新增 `PUT /materials/scene-library/{kind}/default-figure` 写默认图形（kind 稳定契约、只弃用不重命名）。
  注册表 `SCENE_LIBRARY` 不动，仍作结构种子源。「关联知识点」写 seed 时由 `default_figure_key` 注入图形。
- 「关联知识点」picker 的数据源：复用现有知识点列表（教师域），**前端过滤掉已关联该 kind 的项**；
  无需新增端点（或可选新增「未关联 KP」端点，见已知遗留 1）。
- 数据已就位：`GET /materials/scene-library` 的 `SceneLibraryKpRef` 已带 `scenes` + 学科/年级/学期，
  库详情预览与编辑器预填零新增后端字段（测试 `test_scene_templates.py:182` 已断言 `scenes` 透传）。

### 导航

- 库内「列表 → 详情 → 编辑/关联」钻取须走单一 `sealed` 状态（ADR-0059 导航状态约束），不复用
  知识点行的 `showDialog` 散落写法。

## 迁移与兼容性

- **存量 `kp.scenes` 不动**：那 1 个 reflection KP 现有数据原样有效，进库后照常显示。
- **未配置 KP**：经库「关联知识点」写 seed 进库，seed 图形取自 `scene_template_config.default_figure_key`
  （空则回落注册表 `figure=''` 空占位，与现状一致），无需数据迁移。
- **空态语义不变**：`scenes` 为空仍弹开发者指引（位置迁到库详情/编辑器内）。
- **新增 `scene_template_config` 表**（`kind` 主键 + `default_figure_key`，可为空 → 回落注册表空占位，
  行为同现状）；幂等 DDL（`run_migrations`，无 Alembic）。存量无数据，首启动无回填。

## Consequences

- **前端新增/改动**：`scene_library_detail_view` 增编辑 + 关联能力 + kind 级图形画廊/默认图形；
  `knowledge_point_row` 删讲解入口；库详情空态文案更新。
- **后端**：新增 `scene_template_config` 表 + 默认图形读写端点（§7）；编辑/新增实例复用现有 PATCH；
  「关联知识点」picker 可纯前端过滤。
- **约束/兼容性**：ADR-0073 红线不动；快照不可变测试不动；`kind` 稳定契约不动；注册表仍只作结构种子源。
- **不在本 ADR 内**：新增 kind（仍开发者工作流，ADR-0073 决策 7）；注册表运行时编辑/版本化
  （ADR-0073 Out-of-Scope）；per-kind 图形 allow-list 裁剪（§7 已明确不做）。

## 验证判据

- 去掉 KP「讲解」后：库详情页能为每个关联 KP 打开编辑器并保存（断言 `kp.scenes` 更新、渲染路径不变）；
  「关联知识点」能把一个未关联 KP 写 seed 进库并出现在列表。
- 库 kind 详情设 `default_figure_key` 后：新关联 KP 的 seed 场景 `figure/points` 取自该默认图形；
  改库默认后，**已落库**的 `kp.scenes` / `Question.scene_spec` 不受影响（快照不可变回归仍绿）。
- 关联后的 KP 在库内编辑实例可覆盖为其他图形（house→butterfly），保存后仅该 KP 改变，不影响库默认与其他 KP。
- `flutter analyze lib` 零 issue；场景库相关用例与全量 311 例不回归。
- 现有场景库聚合测试（`test_scene_templates.py`）不受影响；ADR-0073 快照不可变回归仍绿。

## 已知遗留

1. **「关联知识点」picker 端点取舍**：纯前端过滤现有 KP 列表（零后端改动）vs 新增「未关联 KP」端点。
   倾向纯前端过滤——教师 KP 量级小，往返成本高且无收益。
2. **多 kind 导航状态**：未来多 kind 时，库内「列表→详情→编辑/关联」钻取须收敛到同一 `sealed`
   状态（ADR-0059），避免并列状态漏清。
3. **「关联知识点」写 seed 后是否立即打开编辑器**：UX 待定——写入 seed 后直接弹编辑器让教师选图形，
   还是先回库列表、由教师点实例卡再编辑。
4. **kind 级默认图形端点形态**：`PUT /materials/scene-library/{kind}/default-figure` 直接写 vs 并入
   现有配置端点；以及「重置为库默认」的 UX——库内编辑实例时是否提供「恢复库默认」一键。
5. **默认图形与注册表中性种子的回落**：关联写 seed 时 `figure/points` 取自 `scene_template_config`，
   若 `default_figure_key` 为空则回落注册表 `figure=''` 空占位（与现状一致），需在前端与 `saveScenes` 两侧对齐。

## Out of Scope

- 库做事实源 / live binding（ADR-0073 已拒，会破坏快照不可变）。
- 注册表运行时编辑 / 版本化（ADR-0073 Out-of-Scope）。
- 新增可渲染 kind（仍开发者工作流 + 前端渲染器发版）。
- per-kind 图形 allow-list 裁剪（§7 已明确仅设默认图形、不裁剪可用集）。
