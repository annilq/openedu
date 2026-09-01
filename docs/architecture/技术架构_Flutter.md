# Flutter 技术架构文档

> 适用项目：娃娃学习 App（平板优先，iOS/安卓双端一套代码）
> 配套文档：`技术架构_后端.md`、`功能规格_PRD_全三期.md`、`娃娃学习App_ADR.md`
> 架构基线：参考 [`flutter-clean-architecture-riverpod`](https://github.com/Uuttssaavv/flutter-clean-architecture-riverpod) —— Clean Architecture + Riverpod。

---

## 1. 文档目的

定义前端的**分层、目录、状态管理、网络层、路由、存储、平板适配**与**二三期扩展点**，使后续 Flutter 开发有可落地的结构遵循，而非凭感觉堆页面。

---

## 2. 选型结论与理由

| 决策 | 选型 | 理由 |
|---|---|---|
| 原生形态 | **Flutter 原生 App** | 一套代码出 iOS/安卓，平板适配成熟，体验优于 PWA/小程序（ADR-006） |
| 架构范式 | **Clean Architecture** | data/domain/presentation 严格分层，依赖指向内核（domain），可测、可替换、可扩展 |
| 状态管理 | **Riverpod** | 编译期安全、依赖注入清晰、易测试；契合本项目的多页面共享「当前家长/娃娃/任务」状态 |
| 代码生成 | **freezed + auto_route + build_runner** | 不可变模型/联合状态、类型安全路由，减少样板 |
| 网络 | **Dio** | 拦截器（token 注入、统一错误）、适配后端 REST |
| 本地存储 | **shared_preferences** | 存 token、家长设置（每日时长/内容范围）、离线缓存错题 |

> 注：本项目当前 `frontend/` 仅为可跑骨架（login/home 占位），**尚未落地下文分层**。本文档是开发蓝图，后续重构须以此为准。

---

## 3. 总体分层（依赖指向内核）

```
presentation (UI，依赖最多)
      │ 监听 StateNotifierProvider
      ▼
domain (纯 Dart 业务逻辑，无 Flutter 依赖)
      │ 定义抽象 Repository / 暴露 Provider(usecase)
      ▼
data (最外层：通信与缓存)
      │ Repository 实现 + DataSource(remote/local)
      ▼
  后端 REST API / 本地存储
```

规则：**外层依赖内层，内层不反向依赖**。UI 不直接调 Dio，必须经 domain Provider → Repository → DataSource。

---

## 4. 目录结构（基于参考 repo，适配本项目）

```
lib/
├── configs/
│   └── app_configs.dart            # 环境配置：API Base URL、主题开关
├── main/
│   ├── app.dart                    # ProviderScope + AppRouter 初始化
│   ├── app_env.dart                # 环境枚举 dev/staging/prod
│   ├── main_dev.dart               # 开发入口
│   ├── main_staging.dart           # 预发入口
│   └── observers.dart              # NavigatorObserver / Riverpod Observer
├── routes/
│   ├── app_route.dart              # auto_route 定义
│   └── app_route.gr.dart           # 生成
├── services/                       # 全局服务（跨 feature）
│   └── auth_session/               # 当前登录用户/角色的缓存与读取
│       ├── data/datasource/auth_local_datasource.dart
│       ├── data/repositories/auth_session_repository_impl.dart
│       ├── domain/providers/auth_session_provider.dart
│       ├── domain/repositories/auth_session_repository.dart
│       └── presentation/...
├── shared/                         # 跨 feature 复用
│   ├── data/
│   │   ├── local/                  # shared_prefs 存储服务
│   │   └── remote/                 # dio_network_service / network_service 抽象
│   ├── domain/
│   │   ├── models/                 # user / task / question / answer / progress / child
│   │   └── providers/              # dio / storage service provider
│   ├── exceptions/                 # http_exception
│   ├── mixins/                     # exception_handler_mixin
│   ├── theme/                      # 护眼配色、字号、text_theme（低龄友好）
│   ├── widgets/                    # app_error / app_loading / 通用卡片
│   └── globals.dart
├── features/                       # 按业务模块隔离
│   ├── authentication/             # 登录、角色分发
│   ├── home/                       # 首页：家长看娃娃+任务；娃娃看今日任务+进度
│   ├── practice/                   # 做题：题目展示、作答、批改反馈
│   ├── checkin/                    # 打卡
│   ├── children/                   # 家长：娃娃账号管理（列表 + 添加娃娃入口）、每日时长/内容范围设置
│   ├── profile/                    # 设置、连续打卡、徽章
│   ├── review/           (二期)    # 错题本 + 遗忘曲线复习（T07 已落地）
│   └── tutor/            (三期)    # AI 伴学答疑（T08）+ AI 使用管控设置（T10，套用后端安全层/管控层）
└── main.dart                       # 指向 main_dev / main_staging
```

每个 `feature` 内部统一三层：

```
features/<name>/
├── data/
│   ├── datasource/      # <name>_remote_data_source / _local_data_source
│   └── repositories/    # <name>_repository_impl
├── domain/
│   ├── providers/       # usecase 型 provider（组合 repository）
│   ├── repositories/    # <name>_repository 抽象
│   └── models/ (或引 shared)
└── presentation/
    ├── providers/state/ # <name>_notifier.dart + <name>_state.dart(.freezed)
    ├── screens/         # <name>_screen.dart
    └── widgets/         # 模块内复用组件
```

---

## 5. 各层职责与约定

### 5.1 data 层
- **DataSource**：`remote` 经 `NetworkService` 调后端；`local` 经 `StorageService` 读 shared_prefs（如离线缓存错题、家长设置）。
- **Repository 实现**：协调多个 DataSource，是 domain 与 data 的桥。

### 5.2 domain 层（纯 Dart，无 Flutter）
- **models**：实体（映射后端 schema，freezed 不可变）。
- **repositories（抽象）**：定义外层预期能力，如 `TaskRepository { Future<Task> generate(...); Future<List<Task>> today(); }`。
- **providers**：描述应用逻辑处理（扮演 UseCase），直接消费 Repository。

### 5.3 presentation 层（无业务逻辑）
- **screens**：发事件（如「提交作答」），`ref.watch` 监听状态。
- **state**：`freezed` 定义 `Idle/Loading/Success/Error` 联合状态；`Notifier` 处理副作用。

---

## 6. 状态管理（Riverpod）

- 根：`main/app.dart` 用 `ProviderScope` 包裹 `MyApp`。
- 表现层状态：Widget 监听 `StateNotifierProvider<XNotifier, XState>`。
- 组合式 DI（自底向上依赖图）：

```dart
// shared: 暴露基础服务
final dioNetworkServiceProvider = Provider<NetworkService>((ref) {
  return DioNetworkService();
});

// feature: repository 接线（注入 datasource）
final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final ds = ref.watch(taskRemoteDataSourceProvider);
  return TaskRepositoryImpl(ds);
});

// feature: notifier 接线（注入 repository，并触发初始拉取）
final practiceNotifierProvider =
    StateNotifierProvider<PracticeNotifier, PracticeState>((ref) {
  final repo = ref.watch(taskRepositoryProvider);
  return PracticeNotifier(repo);
});
```

- 多页面共享：`authSessionProvider` 暴露当前用户/角色，登录后 `home` 据此分流「家长首页 / 娃娃首页」。

---

## 7. 网络层

- `shared/data/remote/network_service.dart`：抽象 `get/post/put/delete`，返回统一 `Response` 或抛 `HttpException`。
- `dio_network_service.dart`：Dio 实现，配拦截器：
  - **Token 拦截器**：从 `StorageService` 取 JWT，注入 `Authorization`。
  - **错误拦截器**：统一解析后端 `{detail: "..."}`，转 `HttpException`，UI 经 `exception_handler_mixin` 展示 `AppError`。
- **API Base URL**：`app_configs.dart` 按环境区分；平板联调时改 `kApiBase` 为电脑局域网 IP（对应后端 `CORS_ORIGINS`）。

### 7.1 AI flow 客户端（Genkit Dart client，迁移 08b）

后端 AI 能力（答疑 `/api/v1/ai/tutor/ask`、出题预览 `/api/v1/ai/tasks/generate`）统一暴露为**原生 Genkit action 端点**（后端 `genkit-fastapi` 的 `serve_flow`）。前端不再自研 SSE 解析，改用官方 `package:genkit/client.dart`：

- **封装**：`shared/data/remote/genkit_ai_client.dart` 的 `GenkitAiClient` 持两个 `defineRemoteAction`（`/ai/tutor/ask`、`/ai/tasks/generate`），`fromResponse` / `fromStreamChunk` 映射 `TutorReply` / `QuestionPreview`。
- **Bearer 注入**：Dart 原生 `http.Client` 不经 Dio 拦截器，故每次 `call` / `stream` 经 `headers: {'Authorization': 'Bearer $token'}`（token 来自 `StorageService.getToken()`）注入——与后端 `handle_genkit_request` 兼容。
- **REST 仍用 Dio**：`NetworkService` 的 REST（登录、任务 CRUD、非流式 `ask` / `batch-generate`、模型管理）维持 Dio + 拦截器不变；**仅 AI 流式**走 genkit client。
- **退役**：`shared/data/remote/sse_client.dart` 与自定义 SSE 信封（`token` / `question` / `safety_refusal` / `done` / `error`）已于 08b 删除，前端流式解析统一收敛到 Genkit 原生协议（`data: {"message": <chunk>}` 逐帧 / 末帧 `data: {"result": <output>}`）。

---

## 8. 路由（auto_route）

- `app_route.dart` 声明页面与守卫（如未登录跳 `/login`，家长页守卫 role）。
- 生成 `app_route.gr.dart`。
- 多环境：`main_dev` / `main_staging` 切换 `app_env` 与 base url，便于本地联调与预发验证。

---

## 9. 本地存储（shared_preferences）

| Key（建议） | 内容 | 用途 |
|---|---|---|
| `auth_token` | JWT | 网络层鉴权 |
| `current_user` | 用户 JSON（含 role） | 角色分流、首页 |
| `parent_settings` | 每日时长上限、内容范围 | 家长管控（对应后端安全设计 §9） |
| `cached_wrong` (二期) | 错题本地缓存 | 离线复习 |

---

## 10. 平板适配（低龄优先）

- **布局**：用 `LayoutBuilder` / `flutter_layout_grid` 做平板双栏（左任务列表、右做题区），手机降级单栏。
- **字号**：正文 ≥ 20sp，选项 ≥ 22sp，照顾低年级阅读。
- **护眼主题**：`theme/` 提供低饱和暖色、大圆角、高对比按钮；避免纯白刺眼背景。
- **横竖屏**：默认支持横屏（平板常见握持），关键作答页锁定防误触。
- **交互**：大点击区、语音/震动轻反馈、减少文字输入（客观题点选为主）。

---

## 11. 模块 / Feature 划分与状态清单

| Feature | 关键 Provider/Notifier | 关键 Screen | 说明 |
|---|---|---|---|
| authentication | `loginNotifier` | `login_screen` | 登录后写 token+用户，按 role 跳 home |
| home | `homeNotifier`（家长：children+tasks；娃娃：today+progress） | `home_screen` | 角色分流首页 |
| practice | `practiceNotifier`（加载题目→提交→批改→解析） | `practice_screen` / `question_card` | 核心做题闭环 |
| checkin | `checkinNotifier` | `checkin_screen` / 首页按钮 | 任务打卡 |
| children | `childrenNotifier`（增/列娃娃；createChild 成功自动刷新） | `add_child_screen`（表单：昵称/账号/密码/年级，前端校验+防重入+错误兜底）；入口在家长首页娃娃列表区（空态大按钮 / 列表尾 + 块） | 家长专属；创建入口 T13 补齐（F-102 / AC-102） |
| profile | `profileNotifier`（连续天数、徽章、设置） | `profile_screen` | 轻量激励展示 |
| review (二期，T07 已落地) | `dueReviewNotifier`（待复习队列）/ `childWrongQuestionsProvider`（娃娃自查）/ `parentWrongQuestionsProvider`（家长含答案） | `review_screen` / `wrong_questions_screen` | 遗忘曲线复习作答 + 错题本；娃娃端答题不含答案（防作弊） |
| home (二期，T07 扩展) | `masteryNotifier`（家长掌握度看板）/ `progressNotifier` | `parent_dashboard` 掌握度进度条 + 错题列表区块 + AI 答疑日志区块 | 家长查看孩子知识点掌握度与答疑记录 |
| tutor (三期，T08/T10/T12 已落地) | `tutorNotifier`（对话：Genkit 流式 `GenkitAiClient.streamTutor` → `/api/v1/ai/tutor/ask`（原生 Genkit action，逐 token 打字机），状态机 Idle→Loading→Loaded，业务错误透出文案）/ `tutorLogsNotifier`（家长日志：GET /tutor/logs）/ `tutorQuotaNotifier`（管控配置：GET·PUT /tutor/quota）/ `tutorUsageNotifier`（当日用量：GET /tutor/usage） | `tutor_chat_screen`（娃娃答疑页，Loading 态「思考中」占位 + 防重入 + 错误保留历史气泡）；`tutor_quota_screen`（家长设置：次数/时长上限 + 学科白名单） | AI 伴学答疑（F-302/F-304/F-305）+ 使用管控（T10 故事 23/26，enforcement 在后端）；流式经 genkit client（08b 统一协议） |
| task gen (三期，T08 出题预览) | `taskGenNotifier`（家长出题：`generate` 走 REST `/tasks/batch-generate` 落库；`preview` 走 `GenkitAiClient.streamTasks` → `/api/v1/ai/tasks/generate` 原生 Genkit action，逐 `QuestionPreview` 题卡浮现） | `parent_task_form_view`（含「预览出题」按钮 → `TaskGenPreview` 逐卡渲染；满意后「保存为任务」落库） | 家长按学科/年级/知识点批量出题；预览为流式 Genkit 协议，与答疑共用 `genkit` client（08b 统一） |

---

## 12. 错误处理与通用组件

- `shared/widgets/app_loading.dart`：统一加载态。
- `shared/widgets/app_error.dart`：统一错误态（可重试）。
- `shared/mixins/exception_handler_mixin.dart`：Notifier 内统一捕获 `HttpException` → 转 Error 状态。

---

## 13. ★ 二三期扩展点

- **二期 错题本/复习（已落地，`features/review/`）**：娃娃首页复习卡片显示今日待复习数（`/review/due`），进入逐题作答（`/review/answer`，答对推进阶段/毕业、答错重置计时，前端仅交互不做调度）；错题本娃娃端走 `/tasks/wrong-questions`（answer=None 防作弊），家长端走 `/tasks/children/{id}/wrong-questions`（含答案）；家长看板新增掌握度区块（`/tasks/children/{id}/mastery`，进度条 + 等级）。
- **三期 AI 答疑（已落地，`features/tutor/`，T08）**：娃娃首页「问 AI 老师」入口进入 `tutor_chat_screen`，调用 `POST /tutor/ask`；内容安全由**后端 `domain/safety.py` 三层防护**统一保证（输入/输出校验 + 年龄锁系统提示），前端无需重复校验、也不渲染拒答原因；家长端 `parent_dashboard` 新增 AI 答疑日志区块（`GET /tutor/logs`，越权 403）。聊天记录由后端 `tutor_log` 落库供家长监督（F-305）。
- **AI 使用管控（已落地，T10，故事 23/26）**：enforcement 全在后端（`domain/quota.check_quota`，越界 403 / 超额 429）；娃娃端 `tutorNotifier` 捕获 `AppException` 透出服务端提示文案（如「今日次数已达上限」）作为气泡；家长端 `parent_dashboard` 新增「AI 使用管控」区块（当前配置摘要 + 今日用量），「设置」进入 `tutor_quota_screen`（每日提问上限 / 时长上限分钟 / 学科白名单 FilterChip 多选，整体覆盖保存，留空=不限、0=禁用）。
- **AI 伴学收尾（已落地，T12）**：`TutorNotifier` 补齐状态机 **Idle(TutorInitial) → Loading(TutorLoading) → Loaded(TutorLoaded)**——提问立即进入 Loading（娃娃气泡即时上屏），回复后进 Loaded；错误场景不销毁对话，以**提示气泡**保留在列表里（对话场景对 Error 态的适配变体）；答疑页 `tutor_chat_screen` 对 Loading 渲染消息列表 +「AI 老师正在思考…」占位。notifier 状态迁移（含防重入、AppException 透出、四态）均以 **mocktail** 覆盖单测。
- **知识库（三期后端）**：前端无需改动，仅后端 `/knowledge/*` 提供知识点检索，出题接口透传。

---

## 14. 关键依赖（pubspec 建议）

```yaml
dependencies:
  flutter_riverpod: ^2.x
  freezed_annotation: ^2.x
  auto_route: ^7.x
  dio: ^5.x
  shared_preferences: ^2.x
  json_serializable: ^6.x
dev_dependencies:
  build_runner: ^2.x
  freezed: ^2.x
  auto_route_generator: ^7.x
```

---

> 前端结构须与 `技术架构_后端.md` 的 API 契约（§7）对齐；任何新增页面/状态应先登记到本节「状态清单」，再实现。
