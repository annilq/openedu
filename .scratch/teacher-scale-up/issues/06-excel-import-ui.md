# 06: Excel 导入 UI

**What to build:** 学生管理页内提供上传入口，选文件后调用导入端点并展示结果：成功多少、跳过多少、以及每一行失败的原因，便于教师修正表格重新导入。

**Blocked by:** 05: Excel 批量导入学生端点

**Status:** done

**Done note (2026-10-07):** 学生管理页标题行新增「批量导入」入口（`AppIconAction`/`LucideIcons.upload`），点击经 `file_picker` 选 xlsx → 调 `studentManagementProvider.importStudents` → `POST /students/import`（复用 `NetworkService.postForm` + `FormData`，与课件素材上传同构）。回执 `StudentImportResultModel`（`created`/`skipped`/`errors[{row,reason}]`）由非 Material 浮层 `StudentImportSheet` 分区展示（成功数 / 跳过数 / 逐行错误原因），与 `_ClassPicker` 同构（Stack + 遮罩，不依赖 Material Dialog）。导入成功后 notifier 自动 `load()`，列表即时刷新。新增两文件已登记 `file_size_guard_test` 基线（38 / 158 行，均 ≤400）。`file_picker` 依赖此前已在 pubspec。

- [x] 选 xlsx 文件 → 显示导入进度 / 结果
- [x] 结果分区展示 `created` / `skipped` / `errors`，`errors` 列出每行原因
- [x] 导入后列表即时反映新增学生
- [x] 上传组件在「不套 Material」的树里真构建通过
- [x] 新增前端 `file_picker` 依赖；新文件受 400 行规模棘轮约束并登记基线

**决策锚点：** ADR-0068「依赖与前端」；导入结果不只是一句「失败」，须明示每行原因与跳过原因。
