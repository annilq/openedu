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

## 引擎失败归因与密钥（ADR-0038）

- **`api_key` 解不开只能返回 `None`**（`app/core/crypto.py#decrypt`）——曾返回密文原文，Fernet 密文被当 API Key 发给厂商（401 + 凭据外泄，事故现场 `Your api key: ****xOOR` 的 `xOOR` 是密文尾号）。
- **`SECRET_KEY` 默认值漂移会静默废掉所有已存密钥**：Fernet 密钥 = `MODEL_APIKEY_SECRET or SECRET_KEY`（走 SHA-256→base64）。仓库根 `.env`（值 `dev-secret-change-me`）已弃用改名后，`SECRET_KEY` 回落默认 `changeme` → 旧密文再也解不开。**生产/长期使用请显式配 `MODEL_APIKEY_SECRET`**；已存在的密文按当前密钥重填即可恢复。
- **失败分两类，不得混用**：模型没有 function calling → `ToolUnsupportedError` / `ERROR(TOOL_UNSUPPORTED)`（ADR-0033）；厂商拒绝（认证/限流/网络/参数）→ `ProviderRequestError(kind)` / `ERROR(PROVIDER_ERROR)`，用户提示走 `err.user_hint`（原始厂商报文只进日志）。分类单一落点 `agent_core/adapters/genkit.py#classify_failure`（默认必须落 ProviderRequestError）。
- **上层禁止 `except Exception` 把引擎失败抹成「请添加模型」**：出题/批改路径已分流（`features/tasks/service.py`、`features/review/service.py` → `ErrCode.LLM_REQUEST_FAILED` = `SYS_10007`，502）。
- 后端服务端 warning 已有密钥解密失败日志；**启动期密钥健康检查仍缺**（家长要等到提问失败才知道）。

## 后端测试约束

- 必须 `cd backend && mv .env .env.hidden` 再跑 pytest（否则 pydantic-settings 读 .env 被 broker 拦），跑完恢复。
- 用 `.venv/bin/ruff` / `.venv/bin/pytest`（`uv` 不在 PATH）；Bash cwd 不跨调用持久，用 `cd backend && ...` 串联。
- **zsh 里 `grep "a\|b"` 会静默返回空**（`\|` 交替在本 shell 下失灵），要多次搜索就用 Grep 工具或分多次单模式 grep，别被空结果误导。
- 沙箱偶发 `PermissionError: Sensitive content approval timed out`（broker 审批准时），**重跑即可**，不是代码问题。
