# 04: 手动添加环节

**What to build:** 让教师能在课件里手动新增环节（当前只能删、只能靠 AI 起草）。

- `editor_section_list.dart` 头部（与「选择」并列）加「添加环节」`AppTextAction`；点击 → 打开现有 `showCoursewareSectionEditDialog`，传入一个**空白 `CoursewareSectionModel`**（无 kind、title/scripts/materials/scene 皆空）。
- 教师配提问/素材/场景后保存 → 回调返回新 `CoursewareSectionModel` → 追加到 `sections` 末尾 → `_persistReorder(next)`（即 `PUT /{id}/sections` 整体覆盖写）。
- 因 T03 已去 `kind`，添加环节**不需要 kind 选择器**——与用户"每个环节的内容都是配置选择的，无需类型化"一致。

**Blocked by:** 03（去 kind·expand 后方可无 kind 选择器添加）。

**Status:** todo

**验收清单**
- [ ] 环节列表头部有「添加环节」按钮
- [ ] 点击弹出与编辑同构的空白处表单（标题/话术/素材/场景）
- [ ] 保存后新环节出现在列表末尾并落库（PUT 整体覆盖写）
- [ ] 不依赖 kind 选择；与 T03 去 kind 后模型一致
- [ ] `flutter analyze` 0 issue；补"添加环节→落库"测试
