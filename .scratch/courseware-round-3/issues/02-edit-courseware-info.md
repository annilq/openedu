# 02: 课件信息编辑（标题 / 状态）

**What to build:** 给课件级信息（标题、状态）一个编辑入口。当前编辑器标题直接用 `widget.kpName`，从不展示/编辑课件信息；后端 `PATCH /{id}` 已支持 `title`/`status` 但前端没接。

- `CoursewareEditorPage` 顶部（`AppPushedPage` 内容首区）加「课件信息」卡片：
  - 展示 `displayTitle`、`学科 · 年级 · 学期`、`状态`（`草稿` / `可上讲台`）。
  - 右侧「编辑」`AppTextAction` → 小弹窗（`AppDialog` 或轻量 `Dialog`）：编辑 `title` 文本 + `status` 段选择器（草稿 / 可上讲台）。
  - 保存 → `coursewareRepository.updateCourseware(id, title?, status?)`（`PATCH /{id}`，只传改的字段）→ 刷新 `_courseware`。
- `subject/grade/semester/knowledgePointId` 是知识点快照、展示用，**不在课件信息里改**（避免与知识点源脱节）。

**Blocked by:** None.

**Status:** todo

**验收清单**
- [ ] 编辑器顶部有「课件信息」卡片，显示标题/范围/状态
- [ ] 点「编辑」可改标题与状态，保存后经 `PATCH /{id}` 落库并刷新
- [ ] 范围（学科·年级·学期）只读展示，不可在课件信息里改
- [ ] 状态切换不阻塞演示（draft 也能开讲，与既有语义一致）
- [ ] `flutter analyze` 0 issue；补 1–2 例编辑保存测试
