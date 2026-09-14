# 前端分层与 feature 边界：shared 只向下、模型管理独立成 feature

前端此前没有一条成文的依赖方向规则，于是同时长出两类越界：`shared/` 反向 import `features/`（`shared/widgets/app_model_selector.dart:5` → `features/tutor/...`），以及**业务归属错位**——模型管理在后端是独立 feature（`backend/app/features/model_management/router.py:22`，ADR-0015），在前端却寄居在 `features/tutor/` 下。本 ADR 固化前端分层：`main/ → features/* → shared/*` 单向不回流，并把模型管理归位为独立 feature。

## 规则

1. **依赖方向单向**：`main/` → `features/*` → `shared/*`。`shared/` 是跨 feature 基础层（设计令牌、通用组件、DTO、网络），**不得 import `features/`**。
2. **feature = 一条业务能力，与后端 `app/features/*` 一一对应**：`tutor` ↔ `tutor`、`assistant` ↔ `assistant`、`model_management` ↔ `model_management`。
3. **`App*` 前缀 = 通用设计系统组件，只在 `shared/widgets/` 定义**。组件一旦订阅某个 feature 的 provider、或携带该 feature 的领域语义（如 builtin / custom / isDefault），就不再通用，必须落回该 feature。
4. **feature 之间不得横向互引**，唯一豁免是 `features/home/presentation/`——它是展示层组合根，负责把各 feature 的页面装配进导航。

## 本决策依据

- **归位错误（本次修复）**：旧 `features/tutor/` 下 4 个文件里有 3 个与「伴学答疑」无关——`models_notifier.dart`（模型 CRUD + 服务商预设）、`parent_model_management_screen.dart`、`model_form_dialog.dart`，全部属模型管理。目录名与内容不符的代价是真实定位成本：找模型管理要先猜它在哪。
- **模型管理独立 feature（迁移后）**：`frontend/lib/features/model_management/presentation/providers/models_notifier.dart:95`（`ModelsNotifier`）、`:169`（`modelsNotifierProvider`）、`presentation/screens/parent_model_management_screen.dart:15`、`presentation/screens/model_form_dialog.dart:18`、`presentation/widgets/model_selector.dart:17`。
- **依赖倒置（本次修复）**：`AppModelSelector` 认识模型域语义且直接 `ref.watch(modelsNotifierProvider)`，却被放在 `shared/widgets/`，于是 shared 必须反向 import feature。归位后改名 `ModelSelector` 并落 `features/model_management/presentation/widgets/`（`model_selector.dart:17`）。
- **调用方经 home 单向引用**：家长导航 index 7 挂 `ParentModelManagementScreen`（`features/home/presentation/screens/home_screen.dart:227`）；出题表单消费 `ModelSelector(showDefaultOption: false)` 与 `modelsNotifierProvider`（`features/home/presentation/widgets/parent/parent_task_form_view.dart:270`、`:101`）。`home` 是既有组合根——它已 import `review` / `practice` / `profile` / `children` / `assistant`，本次不新增方向。
- **后端对齐**：模型管理 REST 前缀 `/models`，仅 `CurrentParent` 可访问，`api_key` 落库前 Fernet 加密（`backend/app/features/model_management/router.py:22`，ADR-0015）。
- **`features/tutor` 收敛后只剩日志**：`features/tutor/presentation/providers/tutor_logs_notifier.dart:12` → `GET /tutor/logs`（`backend/app/features/tutor/router.py:39`），与后端 tutor feature 的保留边界一致（ADR-0036）。
- **不变量测试**：前端原本**没有**分层守卫（后端有 `backend/tests/ai/test_layering_invariants.py`）。本 ADR 补 `frontend/test/feature_boundaries_test.dart`，以 `dart:io` 静态扫描固化 R1/R2/R3 三条断言，跑在 `flutter test`（`.github/workflows/ci.yml` 前端 job 的第二道门禁）。
- **顺带查出的既有缺陷（已修）**：`/features/assistant/data/assistant_api_client.dart:5-6`、`/features/assistant/domain/question_gen_fold.dart:1` 三个 import 多写了一级 `../`（`../../../../shared/…` → 实际落到 `frontend/shared/…`，该目录不存在）。它们此前能编译，是因为 **Dart 分析器在 `..` 越过 `lib/` 根时截断而非报错**（实测：`lib/shared/widgets/x.dart` 写 `../../../features/…` 仍解析到 `lib/features/…`；写成不存在的普通文件名才会报 `uri_does_not_exist`）。已改为正确的 `../../../shared/…`；R1 的路径解析也按同样规则截断，否则一条层数写错的 `shared → features` 违规会既编译通过又被扫描漏掉。

**Considered Options**：① 保留 `shared/widgets/app_model_selector.dart` 不动、只改文档（省掉两处 import 改动，但 shared→feature 的边会随 feature 增删而断，且把 feature 内部状态钉成 public 契约，拒绝）；② 把 `models_notifier` 提到 `shared/`（消除倒置，但模型管理是家长专属业务、非家长无权限访问该端点，shared 不是业务层，拒绝）；③ 模型管理独立 feature + 选择器随 feature 走 + 调用方经 home 单向引用 + 加分层断言（采用）。

**Consequences**：新增模型能力（新 provider 预设、新字段、新交互）只动 `features/model_management/`，出题表单与设置页零改动；`features/tutor/` 名实相符，只剩一条日志端点。代价与遗留：① `ModelSelector` 改名（原 `AppModelSelector`）——它不在 shared，继续挂 `App*` 会误导通用组件语义；② `ModelInfo` / `ModelListResp` / `ModelProviderPreset` 仍在 `shared/domain/models/models.dart:755-840`，与 `ModelCreateReq` / `ModelUpdateReq`（在 feature 内）分处两地，本次不拆是因为该文件是本仓 DTO 单一收口点，若将来按 feature 拆 DTO 则三个随之迁出；③ `features/model_management` 目前只有 presentation 层，未建 data/repository 层——HTTP 仍直调 `NetworkService`，与 `practice` / `review` 的薄 feature 一致，等该能力长出第二条数据来源再抽。
