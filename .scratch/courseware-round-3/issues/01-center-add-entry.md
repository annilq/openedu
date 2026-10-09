# 01: 课件中心「新增课件」主入口 + 新建表单

**What to build:** 把"新增课件"做成课件模块自身的一等动作，不再只藏在知识点行的「课件」入口里。

- `CoursewareCenterScreen` 顶部（复用 `CoursewareRecentBar` 之下、列表之上）加「新增课件」`AppPrimaryButton`；空态文案改为「点上方『新增课件』，选一个知识点即可备课」。
- 新增 `courseware_create_sheet.dart`（`showCoursewareCreateSheet`）：
  - **选知识点**：列出本人已转正知识点，可按 学科·年级·学期 / 名称检索，必选。数据源复用 `knowledgeManageProvider` 的加载与检索逻辑；若现有 provider 不便复用，新增轻量 `GET /knowledge-points`（按 `teacher_id` + 可选 `subject/grade/semester/name`）端点——T01 落地时定。
  - **标题**：可选文本，留空回落知识点名。
  - **教学目标/备注**：可选自由文本，作为 AI 起草依据（透传给 05 的 `draft_sections`）。
  - 确认 → `createCourseware(knowledge_point_id, title?, objective?, draft: False)` → 建空壳 → push `CoursewareEditorPage`。
- 保留 `knowledge_point_row.dart` 的「课件」行内入口为次级快捷（两者通向同一新建流程）。
- 后端 `create_courseware`：`CoursewareCreate` 加 `draft: bool = True`；`draft=False` 时跳过 `draft_sections`，只按知识点快照建**零环节**课件（不调 AI、不抛 `LLM_UNAVAILABLE`）。`objective` 字段：`CoursewareCreate.objective: str | None`，落到课件行备用（AI 补充时读取）。

**Blocked by:** None.

**Status:** todo

**验收清单**
- [ ] 课件中心页有「新增课件」主按钮，点击弹出选知识点 + 标题 + 教学目标表单
- [ ] 表单必选知识点，确认后建出零环节课件并进入编辑器（不自动跑 AI）
- [ ] 知识点选择器可检索本人已转正知识点；未选知识点确认按钮禁用
- [ ] 知识点行的「课件」入口仍可用（次级快捷）
- [ ] `create_courseware(draft=False)` 后端不调 AI、不抛 LLM 错误、落库零环节
- [ ] `flutter analyze lib/features/courseware` 0 issue；相关 widget 测试全绿
