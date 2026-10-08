# ADR-0074：场景库成为「讲解配置」唯一管理面（场景为中心，场景服务端硬编码）

状态：草案（v4——场景为中心 + 场景服务端硬编码；前端「新增场景」仅提醒开发者，不自由创建）

修订轨迹：
- v1：KP 为中心（库做配置入口）。
- v2：加 §7 kind 级默认图形（消除场景/图形割裂）。
- v3（已废弃）：试图把场景升级为教师可自由建的 SceneInstance 一等实体——被本方向推翻。
- v4（本版）：**场景（kind）是服务端硬编码资产**，前端不自由创建；「新增场景」按钮只提醒开发者
  在后端配置。教师侧不产生新实体，只在场景库里配置已有 kind 的「演示图形 + 关联知识点 + 标题」。

## 背景

知识点由资料库解析（重解析身份稳定、`upsert_pending_knowledge_point` 按
`(teacher_id, subject, grade, name, semester)` 查重保留 id；但 KP 不再被引用时 `_prune_knowledge_points`
会级联清理 → 关联可能悬空）。而场景库 `SCENE_LIBRARY` 注册表 + `scene_figures.py` **硬编码、一般不变**
（kind 与图形均开发者维护，ADR-0073「新增可渲染 kind 仍开发者工作流 + 前端渲染器发版」）。

用户据此重新定义关系：**场景稳定、知识点易变** → 关联应以「配置已有场景 → 关联知识点」为正向，
而非「从易变 KP 反向建场景」。并明确：场景只在服务端新增，前端点击「新增场景」时提醒开发者配置。

原痛点（仍成立）：知识点管理行「讲解」按钮（`knowledge_point_row.dart`）与场景库指向同一概念却分散；
讲解弹窗的图形画廊（`ReflectionFigureGallery`）只活在 KP 编辑器，库管不了图形 → 割裂。

## 决策

### 1. 场景（kind）是服务端硬编码资产，前端不自由创建

- kind 与图形由开发者在 `scene_templates.py`（`SCENE_LIBRARY`）+ `scene_figures.py` 维护；
  教师端只**消费**已登记项（选图形 + 设标题），不自由创建场景类型、不自由绘制图形。
- 前端场景库顶部的「新增场景」按钮**不调用任何写端点**，点击即弹出提醒（toast/引导文案）：
  「新场景类型请在后端 `SCENE_LIBRARY` 注册表配置并随前端渲染器发版，请联系开发者」。
  即：**前端只做开发者提醒，不做创建**。
- 新增可渲染 kind 属开发者工作流（ADR-0073 决策 7），不在本 ADR 教师 ticket 内。

### 2. 场景库详情页成为讲解配置的唯一管理面

对每个服务端已存在的 kind，教师在其详情页配置三件事：

- **① 演示图形（默认图形）**：在该 kind 暴露的图形集中选一个标为 `default_figure_key`
  （复用 v2 §7 机制）。图形顶点仍来自 `scene_figures.py`，库只存 key，不复制几何。
- **② 关联知识点（1:N）**：把一个或多个 KP 关联到该场景——写一份 seed 场景（kind + §7 默认图形 +
  注册表中性轴参数）进该 KP 的 `kp.scenes`（经现有 `PATCH …/scenes`）。关联由 `kp.scenes` 里的
  `kind` 隐式表达（ADR-0073 的 `GET /materials/scene-library` 正是扫 `kp.scenes` 反查关联），
  **无需新增关联表**。
- **③ 标题按知识点编辑**：每个关联 KP 的场景条目标题可在库内经编辑器覆盖（写入该 KP 的 `kp.scenes`
  场景条目 `title`），即「场景 title 根据对应知识点编辑」。

### 3. 事实源不变（不碰 ADR-0073 红线）

- 渲染 / 出题 / 课件只读 `KnowledgePoint.scenes`（per-KP 快照拷贝），**永不回查** 库配置 / 注册表 /
  `scene_figures`。
- 关联 KP 时把场景当前 `{kind, figure_key, params, title}` **seed 拷贝**进 `kp.scenes`。
- 改库默认图形 / 标题**只影响之后新关联的 KP**；已关联 KP 的 `kp.scenes` 不自动回写（保快照不可变）。
  可选「同步到已关联」显式按钮（老师主动触发，非自动、非 live binding）——列为遗留，不在首版。

### 4. 关联稳定性与 prune 处理

- KP id 重解析稳定（upsert by name），关联在重解析下存活。
- KP 被 prune（无资料引用）时：库侧该关联**显示为悬空项**（「关联的知识点已不存在」），教师可手动解除；
  **不级联删场景**（场景是教师的稳定资产）。库聚合在反查 `kp.scenes` 时若 KP 已不存在则标悬空。

### 5. KP 行移除「讲解」按钮

`knowledge_point_row.dart` 删「讲解」`AppTextAction` + 确认框 + `kp.semester` 传参整条链路；保留「课件」。
必须在库具备「演示图形配置 + 关联知识点」能力后撤（否则新 KP 进不了库）。

### 6. 标题语义

- 场景有基础展示名（kind 名，如「轴对称」）；每个关联 KP 的场景条目标题可覆盖（编辑自对应 KP 名）。
- 渲染 / 出题用的是 `kp.scenes` 里的标题（覆盖值或回落 kind 名），不在运行时回查库配置。

## 与 ADR-0073 的关系

- **扩展**其 UX 边界：场景库从「只读浏览/聚合」变为「讲解配置唯一管理面」，并管理 kind 级默认图形。
- **不改**其红线：`scenes` 唯一事实源；实例存完整副本（快照不可变）；渲染/出题/课件永不回查。
- **显式排除**：① 库做事实源 / live binding（ADR-0073 Out-of-Scope 已拒）；② 教师前端自由创建场景
  / 图形（v3 已废弃方向）；③ 注册表运行时编辑 / 版本化。

## 数据模型新增（仅一处）

`scene_template_config(kind PK → default_figure_key, nullable)`：kind 级演示图形，可写持久化。
- 注册表 `SCENE_LIBRARY` 仍只作结构种子源（inputs 骨架），不承载默认图形。
- `default_figure_key` 为空 → 关联写 seed 时回落注册表 `figure=''` 空占位（与现状一致）。
- 其余关联 / 场景条目均存于 `kp.scenes`，无新增关联表。

## 实施要点

### 前端

- `scene_library_view`：顶部「新增场景」按钮 → 点击弹开发者提醒（toast/引导文案），无写调用。
- `scene_library_detail_view`：每个 kind 详情展示 ① 图形画廊 + 「设为默认」（读/写 `default_figure_key`）；
  ② 关联知识点列表（1:N，扫 `kp.scenes` 反查，含 prune 悬空标记）；③ 点关联项打开 `KnowledgePointSceneEditor`
  （复用，传 `id/name/subject/grade/semester/scenes`）改图形/标题经现有 `PATCH …/scenes`；④ 新增「关联知识点」
  入口（前端过滤未关联该 kind 的 KP → 写 seed）。
- `knowledge_point_row.dart`：删「讲解」链路，保留「课件」；库详情空态文案指向「在场景库关联」。

### 后端

- 新增 `scene_template_config` 表（幂等 DDL，`run_migrations`）；`GET /materials/scene-library` 的
  `SceneLibraryItem` 附带 `default_figure_key`；新增 `PUT /materials/scene-library/{kind}/default-figure`
  写默认图形（kind 稳定契约）。
- 关联 / 编辑复用现有 `PATCH /materials/knowledge-points/{kpId}/scenes`，零新增实例端点。
- `GET /materials/scene-library` 反查 `kp.scenes` 时补充 prune 悬空标记（KP 已不存在）。

### 导航

- 库内「列表 → 详情 → 编辑/关联」钻取走单一 `sealed` 状态（ADR-0059），不复用 KP 行 `showDialog` 散落写法。

## 迁移与兼容性

- 存量 `kp.scenes` 不动；那 1 个 reflection KP 现有数据原样有效。
- 新增 `scene_template_config` 表首启动无回填；`default_figure_key` 空则回落现状。
- 快照不可变测试 / ADR-0073 回归不动；`kind` 稳定契约不动。

## Consequences

- 前端：场景库详情可写化（图形画廊 + 默认 + 关联 + 标题）；KP 行删讲解；新增「提醒开发者」按钮。
- 后端：新增 `scene_template_config` 表 + 默认图形端点 + 库聚合补 prune 标记。
- 约束：ADR-0073 红线不动；场景服务端硬编码、前端不自由创建。

## 验证判据

- 前端点「新增场景」→ 弹开发者提醒、无写调用、不产生 kind。
- 库设 `default_figure_key` 后新关联 KP 的 seed `figure/points` 取自该默认；改默认后已落库 `kp.scenes` /
  `Question.scene_spec` 不受影响（快照不可变回归绿）。
- 「关联知识点」能把未关联 KP 写 seed 进库并出现在列表；prune 的 KP 在库侧标悬空、可解除。
- 去掉 KP「讲解」后库能完整替代（配置 + 关联 + 标题编辑）。
- `flutter analyze` 0 issue；场景库相关用例 + 全量不回归；ADR-0073 快照不可变回归绿。

## 已知遗留

1. **「同步到已关联」显式按钮**：改库默认/标题是否提供一键推到已关联 KP（非自动、非 live binding）——首版不做。
2. **per-kind 图形 allow-list**：是否限制某 kind 仅暴露部分图形（v2 已定「不裁剪可用集」），维持不裁剪。
3. **「关联知识点」写 seed 后是否立即开编辑器**：写入后直接弹编辑器 vs 先回列表——UX 待定。
4. **库聚合 prune 标记形态**：反查 `kp.scenes` 时 KP 已不存在的判定与展示文案。

## Out of Scope

- 库做事实源 / live binding（ADR-0073 已拒）。
- 教师前端自由创建场景 / 图形（本方向明确服务端硬编码）。
- 注册表运行时编辑 / 版本化（ADR-0073 Out-of-Scope）。
- 新增可渲染 kind（开发者工作流 + 前端渲染器发版）。
- per-kind 图形 allow-list 裁剪。
