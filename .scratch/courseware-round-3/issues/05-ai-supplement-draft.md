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

**Status:** todo

**验收清单**
- [ ] 空课件进入不自动跑 AI；「AI 补充讲解」显式触发
- [ ] 草稿环节引用真实素材 asset_id 与场景模板（非编造、非空）
- [ ] 空课件时 AI 补充的 diff 全为 added，接受后即落库
- [ ] 未配模型时返回 LLM_UNAVAILABLE 且不落空课件
- [ ] 教学目标文本进入起草 prompt 并影响产出
- [ ] `flutter analyze` 0 issue；后端起草测试覆盖"引用真实素材/场景"
