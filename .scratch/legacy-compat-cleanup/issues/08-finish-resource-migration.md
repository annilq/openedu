# 08: 完成 Resource<T> 加载态迁移（LCC-08）

**What to build:** 把仍手写「取一次就显示」四态 sealed 类（`XxxInitial/Loading/Loaded/Error`）的 notifier 统一改用共享的 `Resource<T>`（LCC-08，用户 2026-10-13 拍板「全站铺开」）。达成单源真身（贴合本 epic「每概念只一个真身」）。

**Blocked by:** None（可立即抓；frontier）

**Status:** done

## 范围（实测复核，非原 spec 的「~14」）

原 spec 估「~14/19 处」，但交叉核验后真正该迁的是 **8 个**「取一次就显示」notifier；另有 **3 个状态机**按 `resource.dart` 文档（"带动作的状态机…不是资源，别硬套"）**明确不迁**：

- **单载荷（直接 `Resource<T>`，干净）：4 个**
  - `teacher_todo` → `Resource<TeacherTodoSummary>`（done，commit 295c3a0）
  - `due_review` → `Resource<List<ReviewItemModel>>`（done，commit 0531455；本页 `answer()` 就地把已答题移出列表，故自定义 notifier `with ResourceLoader`，保留 `_repo`）
  - `students`（`ChildrenState`）→ `Resource<List<UserModel>>`（done，commit 5eac92a；类名陈旧，顺手正名；自定义 notifier `with ResourceLoader`，保留 createChild/updateChild 回传值）
  - `class_management` → `Resource<List<ClassModel>>`（done，本票次）
- **复合载荷（需包装类 / record 包一层）：4 个**
  - `models`：`(ModelListResp, List<ModelProviderPreset>)`（done，commit 5cd5c85；自定义 notifier `with ResourceLoader`，保留 create/update/delete/setDefault/testConnection）
  - `student_management`：5 字段（classes/students/wrongCounts/classId/keyword）（done，commit b390515；自定义 notifier `with ResourceLoader`，保留 batchReassign/importStudents）
  - `analytics_summary`：`(WrongDistributionResp, AccuracyResp, MasteryResp)`（done，commit ec9130e；纯只读、自定义 notifier `with ResourceLoader`，包 AnalyticsSummaryData）
  - `analytics`：8 字段（scope/dimension/classId/classes/students/wrong/accuracy/mastery）（done，commit da80302；自定义 notifier `with ResourceLoader`，保留 _classesCache/_studentsCache 与 setScope/setDimension/setClass 下钻动作）
- **不迁（状态机，留手写）：3 个**
  - `question_bank`（`BankState`）：游标分页 + 动作态（BankActionLoading/Success/Error、BankDeleted、BankArchived）
  - `task_review`（`ReviewState`）：草稿审核，busyTqId 在途动作 + 题卡原地增删改
  - `knowledge_manage`（`KnowledgeManageState`）：非 sealed，loading/error 是字段，含勾选/范围选择/notice 通道

## 迁移纪律（每站）

- notifier：删 4 态 sealed 类；改为 `ResourceNotifier<T>`（或直接 `StateNotifierProvider<ResourceNotifier<T>, Resource<T>>`，闭包吃 `ref` 取数，契合 `resource.dart` 文档示例）。
- **带写动作（增/改/删后重载）的 notifier**：自定义 `StateNotifier<Resource<T>> with ResourceLoader<T>`，保留 `_repo` 字段；`load()` 调 `runLoad(_repo.getX)`，`create/update/delete` 调 `_repo` 后 `await load()`。本票次把原本私有的 `_ResourceLoader` 改名公开为 `ResourceLoader` 并暴露 `runLoad`（私有 `_run` 跨库不可见），让写动作 notifier 也能复用同一套四态落法，不重新手写 `Loading → get → Loaded / catch → Error`。
- widget：状态参数改 `Resource<T>`；渲染改 `state.errorOrNull` / `state.dataOrNull` / `state.isLoading`（Idle+Loading → 占位，Error → 重试，Loaded → 内容），**行为保真**。
- `ref.loadWhenIdle(...)` 的触发谓词 `s is XxxInitial` → `s is ResourceIdle`。
- 每站 `flutter analyze` + 针对性 widget 测试守门；分离提交 code / tracker / memory。

## 验收清单

- [x] `teacher_todo` 已迁（analyze 绿 + 全量 552 测试通过）。
- [x] `class_management` 已迁（自定义 `ClassManagementNotifier with ResourceLoader<List<ClassModel>>`；analyze 全仓绿 + 全量 552 测试通过）。
- [x] `due_review` 已迁（自定义 `DueReviewNotifier with ResourceLoader<List<ReviewItemModel>>`；`answer()` 在 ResourceLoaded 态直接替换 data，保留「答完不误清进度」语义；analyze 全仓绿 + 全量 552 测试通过）。
- [x] `students` 已迁（自定义 `ChildrenNotifier with ResourceLoader<List<UserModel>>`，保留 createChild/updateChild 回传值；analyze 全仓绿 + 全量 552 测试通过）。
- [x] `analytics_summary` 已迁（自定义 `AnalyticsSummaryNotifier with ResourceLoader<AnalyticsSummaryData>`；纯只读、三聚合包一层；analyze 全仓绿 + 全量 556 测试通过）。
- [x] `models` 已迁（自定义 `ModelsNotifier with ResourceLoader<ModelsData>`，保留 create/update/delete/setDefault/testConnection；analyze 全仓绿 + 全量 556 测试通过）。
- [x] `student_management` 已迁（自定义 `StudentManagementNotifier with ResourceLoader<StudentManagementData>`，保留 batchReassign/importStudents；analyze 全仓绿 + 全量 556 测试通过）。
- [x] `analytics` 已迁（自定义 `AnalyticsNotifier with ResourceLoader<AnalyticsData>`；保留下钻动作 + 缓存；analyze 全仓绿 + 全量 556 测试通过）。
- [x] 8 个 notifier 全部迁完（4 单载荷 + 4 复合载荷）；旧 sealed 加载态类引用全仓归零（实测 grep 8 个状态名零命中）。
- [x] `flutter analyze` 全仓绿；`flutter test` 全量通过（556/556）。
- [x] 3 个状态机（question_bank / task_review / knowledge_manage）按 `resource.dart` 文档（"带动作的状态机…不是资源，别硬套"）明确不迁，保留手写四态。
