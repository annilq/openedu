# openedu · 项目长期约定

## AI 入口与分层（ADR-0036/0037）
- 前端 AI 唯一入口：`assistantNotifierProvider` + `AssistantMessageList`；家长=悬浮球 `FloatingAssistant`，娃娃=整页 `AssistantChatPage`。不再加第二个入口。
- 后端唯一端点 `POST /api/v1/assistant/chat`（ADR-0024）；可见 SubAgent 单点 `AgentRuntime.visible_businesses(role)`。
- 业务字段不前端预填：`AssistantChatReq` 只含 message/sessionId/model/history/focusInterest；subject 后端重算、grade 取 JWT。
- 依赖单向 `main/ → features/* → shared/*`；`shared/` 不得 import `features/`。`App*` 前缀只给 shared 通用组件。守卫 `frontend/test/feature_boundaries_test.dart`（R1/R2/R3）。

## Dart 陷阱 / 沙箱
- 相对 import `..` 越过 `lib/` 根时分析器「截断」不报错 → 层数自己数准。
- `flutter test` 沙箱跑不了；纯逻辑用 `/Users/yunqi/Documents/flutter/bin/dart run <script>` 直跑。
- Flutter SDK 在 `/Users/yunqi/Documents/flutter`（不在 PATH）。

## 引擎/密钥（ADR-0038 / 0041）
- `decrypt()` 解不开只返 `None`，**密文永不出门**。失败分两类：`ToolUnsupportedError`(无FC) vs `ProviderRequestError`(厂商拒绝)，落点 `agent_core/adapters/genkit.py#classify_failure`。
- 密钥漂移已止血；`env_file` 与 `DATABASE_URL` 均 CWD 无关（`config.py` 按 `__file__` 解析）。**`SECRET_KEY` 已不再是默认值**（ADR-0041 正经正文）：未显式配置时 `resolve_effective_secret_key` 生成随机密钥并落盘 `backend/.secret_key`；`secrets.py:check_runtime_secrets_health` 启动期冒烟，生产缺配阻断启动。
- 文本防护 `subagent.py:127-142`（无原生 ToolCall + 含 XML 协议标记 → TOOL_UNSUPPORTED）仍在，但它**不是根治**，只覆盖「答案带协议」形态。

## 工具 schema strict（ADR-0040）
- genkit 把 `"required": []` 在 wire 改写成「全 property 必填」+ `strict:True` → 每个可省略参数都要有**缺席编码**：字符串 `""`、整数 `0`、枚举含 `NO_FILTER="all"`。`UNSET_TOKENS` 覆盖 `""/all/any/*/none/null/nil/undefined/unset/n/a/na`。归一收口 `query/tools/_shared.py`（`optional_str`/`optional_int`/`resolve_children`）。守卫 `tests/ai/test_query_tools_contract.py`。

## 助手回答泄露：已修（2026-09-15，推理/正文分流，ADR-0043）
- `TextDelta.kind`（`ports.py TextKind`）由 adapter 按 `SegmentKind` 标注；`subagent.py` 的 `acc` **只收 kind=TEXT**，思维链走 `turn_thinking` 且不进回灌历史；工具型 subagent「无原生 ToolCall 且正文空」→ `ERROR(TOOL_UNSUPPORTED)`。落地 `77fd33f`，正文 `docs/adr/0043-reasoning-text-channel-split.md`。
- ✅ **编号悬空已订正**：该决策曾被代码误标 `ADR-0041`（0041 实为「启动期密钥健康检查」）→ 已落 ADR-0043，并把 `ports.py`/`genkit.py`/`subagent.py` 及两个测试的引用全部迁到 0043。`config.py`/`secrets.py`/`main.py` 的 0041 保持不动。
- 残留：纯自然语言「我去查一下」（无协议标记）仍当普通回答流出——泄露危害已消除，根治须模型侧原生 FC。
- ✅ **AI 气泡 Markdown 渲染已落地**：`gpt_markdown` → `shared/widgets/app_markdown.dart#AppMarkdown`（设计令牌映成 `GptMarkdownStyleSheet`；代码块复制按钮关闭、沿用原生整条复制；根 CupertinoApp 无 Material 祖先），接入 `assistant_message_list.dart`。落地 `349e4ec`（`pubspec` 加 `gpt_markdown`）。

## 已知未修小瑕疵
- 无。原「编辑模型服务商下拉误导」已于 2026-09-15 修（`349e4ec`）：`AppPickerField.value` 放开为 `T?` + 新增 `placeholder` 参数；`model_form_dialog.dart` 未匹配预设时传 `value: _presetKey`，显示「自定义（未匹配预设）」而非硬选第一个。已真机验证。

## 架构重构候选（① ② ③ ⑤ 已完成；④+⑥ 进行中）
- 已完成：① `core/guard.py`（`require_owned`/`find_owned`/`require_owned_child`，合并 7 处归属判定）② tasks write-path 下沉 `features/tasks/service.py`（`router.py` 只剩薄壳）③ SSE reducer fold（`assistant/domain/question_gen_fold.dart` + `ai_text_fold.dart`）⑤ `core/async_bridge.py#run_async`（grader/tutor/tasks 三处收口，删裸 `asyncio.run`）。
- 未完成：④+⑥ `Resource<T>` 迁移——`shared/presentation/resource.dart` 已建，home 的 today/progress/mastery 已迁；**ModelsState / DueReviewState / ReviewState / BankState / ChildrenState 仍是自建四态**。（TaskGen/Assistant/Auth/Practice 是「带动作状态机」，按 resource.dart 自述不套，不算欠账。）
- 待办：AI 集成层待业务闭环后整层重构。
- 文档缺口：③ 无 ADR；⑤ docstring 仍是 `ADR-00xx` 占位。`docs/adr/` 现 0001–0043；`docs/agent-core-architecture-review.md` §7 与 `AGENTS.md` 风险段已于 2026-09-15 标注 P0/P1/P2 关闭。

## 后端测试/沙箱约束
- pytest 前 `cd backend && mv .env .env.hidden`（避 broker 读 .env），跑完恢复。用 `.venv/bin/ruff` / `.venv/bin/pytest`。
- zsh 里 `grep "a\|b"` 静默空，用 Grep 工具或分次单模式 grep。
- 偶发 `PermissionError: Sensitive content approval timed out` → 重跑即可。
