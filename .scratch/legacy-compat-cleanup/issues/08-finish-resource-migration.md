# 08: 完成 Resource<T> 加载态迁移（LCC-08）

**What to build:** 把仍手写「取一次就显示」四态 sealed 类（`XxxInitial/Loading/Loaded/Error`）的 notifier 统一改用共享的 `Resource<T>`（LCC-08，用户 2026-10-13 拍板「全站铺开」）。达成单源真身（贴合本 epic「每概念只一个真身」）。

**Blocked by:** None（可立即抓；frontier）

**Status:** in_progress

## 范围（实测复核，非原 spec 的「~14」）

原 spec 估「~14/19 处」，但交叉核验后真正该迁的是 **8 个**「取一次就显示」notifier；另有 **3 个状态机**按 `resource.dart` 文档（"带动作的状态机…不是资源，别硬套"）**明确不迁**：

- **单载荷（直接 `Resource<T>`，干净）：4 个**
  - `teacher_todo` → `Resource<TeacherTodoSummary>`（done）
  - `due_review` → `Resource<List<ReviewItemModel>>`
  - `students`（`ChildrenState`）→ `Resource<List<UserModel>>`（类名陈旧，迁移顺手正名）
  - `class_management` → `Resource<List<ClassModel>>`
- **复合载荷（需包装类 / record 包一层）：4 个**
  - `models`：`(ModelListResp, List<ModelProviderPreset>)`
  - `student_management`：5 字段（classes/students/wrongCounts/classId/keyword）
  - `analytics_summary`：`(WrongDistributionResp, AccuracyResp, MasteryResp)`
  - `analytics`：8 字段（scope/dimension/classId/classes/students/wrong/accuracy/mastery）
- **不迁（状态机，留手写）：3 个**
  - `question_bank`（`BankState`）：游标分页 + 动作态（BankActionLoading/Success/Error、BankDeleted、BankArchived）
  - `task_review`（`ReviewState`）：草稿审核，busyTqId 在途动作 + 题卡原地增删改
  - `knowledge_manage`（`KnowledgeManageState`）：非 sealed，loading/error 是字段，含勾选/范围选择/notice 通道

## 迁移纪律（每站）

- notifier：删 4 态 sealed 类；改为 `ResourceNotifier<T>`（或直接 `StateNotifierProvider<ResourceNotifier<T>, Resource<T>>`，闭包吃 `ref` 取数，契合 `resource.dart` 文档示例）。
- widget：状态参数改 `Resource<T>`；渲染改 `state.errorOrNull` / `state.dataOrNull` / `state.isLoading`（Idle+Loading → 占位，Error → 重试，Loaded → 内容），**行为保真**。
- `ref.loadWhenIdle(...)` 的触发谓词 `s is XxxInitial` → `s is ResourceIdle`。
- 每站 `flutter analyze` + 针对性 widget 测试守门；分离提交 code / tracker / memory。

## 验收清单

- [x] `teacher_todo` 已迁（analyze 绿 + 全量 552 测试通过）。
- [ ] 其余 7 个 notifier 迁完；旧 sealed 加载态类引用全仓归零（grep `XxxInitial/XxxLoaded` 等）。
- [ ] `flutter analyze` 全仓绿；`flutter test` 全量通过。
