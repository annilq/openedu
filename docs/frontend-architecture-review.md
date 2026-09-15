# 前端架构评审（2026-09-15）

> **状态：1–7 步全部落地。** `flutter analyze` = `No issues found!`，
> `flutter test` = 66 passed，R1–R5 五条分层守卫全绿，R4/R5 棘轮名单均已清零。
> 落地记录见文末「修复记录」。下面的「现状」章节是**修复前**的快照，保留作为问题清单。
>
> 环境提示：本机 `flutter test` 需要 `env no_proxy="127.0.0.1,localhost,::1" NO_PROXY=...`
> 才能跑（详见「修复记录」第 0 节）。



对照 `flutter-apply-architecture-best-practices` 的 UI / Logic / Data 三层规范，
对 `frontend/lib` 全部 96 个 dart 文件做了一次静态扫描（依赖方向 + 职责归属 + 行数分布）。

**结论：骨架是对的，Repository 层是空的。** 目录划分、`shared/` 单向依赖、ADR-0037 的
R1/R2/R3 静态守卫都成立；真正的问题在于「三层」里中间那层和下面那层在 9 个 feature 中的
7 个里根本没落地，ViewModel 直接吃 Service。

---

## 现状速览

| 项 | 数值 |
|------|------|
| feature 数 | 9（assistant / authentication / children / home / model_management / practice / profile / review / tutor） |
| 有 `domain/repositories` 接口的 feature | **2 / 9**（authentication、children） |
| 有 `data/datasource` 的 feature | 3 / 9（+ home 的 datasource 有一半是死代码） |
| presentation 层直接 import `network_service.dart` | **6 个 notifier + `shared/presentation/resource.dart`** |
| `StateNotifierProvider` / `extends StateNotifier` | 22 / 16 |
| `extends StatefulWidget`（无 Riverpod） | 0 —— 全部走 `ConsumerWidget` / `ConsumerStatefulWidget` |
| 总行数 | 18,384 |

---

## P0-1 Repository 层名存实亡

`NetworkService` 是 Data 层的 Service 抽象（设计正确），但它是**直接被 ViewModel 消费**的：

```
features/practice/presentation/providers/practice_notifier.dart     → shared/data/remote/network_service.dart
features/review/presentation/providers/review_notifier.dart         → 同上
features/home/presentation/providers/home_notifier.dart             → 同上
features/home/presentation/providers/parent_tasks_notifier.dart     → 同上
features/home/presentation/providers/parent_task_review_notifier.dart → 同上
features/model_management/presentation/providers/models_notifier.dart → 同上
shared/presentation/resource.dart                                    → 同上
```

后果：

1. **没有 single source of truth。** 缓存、离线兜底、重试、请求去重无处可放。
   现在娃娃端切 Tab 要手工 `_refreshChildTab(index)` 逐个 `ref.read(...).load()`，
   做完题要手写 4 行刷新——这些都是 repository 该提供的失效语义。
2. **端点字符串散落在 UI 层。** `'/review/due'`、`'/tasks/wrong-questions'`、
   `'/tasks/children/$childId/wrong-questions'` 写在 notifier 里，
   后端改一个 path 要翻 presentation 目录。
3. **`ResourceNotifier` 把取数固化进了 presentation 基类。**
   `shared/presentation/resource.dart:3` import 了 data 层，`load()` 内部直接 `_network.get(path)`。
   这个基类现在很好用（把 19 份同构四态收成了 1 份，是明确的正资产），
   但它让「插入 repository」变成改所有子类构造函数，而不是改一处注入。

## P0-2 分层方向倒置两处

- `features/children/domain/providers/children_provider.dart:7`
  → `import '../../presentation/providers/children_notifier.dart'`
- `features/authentication/domain/providers/auth_provider.dart:7`
  → `import '../../presentation/providers/auth_notifier.dart'`

**domain 依赖 presentation**，方向反了。同时这两个文件把「DI 装配」放进了 domain 层，
而其他 7 个 feature 的 DI 装配放在 `presentation/providers/`——同一职责两个落点。

现有 `feature_boundaries_test.dart` 的 R1/R2/R3 只管 `shared ↔ features` 和 feature 横向，
**不管层内方向**，所以这两处一直没被拦住。

## P1-1 三种架构风格并存，新人没有唯一正确姿势

| 风格 | feature | 链路 |
|------|---------|------|
| A 完整三层 | authentication、children | notifier → repository 接口 → repository impl → datasource → NetworkService |
| B 缺 repository | home（题库部分） | `question_bank_notifier` → `QuestionBankRemoteDataSource`（跳过接口） |
| C 只有 service | practice / review / tutor / model_management / home（其余） | notifier → NetworkService |

`assistant` 是第四种：`assistant_notifier` → `AssistantApiClient`（data 层服务），
但 SSE 状态机逻辑抽到了 `domain/ai_text_fold.dart` + `domain/question_gen_fold.dart`
纯函数——**这是全工程做得最好的地方**，fold 是纯函数、有 40+ 个单测守卫，改起来最放心。

## P1-2 孤儿文件

`features/home/data/datasource/tasks_remote_data_source.dart` **全工程零 import**。
同样的取数逻辑在 `parent_tasks_notifier.dart` 里用 `ResourceNotifier` 重写了一遍。
两份实现并存意味着改一边会静默漏掉另一边。

## P1-3 `lib/services/` 是第二个顶层数据目录

`lib/services/auth_session/` 与 `lib/features/` 平行，内含自己的
`data/repositories` + `domain/repositories` + `domain/providers`。
它的 `currentUserProvider`（`UserModel?`）与 `features/authentication` 的
`authNotifierProvider` 职责重叠——登录态有两个可能的真相源。

## P1-4 跨 feature 耦合越过了 R2 豁免的本意

ADR-0037 豁免的是 `features/home/presentation/` 作为**展示层组合根**。
但当前 home 的依赖深度已经超出「组合」：

- `home/presentation/providers/home_notifier.dart:8` → `assistant/data/assistant_api_client.dart`
- `home/presentation/providers/parent_task_review_notifier.dart:7` → `assistant/data/...`
- `home/presentation/providers/parent_task_review_notifier.dart:9` → `assistant/presentation/provider/assistant_notifier.dart`

home 的 **notifier** 吃进了 assistant 的 **data 层和 notifier**。
assistant 内部任何重构都会穿透到 home。

`selected_child_provider.dart` 用裸 `Ref` 扇出刷新 4 个外部 provider
（progress / mastery / parentWrongQuestions / tutorLogs）——
一个「选中娃娃」的动作硬编码知道另外三个 feature 的存在。

## P2-1 View 层偏重

- **`parent_task_review_screen.dart` 1204 行**，内嵌 `_QuestionCard` 及其 State，
  含 10 个 async 业务方法：`_onPromoteOne/_onPromoteAll/_onDelete/_onRegenerateOne/
  _onRegenerateAll/_onEdit/_onConfirm/_onAssign/_onDiscard/_submitEdits`。
  `_submitEdits()` 还自己做字段裁剪与判空——这是 ViewModel 的活。
- **`home_screen.dart` 12 处 `setState`**，导航靠 `_parentNavIndex / _childNavIndex /
  _showProfile / _reviewingTask / _editingChild` 五个局部字段手工切视图。
  全工程只有一个 `Navigator.push`（进练习页），其余都是 `setState` 换 widget。
- `_refreshChildTab(int index)` 用 switch 把「Tab 序号 → 刷哪个 provider」硬编码，
  与 UI 排列顺序强耦合，插一个 Tab 就要改两处。

## P2-2 领域模型是一个 God file

`shared/domain/models/models.dart` **833 行、21 个类**，横跨 9 个 feature 的全部领域概念
（User / Task / Question / WrongQuestion / ReviewItem / Mastery / TutorLog / ModelInfo…）。
且**没有 API DTO 与 Domain Model 之分**——27 个 `fromJson` 直接写在领域模型上，
后端字段一改，所有 feature 一起动。也没有 `freezed` / `built_value`，
不可变性与相等性靠手写（`toJson` 只有 5 处，多数模型不能回写）。

## P2-3 测试缺口

11 个测试文件，质量整体不错（assistant fold 的纯函数、SSE 分帧解析都覆盖到了，
还有 `feature_boundaries_test.dart` 这种把架构约束固化成断言的做法）。缺口：

- 无 repository 测试（因为大部分 feature 没有 repository）
- 无 models 解析容错测试（21 个类的 `fromJson` 零覆盖）
- 无 `selected_child` / `_refreshChildTab` 这类跨 feature 编排的测试
- 边界测试只守 R1/R2/R3，不守「presentation → data 直连」和「domain → presentation 倒置」

---

## 修复记录（2026-09-15 全部落地）

### 0. 先修工具链：`flutter test` 其实能跑

记忆里一直记着「`flutter test` 沙箱跑不了」，实测是**误判**。真正原因：环境里设了
`HTTP_PROXY=http://127.0.0.1:54128`，Dart 的 HttpClient 会把 flutter_tester 的本地
WebSocket 也走代理，报 `Unable to connect to flutter_tester process:
WebSocketException: Invalid WebSocket upgrade request`。

```bash
# Flutter 3.47.2 在 ~/Documents/fulttersdk/flutter（不在 PATH）
env no_proxy="127.0.0.1,localhost,::1" NO_PROXY="127.0.0.1,localhost,::1" \
  ~/Documents/fulttersdk/flutter/bin/flutter test
```

加 `no_proxy` 后 64 个测试（修复前基线）全绿。

### 1. R4 / R5 棘轮守卫

`test/feature_boundaries_test.dart` 从 3 条断言扩到 5 条：

- **R4** `presentation/` 不得 import `*/data/`
- **R5** `domain/` 不得 import `*/presentation/`

两条都用**棘轮**（ratchet）而非二值断言：`_knownR4` / `_knownR5` 名单**只许变短不许变长**——
名单外出现新违规 → 红；名单内某条已修好却忘了删 → 也红。后者逼着逐条收口，
防止「先记进名单再说」变成永久豁免。

### 2. 组合根：新建 `features/<f>/providers/`

`children_provider.dart` / `auth_provider.dart` 从 `domain/providers/` 挪到 feature 级
的 `providers/`。**不是**挪到 `presentation/providers/`——装配代码必然同时 import
`data/`（绑实现）和 `presentation/`（建 notifier），塞进任何一层都造成倒置。
它不属于任何一层，所以单占一个与 `data|domain|presentation` 平级的目录。

### 3. 删孤儿文件

`home/data/datasource/tasks_remote_data_source.dart` 已 `git rm`（其注释里本就写明
这是 pass-through、当初就该删）。

### 4. `ResourceNotifier` 与传输解耦

`shared/presentation/resource.dart` 不再 import `shared/data/**`，改为只吃一个
`Future<T> Function()`。**解析下沉到 repository**——原先 fetch 返回原始 JSON
再由 notifier `parse`，补上 repository 后会双重解析（repository 已转过一次领域模型）。

`decodeList` / `decodeMap` 从 `resource.dart` 迁到 `shared/utils/json_decode.dart`：
消费方是 data 层，留在 presentation 会让 data 反向 import 展示层。

### 5. 补齐 repository 层（9 个 feature 全覆盖）

刻意**不建 datasource**——项目自己已经删过一个 pass-through datasource，
再垫一层只做转发是重蹈覆辙。每个 feature 三个文件：
`domain/repositories/<x>_repository.dart`（接口）+ `data/repositories/<x>_repository_impl.dart`
（端点 + 模型映射）+ `providers/<x>_provider.dart`（组合根）。

| feature | repository |
|---|---|
| authentication / children | 已有（仅挪了组合根） |
| practice | `PracticeRepository` |
| review | `ReviewRepository` |
| home | `TasksRepository` / `QuestionBankRepository` / `TaskReviewRepository` |
| assistant | `AssistantRepository`（SSE 端口与适配器） |
| model_management | `ModelsRepository` |
| tutor | `TutorLogsRepository` |

原 `QuestionBankRemoteDataSource` **升格**为 `QuestionBankRepositoryImpl`（查询拼装本就是
repository 的活），datasource 目录随之删除。

`AssistantRepository` 的四个方法一跳转发到 `AssistantApiClient`，看着像 pass-through，
但它是**端口与适配器**：上层依赖「给我事件流」这个领域能力，不知道 SSE。
请求 DTO（`AssistantChatReq` / `TaskGenerateReq`）从 `data/assistant_api_client.dart`
下沉到 `domain/assistant_requests.dart`，否则 domain 接口得反过来引用 data。

### 6. 拆 `parent_task_review_screen`

1204 行 → **683 行**；`_QuestionCard`（含自己的编辑表单状态，533 行）独立为
`features/home/presentation/widgets/parent/parent_question_card.dart`。

> **订正**：报告原文说那 10 个 async 方法是「ViewModel 的活」，这个判断过强了。
> 实际它们都是 `await notifier.xxx() → AppToast → 可选跳转` 的薄壳，
> toast 与导航是展示层职责，留在 view 里是对的。真正该拆的就是那张卡片。

### 7. `models.dart` 拆出两组零争议模型

`shared/domain/models/models.dart` 833 行 → **708 行**：

- `TutorLogModel` → `features/tutor/domain/models.dart`
- `ModelProviderPreset` / `ModelInfo` / `ModelListResp` → `features/model_management/domain/models.dart`

**没有做 barrel 导出**——`shared/` 反向 export `features/` 会直接违反 R1。
改为更新 9 个引用方的 import。

剩下的 17 个类不动：Task / Question / WrongQuestion / Mastery 等被多个 feature 共用，
按 feature 拆只会让大部分文件从 import 1 个变成 import 3–4 个。这个文件本质上是
「后端 API 契约的镜像」，不是 feature 私有模型，先维持单一入口。

---

## 建议的修复顺序

按「投入产出比」排，不按严重程度排——P0-2 比 P0-1 好改太多，先拿它练手。
**以下 1–7 已于 2026-09-15 全部完成**，保留原始排序供追溯。

1. **给 `feature_boundaries_test.dart` 加 R4 / R5**（半天，零风险）
   - R4：`presentation/` 不得 import `*/data/`
   - R5：`domain/` 不得 import `*/presentation/`
   先把红线划上，防止继续恶化。
2. **修 P0-2 倒置**：把 `children_provider.dart` / `auth_provider.dart` 两个 DI 装配
   文件挪到 `presentation/providers/`，与其它 7 个 feature 对齐。（1 小时）
3. **删孤儿文件** `tasks_remote_data_source.dart`，或反过来让
   `parent_tasks_notifier` 改用它。（1 小时）
4. **`ResourceNotifier` 注入点从 `NetworkService` 换成抽象 `fetch` 函数**（半天）
   这样取数实现可以随时换成 repository，子类构造函数不用动。这是 P0-1 的最小切口。
5. **按 feature 补 repository**：先做 practice / review（状态机最简单），
   再做 home（最大最乱），最后 model_management / tutor。每个约半天。
6. **`parent_task_review_screen` 拆**：把 10 个 async 方法提到
   `parent_task_review_notifier`（它已经存在，只是没接这些方法），
   `_QuestionCard` 拆成独立 widget 文件。（1 天）
7. **`models.dart` 按 feature 拆**：`shared/domain/models/` → 各 feature 自己的
   `domain/models/`。可以渐进：先拆 `ModelInfo` 组（model_management 独占）和
   `TutorLogModel` 组（tutor 独占）这两个零争议的。

**明确不建议现在做的**：

- 上 `freezed` + `code generation`：会引入 build_runner，当前 96 个文件的规模收益不抵成本。
  等模型真的需要联合类型（sealed）时再说。
- 上 `go_router`：当前只有 1 处 `Navigator.push`，引入路由收益有限。
  但 `home_screen` 那 5 个局部导航字段值得先收成一个 `HomeNavState` sealed 类。
- 把 `lib/services/auth_session/` 并进 `features/authentication/`：
  合理但牵扯登录态，等 P0-1 做完再动。

## 未做 / 后续候选

按上面的修复记录，1–7 已清。仍挂着的有：

- `lib/services/auth_session/` 仍是第二个顶层数据目录，与 `features/authentication`
  职责重叠（`currentUserProvider` vs `authNotifierProvider`）。等登录态相关需求时一并收敛。
- `models.dart` 剩 17 个类（见第 7 节说明，暂不拆）。
- `home_screen.dart` 的 5 个局部导航字段（`_parentNavIndex` / `_childNavIndex` /
  `_showProfile` / `_reviewingTask` / `_editingChild`）仍靠 `setState` 手工切视图，
  全工程仅 1 处 `Navigator.push`。可以收成一个 sealed `HomeNavState`，但收益有限。
- `selected_child_provider` 仍用裸 `Ref` 扇出刷新 4 个外部 provider。
- 无 `freezed`：模型不可变/相等性靠手写，等真需要 sealed 联合类型时再引入。
