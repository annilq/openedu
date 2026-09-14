# openedu · 项目长期约定

## AI 能力：前端只有一个入口（ADR-0036）

- **一个 provider、一份渲染、一条会话**：`assistantNotifierProvider`（`features/assistant/presentation/provider/assistant_notifier.dart`）是唯一对话状态源；消息渲染统一走 `AssistantMessageList`（`features/assistant/presentation/widgets/assistant_message_list.dart`）。
- **角色决定入口形态**：家长端 = 右上角悬浮球 `FloatingAssistant`（`main/app.dart` 按 `user.isParent` 挂载）；娃娃端 = 整页 `AssistantChatPage`，导航页签「问 AI 老师」（`home_screen.dart`）。**不要再给某个角色加第二个 AI 入口**。
- **后端也是一个端点**：`POST /api/v1/assistant/chat`（ADR-0024），可见 SubAgent 由 `AgentRuntime.visible_businesses(role)` 单点决定。parent = {question, query, tutor}；child = {query, tutor}，child 问出题被强制改写成 tutor。
- **业务字段不要前端预填**：`AssistantChatReq` 只有 message/sessionId/model/history/focusInterest；subject 由后端 `detect_subject(message)` 重算、grade 取 JWT。历史教训：旧 tutor 页的学科/年级/知识点控件没进请求体，是死 UI，已删。
- `features/tutor` 只剩家长侧日志 `GET /tutor/logs`（`tutor_logs_notifier.dart`）。

## 前端分层与 feature 边界（ADR-0037）

- **依赖方向单向**：`main/ → features/* → shared/*`。**`shared/` 不得 import `features/`**；feature 之间不得横向互引，唯一豁免 `features/home/presentation/`（展示层组合根，装配各 feature 页面）。
- **feature ↔ 后端 `app/features/*` 一一对应**：`assistant` / `authentication` / `children` / `home` / `model_management` / `practice` / `profile` / `review` / `tutor`。
- **`App*` 前缀只给 `shared/widgets/` 通用设计系统组件**。组件一旦订阅某 feature 的 provider（或带着该 feature 的领域语义），就落回该 feature —— 例：`AppModelSelector` → `ModelSelector`，现居 `features/model_management/presentation/widgets/`。
- **模型管理归 `features/model_management/`**（`models_notifier.dart` + `parent_model_management_screen.dart` + `model_form_dialog.dart` + `model_selector.dart`）。调用方只在 home：家长导航 index 7、出题表单 `ModelSelector(showDefaultOption: false)`。
- **守卫**：`frontend/test/feature_boundaries_test.dart` 静态扫描 R1/R2/R3（跑在 `flutter test`）。改前端目录结构前先跑它；命令级判据：`grep -rn "features/" frontend/lib/shared` 须为空。

## Dart 语言陷阱（实测）

- **相对 import 的 `..` 越过 `lib/` 根时，分析器是「截断」而非报错**：`lib/shared/widgets/x.dart` 写 `../../../features/…`（多一级）照样解析到 `lib/features/…`；只有目标文件名真的不存在才报 `uri_does_not_exist`。→ 写相对 import 别靠 analyze 兜底，层数自己数准；写静态扫描工具时也要按同样规则截断，否则违规会被漏掉。（本仓曾有 3 处 `../../../../shared/…` 多写了一级，已修。）
- 沙箱里 `flutter test` 跑不了，但**纯 `dart:io` 的 Dart 脚本可以用 `/Users/yunqi/Documents/flutter/bin/dart run <script>` 直跑**——切纯逻辑测试（不碰 widget 树）时，可以先用等价的临时脚本验证断言逻辑，再由 CI 的 `flutter test` 承担正式执行。

## 前端沙箱约束

- Flutter SDK 在 `/Users/yunqi/Documents/flutter`（不在 PATH）。
- `flutter analyze` 可跑（会写 `~/.dartServer`，可能触发沙箱授权）；`flutter_tester` / `flutter test` 在沙箱内跑不起来 → 前端改动只能 analyze + 真机验证。

## 后端测试约束

- 必须 `cd backend && mv .env .env.hidden` 再跑 pytest（否则 pydantic-settings 读 .env 被 broker 拦），跑完恢复。
- 用 `.venv/bin/ruff` / `.venv/bin/pytest`（`uv` 不在 PATH）；Bash cwd 不跨调用持久，用 `cd backend && ...` 串联。
