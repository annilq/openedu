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
- **密钥漂移已止血（2026-09-15）**：`backend/.env` 已显式写入随机 `MODEL_APIKEY_SECRET`（Fernet 密钥不再由 `SECRET_KEY` 派生），`ModelConfig` 唯一那行已按新密钥重加密并验证 `resolve_engine` 能取到明文。`app/core/config.py` 的 `env_file` 已改为按 `__file__` 解析绝对路径——**不再随启动 CWD 漂移**（原先在仓库根起服读不到 `backend/.env`，会静默回落默认密钥，与事故同一失效模式）。`DATABASE_URL=sqlite:///./app.db` 仍是相对路径：换 CWD 会指向另一个库文件，起服请固定 `backend/`。
- **`SECRET_KEY` 仍是默认值 `changeme`**（JWT 签名用），且 `docker-compose.yml` 用另一个默认 `${SECRET_KEY:-change-me-in-prod}`。改它会失效所有登录态，故未动；生产部署必须显式配置。
- **失败分两类，不得混用**：模型没有 function calling → `ToolUnsupportedError` / `ERROR(TOOL_UNSUPPORTED)`（ADR-0033）；厂商拒绝（认证/限流/网络/参数）→ `ProviderRequestError(kind)` / `ERROR(PROVIDER_ERROR)`，用户提示走 `err.user_hint`（原始厂商报文只进日志）。分类单一落点 `agent_core/adapters/genkit.py#classify_failure`（默认必须落 ProviderRequestError）。
- **模型把工具调用写成文本时也走 `TOOL_UNSUPPORTED` 硬失败**（ADR-0033 补充，`agent_core/subagent.py:127-142`）：工具型 subagent 某轮无原生 `ToolCall` 但文本含调用协议标记（`<invoke name=` / `"name": "` / `function_call`）**且**点名了已注册工具 → 抛 `ERROR(TOOL_UNSUPPORTED)` 并**整段丢弃本轮回显思考**（`turn_thinking` 缓冲到轮次结束再判定，`:193,219,267,286`）。绝不能把 `acc` 当 `assistant_message` 回流——那是把内部协议泄露给用户。**实测 `deepseek-v4-flash` 原生 FC 正常**（真接口返回 `TOOL_REQUEST`），触发路径的是本地 Ollama / 中转模型这类「叙述式调用」模型。无协议标记的普通文本收尾不受影响。
- **上层禁止 `except Exception` 把引擎失败抹成「请添加模型」**：出题/批改路径已分流（`features/tasks/service.py`、`features/review/service.py` → `ErrCode.LLM_REQUEST_FAILED` = `SYS_10007`，502）。
- **模型只有一份来源（ADR-0039）**：内置模型目录 `BUILTIN_MODELS` 已整体移除——`config.py` 无该字段、`ai/engine.py` 只剩「显式 ModelConfig id → 本家长 is_default」两条优先级、`GET /models` 只剩 `custom`、前端 `ModelInfo.isBuiltin`/`ModelListResp.builtin` 已删。**新增模型 `api_key` 必填**（后端 `ModelConfigCreate` + 前端 `ModelCreateReq.apiKey` 的非空 `String`）；编辑留空 = 不修改。响应 `ModelConfigResp` 从不下发 api_key（明文密文都不给）。
- **`RequestValidationError` 处理器曾把自定义校验器的 422 变成 500**：pydantic v2 会把自定义校验器抛的 `ValueError` 对象塞进 `ctx["error"]`，`jsonable_encoder` 序列化失败。已加 `app/core/errors.py#_safe_validation_errors`（只留 loc/msg/type）。**此后新增任何 `field_validator` 都不会再踩**。
- 已知小瑕疵（未修）：编辑模型时若 provider+baseUrl 匹配不到服务商预设，下拉会显示第一个预设（DeepSeek）却不出模型名建议（`model_form_dialog.dart`）——显示误导，但保存取的仍是 `initial.provider`，写不坏数据。
- 后端服务端 warning 已有密钥解密失败日志；**启动期密钥健康检查仍缺**（家长要等到提问失败才知道）。

## 工具 schema 的 strict 自洽性（ADR-0040）——踩过一次的坑

- **genkit 会把我们写的 `"required": []` 在 wire 上改写成「所有 property 必填」**：`genkit_openai/models/model.py#_get_tools_definition`（`:88-120`）对每个工具无条件套 `openai.lib._pydantic._ensure_strict_json_schema`（该函数 `:55-57` 直接 `required = 全部 property`）并打 `strict: True`。→ **模型被迫为每个参数编一个值，别再以为「不传」是默认行为。**
- **推论（新工具必须遵守）**：每个可省略参数都要有**类型合法的缺席编码** —— 字符串 `""`、整数 `0`；**枚举型参数必须把 `NO_FILTER`（`"all"`）列进 `enum`**，否则模型无合法值可填。归一收口在 `app/ai/subagents/query/tools/_shared.py`：`optional_str` / `optional_int` / `resolve_children`（后者是全部定位工具的公用入口，改动它会同时影响 7 个工具）。
- **翻车现场**：`status=""` 被判非法 → 回灌「status 只能是 [...] 之一」→ 模型反复试探 → 撞 SOP「不重复调用同一工具」→ 空转并把调用叙述成文本外泄。`limit: integer` 同类：strict 下必填 → 模型自编数字 → **静默截断结果**；或填 `0` → 撞「必须大于 0」。**第三种形态是文本化缺席**：模型把「没有目标」写成字符串 `"null"` 传给 `child_id` → 被当 uuid 解析 → `child_id 不是合法的 uuid：'null'`。故 `UNSET_TOKENS` 覆盖 `""/all/any/*/none/null/nil/undefined/unset/n/a/na`。
- **回灌给模型的错误必须带可执行出路**（`_as_uuid(..., hint=...)`）：模型靠自纠继续，只说「不是 uuid」它只会换个猜法重试。新增工具/校验时照此写错误消息。
- **AI 入口的定位参数只来自模型 + JWT，不接受客户端预填**：`extra["child_id"]` 由端点从 JWT 写入（`assistant/service.py:85-90`；child → 自己，parent → `None`），`resolve_children` 在孩子分支直接返回本人、**忽略入参**。想让「家长当前浏览的娃娃」成为默认查询范围，正确形态是 `AssistantChatReq.focusChildId` → 服务端校验归属 → `extra["focus_child_id"]` 仅作兜底，须单独立 ADR（ADR-0040「明确不做」）。
- **诊断方法（可复用）**：判断「模型为何行为异常」要**打真接口**看 wire schema，别只读源码——`genkit_openai` 会在发包前加工 schema。复刻方式：`_ensure_strict_json_schema(SPEC.schema, path=(), root=SPEC.schema)`，用 `.venv/bin/python` + `urllib` 直连 `{base_url}/chat/completions`（DB 取 `modelconfig` + `decrypt` 拿 key），打印机 `tool_calls[].function.arguments`。
- **守卫测试**：`tests/ai/test_query_tools_contract.py` 有 4 条（证据锚点 / 枚举含 NO_FILTER / 行为级「缺席编码填满 ≡ 不传」/ 非法值仍报错）。改工具 schema 先跑它。
- genkit **不**校验工具入参（`_core/_action.py:499-500`：`input_schema` 为 dict 时 `_input_type=None`）→ 入参校验只能靠 handler 自己。

## 后端测试约束

- 必须 `cd backend && mv .env .env.hidden` 再跑 pytest（否则 pydantic-settings 读 .env 被 broker 拦），跑完恢复。
- 用 `.venv/bin/ruff` / `.venv/bin/pytest`（`uv` 不在 PATH）；Bash cwd 不跨调用持久，用 `cd backend && ...` 串联。
- **zsh 里 `grep "a\|b"` 会静默返回空**（`\|` 交替在本 shell 下失灵），要多次搜索就用 Grep 工具或分多次单模式 grep，别被空结果误导。
- 沙箱偶发 `PermissionError: Sensitive content approval timed out`（broker 审批准时），**重跑即可**，不是代码问题。
