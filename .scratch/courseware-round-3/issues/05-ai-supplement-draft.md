# 05: AI 补充讲解——知识点 + 用户信息的三项数据回填

**What to build:** 把 AI 从"进入即自动起草"降为"教师显式触发的辅助"。新建已是空壳（T01），本票补「AI 补充讲解」按钮，并让 AI 真正从服务端拿"提问/素材/场景"三项数据回填。

**前端**
- `CoursewareEditorPage`：空课件时「新增课件信息」改为「新增课件」（建空壳，语义归 T01）；有空课件/任意课件时提供「AI 补充讲解」`AppTextAction`（与既有「AI 重新起草」合并为同一动作，标签按是否有环节自适应）。
- 「AI 补充讲解」→ 复用现有 `redraft_diff`（空课件时 diff 全为 `added`）→ `showCoursewareRedraftDialog` 逐段接受 → `updateSections` 写回同一课件。
- 新建表单（T01）的「教学目标」在 `draft_sections` 时透传为 prompt 依据。

**后端**
- `draft_sections` / `redraft_diff` 起草前先查该知识点：
  - 素材库 `CoursewareAsset`（`knowledge_point_id` 过滤），取 `(id, name)` 候选清单；
  - 场景库场景模板（`get_knowledge_point_scenes` 同款查询）。
- 把候选 id 清单喂给 LLM（扩 `_DRAFT_SYSTEM` 与 `_DraftSection` 契约，允许环节引用真实 `materials[].asset_id` 与 `scene`），让产出**引用真实 id** 而非留空/编造。`_recall_snippets` 继续作为话术依据保留。
- 未配模型 → `LLM_UNAVAILABLE`，不落空课件（守 ADR-0066）。

**Blocked by:** 01（新建空壳）、03（去 kind·expand 后 diff 匹配键）。

**Status:** done

**验收清单**
- [x] 空课件进入不自动跑 AI；「AI 补充讲解」显式触发（编辑器空态「新增课件」建空壳，AI 行动标签自适应为「AI 补充讲解」/「AI 重新起草」）
- [x] 草稿环节引用真实素材 asset_id 与场景模板（非编造、非空）——`draft_sections` 起草前查 `CoursewareAsset(knowledge_point_id)` + `kp.scenes` 真实候选，prompt 声明只许引用真实值，服务端 `_sections_from_draft` 剥掉编造 id
- [x] 空课件时 AI 补充的 diff 全为 added，接受后即落库（`redraft_diff` 复用，空课件 current=[] → 全 added；前端「AI 补充讲解」复用 `showCoursewareRedraftDialog` + `updateSections`）
- [x] 未配模型时返回 LLM_UNAVAILABLE 且不落空课件（纪律不变，`build_ai_provider` 未配置即抛）
- [x] 教学目标文本进入起草 prompt 并影响产出（`objective` 透传 `draft_sections` → prompt；create/redraft 均带 `row.objective`）
- [x] `flutter analyze` 0 issue；后端起草测试覆盖"引用真实素材/场景"（新增 2 测试：真实引用保留 + 编造 id 剥掉 + objective 透传）

**实现备注**
- 后端 `service.py`：`draft_sections` 新增 `knowledge_point_id` / `objective` 形参，起草前 `_candidate_assets`（`asset_service.search_assets` 按 kp 过滤）+ `_candidate_scenes`（读 `kp.scenes`，ADR-0073 单一事实源）注入 prompt；`_sections_from_draft` 收 `allowed_asset_ids` / `allowed_scene_kinds`，不在候选集的素材 / 场景引用一律剥掉（不信任模型输出）。
- 顺手修了一个潜在 bug：`_DraftSection` 原本缺 `kind` 字段，却在本应是只读兼容的 `raw.kind` 读取处引用——旧测试因 monkeypatch `draft_sections` 从未走到真实 `_sections_from_draft` 而漏网；补 `kind: str | None = None`，使旧草稿带 kind 也能解析透传。
- 前端 `courseware_editor_page.dart`：空态「新增课件信息」→「新增课件」（建空壳 `draft=false`，不触发 AI）；AI 行动标签按 `cw.isEmpty` 自适应；「教学目标」经 T01 新建表单 `objective` 字段落到课件行，T05 后端起草时透传 prompt。
- 测试：`test_courseware_crud.py` 新增 2 例（含实时跑真实 `draft_sections` 验 prompt 注入 + 收敛）；`courseware_editor_page_test.dart` 新增 2 例 + 更新 T09 空态用例（建空壳而非 AI 起草）。
