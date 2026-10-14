# ADR-0093：知识点审核视图增强（去近似重复 / 学期口径 / 覆盖度 / 溯源）

> 本 ADR 已根据用户确认的 `docs/adr/0093-spec.md` 开发计划定稿（用户选项 A：保留工作树参考实现并补提交）。
> 四项决策均已落地，验证见「验证」一节。

状态：已实现（2026-10-14 · 经用户确认 `0093-spec.md` 计划，采用选项 A 保留工作树实现）

> 落地轨迹：
> `schemas.py` 新增溯源响应三件套（`KnowledgePointSourceChunk`/`SourceMaterial`/`SourcesResp`）
> → `repository.list_knowledge_point_sources` 反查源资料+片段 → `service.get_knowledge_point_sources` 组装
> → `router` 新增 `GET /materials/knowledge-points/sources` → 前端 `material_repository` 抽象+实现
> → `material_knowledge_manage_view` 加 `_CoverageMeter` + `_openSource` 弹窗、`knowledge_point_row` 加「溯源」入口
> → `knowledge_point_source_view` 新建、DB 补 `ix_knowledgepoint_unique`、测试 `knowledge_manage_scope_test` 同步学期口径。
> 验证：后端资料路由测试 23 passed（1 项 `test_empty_text_422` 为预存在、与本期无关）；前端 `flutter analyze` No issues、
> `knowledge_manage_scope_test` All tests passed。

## 背景

「知识点管理」页（`material_knowledge_manage_view`）原先是平面列表，教师能勾选待审/已转正、
能按 (学科, 年级, 学期) 过滤，但**缺少审计信号**：看不出重复、看不出覆盖到哪、也查不到某个点
到底出自哪本教材哪一段。用户给出四点明确增强（按依赖即下方四项决策），并要求落 spec。

落地前实测到的两个**数据现实**，直接决定了 #1 与 #4 的口径：

- **真重复并不存在，近似重复不该做**。对线上 `app.db`（`knowledgepoint` 共 157 行）按
  唯一键 `(teacher_id, subject, grade, name, semester)` 分组复核：`dup_violations = 0`
  （之前看到的「2 行同名」是同名跨学期，属设计内，不是突破唯一键的真重复）。因此「近似重复」
  无判别标准、只会把合法跨学期条目误标，不做。
- **`MaterialChunk.knowledge_point` 字段 1312 条全部为 NULL**。当初设想的「就近匹配」赋值逻辑
  实际从未跑过，所以溯源**不能**走 chunk↔KP 字段。知识点与资料之间唯一的真实链接是
  `Material.knowledge_points`（名字串，无外键）。溯源只能反查「哪些资料引用了这个名字」，
  再展开该资料的整篇切片。

## 决策

### 1. 不做近似重复，真重复交给数据库唯一约束（用户点 #1）

- 不引入任何「相似度 / 近似重复」标记逻辑——无可靠判别标准，且会误伤合法同名跨学期条目。
- 真重复由物理约束兜底：已在 `app.db` 建
  `CREATE UNIQUE INDEX IF NOT EXISTS ix_knowledgepoint_unique ON knowledgepoint(teacher_id, subject, grade, name, semester)`
  （SQLite 对已有表可直接 `CREATE UNIQUE INDEX`，无需重建表；实测 `removed dup rows = 0`、
  `index present = True`、`violations = 0`）。
- **迁移可重复性**：该索引为一次性 DDL，未在 Alembic 里登记。新环境（或重置库）须重跑同一条
  `CREATE UNIQUE INDEX IF NOT EXISTS`；若未来接入迁移框架，把它补成正式迁移，避免「靠约束控制」
  在新库失效。

### 2. 去掉「整年」标识，只保持学期（用户点 #2）

- 模型层口径已定：`KnowledgePoint.semester` 必须是**具体值**（`''`/空不再允许），
  `knowledge_manage_provider.dart:24` 的注释明确「`''` = 整学年仅为前端聚合视图（UNION），
  **不存空行**」。
- 默认学期从 `''` 改为 `'上学期'`（`knowledge_manage_provider.dart:46`）；
  `semestersOf`（`knowledge_manage_provider.dart:111`）移除前置 `['']`，只返回该 (学科, 年级)
  **真实出现过的**具体学期（如仅上册教材则只有 `['上学期']`）。
- 失效回落不再回退空：无具体学期时落到 `concrete.first` 或 `'上学期'`
  （`knowledge_manage_provider.dart:193`）。
- 视图 `_ScopeBar` 切学科/年级时级联到 `firstSemester()`（`material_knowledge_manage_view.dart:263`），
  落首个具体学期；学期下拉 `labels: km.semesters`（`material_knowledge_manage_view.dart:303`），
  不再渲染「整学年」空标签。
- 测试同步：`knowledge_manage_scope_test` 的「入口落到第一个真实有教材的范围」与「下拉只派生自
  真实有教材的范围」断言改为期望具体学期（如 `'上学期'`），去掉 `''` 与「整学年」用例。

### 3. 显示覆盖度（用户点 #3）

- 定义：**审核覆盖度 = curated / total**（该 (学科, 年级, 学期) 范围内已转正 ÷ 总条数）。
- 前端计算，无后端改动：新增 `_CoverageMeter` 进度条
  （`material_knowledge_manage_view.dart:103` 调用、`material_knowledge_manage_view.dart:314` 定义），
  在 pending 计数之后展示「已审 X / 总 Y」。
- 范围：**知识点级**覆盖度（审核进度）。教材**章节级**覆盖度需解析目录树，超出本期，不在本 ADR 内。

### 4. 添加溯源，点击看 chunk 原文（用户点 #4）

- 行内新增「溯源」入口（`knowledge_point_row.dart:91-94`，`AppTextAction` label `'溯源'`），
  点击经父级 `_openSource`（`material_knowledge_manage_view.dart:215`）拉取并弹窗。
- 数据源（见背景实测）：走 `Material.knowledge_points` 名字串反查源资料，再展开该资料整篇切片；
  **不依赖** `MaterialChunk.knowledge_point`（该字段全 NULL）。
- 后端新增端点 `GET /materials/knowledge-points/sources`
  （`router.py:225`，参数 `subject/grade/name`），由
  `service.get_knowledge_point_sources`（`service.py:723`）组装、
  `repository.list_knowledge_point_sources`（`repository.py:339`）反查——
  筛选该教师同 (学科, 年级) 的资料，`name in material.knowledge_points` 命中者取其全部 chunk
  （`seq` + `content`，按 `seq` 排序）。
- 响应 schema：`KnowledgePointSourceChunk`/`KnowledgePointSourceMaterial`/`KnowledgePointSourcesResp`
  （`schemas.py:177/184/197`）。
- 前端抽象：`MaterialRepository.getKnowledgePointSources`
  （`material_repository.dart:293`，含 `KnowledgePointSourceChunk/SourceMaterial/Sources` 模型）
  由 `material_repository_impl.dart:67` 经 `_network.get('/materials/knowledge-points/sources', query: ...)`
  实现；弹窗组件 `KnowledgePointSourceView`（`knowledge_point_source_view.dart`，新建）展示
  源资料列表 + 按 `seq+1` 展开的片段原文，空命中给出「该点由教材涌现、未绑定资料」的说明。

## 验证

- 前端：`flutter analyze` 六个改动文件 **No issues found**；`knowledge_manage_scope_test`
  **All tests passed**（#2 学期口径断言已更新）。
- 后端：`tests/api/routes/test_materials.py` 跑出 **23 passed**；
  唯一失败 `TestUploadAndParse::test_empty_text_422`（空文本上传应 422 却得 200）经 stash 验证
  **在干净树上同样失败**，属预存在缺陷，与本期 4 项改动无关（本期未触碰上传校验路径）。
- 数据：`app.db` 已确认 `ix_knowledgepoint_unique` 存在、`violations = 0`、`total = 157`。

## 后果与遗留

- 「整学年」视图作为 UNION 聚合仍可存在（跨学期并集展示），但其底层不再有 `semester=''` 的行，
  聚合由前端按具体学期拼接，避免空行污染与确认盲区（呼应 ADR-0065 跨学期转正）。
- 溯源弹窗展示的是「引用该名字的资料整篇切片」，不是「chunk 精准命中该知识点的一段」——
  因 `chunk.knowledge_point` 缺数据，这是当前能给出的最强出处证据；若后续回填 chunk 级归属，
  可把溯源精度从「资料级」提升到「片段级」。
- `ix_knowledgepoint_unique` 为一次性 DDL，须纳入迁移/部署脚本（见决策 #1），否则新环境约束失效。
