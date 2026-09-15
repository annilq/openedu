# openedu · 项目长期约定

## AI 入口与分层（ADR-0036/0037）
- 前端 AI 唯一入口：`assistantNotifierProvider` + `AssistantMessageList`；家长=悬浮球 `FloatingAssistant`，娃娃=整页 `AssistantChatPage`。不再加第二个入口。
- 后端唯一端点 `POST /api/v1/assistant/chat`（ADR-0024）；可见 SubAgent 单点 `AgentRuntime.visible_businesses(role)`。
- 业务字段不前端预填：`AssistantChatReq` 只含 message/sessionId/model/history/focusInterest；subject 后端重算、grade 取 JWT。
- 依赖单向 `main/ → features/* → shared/*`；`shared/` 不得 import `features/`。`App*` 前缀只给 shared 通用组件。守卫 `frontend/test/feature_boundaries_test.dart`（R1/R2/R3）。

## 前端分层落地约定（2026-09-15 重构后，见 docs/frontend-architecture-review.md）
- **9 个 feature 全部有 repository**：`domain/repositories/<x>_repository.dart`（接口）+ `data/repositories/<x>_repository_impl.dart`（端点 + 模型映射）+ `providers/<x>_provider.dart`（组合根）。**刻意不建 datasource**——项目已删过一个 pass-through datasource，再垫只做转发的层是重蹈覆辙。
- **组合根 = feature 级的 `features/<f>/providers/`**（与 `data|domain|presentation` 平级）。装配代码必然同时 import data（绑实现）和 presentation（建 notifier），塞进 domain 会反向依赖 presentation、塞进 presentation 会违反 R4。auth/children/practice/review/home/assistant/model_management/tutor 均已建。
- **边界守卫 5 条**（`test/feature_boundaries_test.dart`）：R1 shared 不 import features · R2 除 home 外 feature 不横向 import · R3 features 下不定义 `App*` · **R4 presentation 不 import data** · **R5 domain 不 import presentation**。R4/R5 用**棘轮**（`_knownR4`/`_knownR5` 只许变短）：名单外新违规红、名单内已修未删也红。**两条名单均已清零**，新增违规会直接红。
- `shared/presentation/resource.dart`：`ResourceNotifier<T>` 只吃 `Future<T> Function()`，**解析在 repository**（不要在 notifier 再 parse 一次，会双重解析）。
- `decodeList`/`decodeMap` 在 `shared/utils/json_decode.dart`（消费方是 data 层，放 presentation 会倒置）。
- 请求 DTO 归 domain：`assistant/domain/assistant_requests.dart`（AssistantChatReq/TaskGenerateReq）、`model_management/domain/model_requests.dart`。
- 模型归属：`shared/domain/models/models.dart` 只放多 feature 共用的（708 行）；`TutorLogModel` 归 `tutor/domain/models.dart`，`Model*` 归 `model_management/domain/models.dart`。**不要为它们做 barrel**（shared 反向 export features 违反 R1）。

## Dart 陷阱 / 沙箱
- 相对 import `..` 越过 `lib/` 根时分析器「截断」不报错 → 层数自己数准。
- ✅ **`flutter test` 能跑**（2026-09-15 订正：旧记「沙箱跑不了」是误判）。失败真因是环境 `HTTP_PROXY=http://127.0.0.1:54128`，Dart HttpClient 把 flutter_tester 的**本地 WebSocket** 也走代理 → `Unable to connect to flutter_tester process: WebSocketException: Invalid WebSocket upgrade request`。加 `no_proxy` 即可：
  `env no_proxy="127.0.0.1,localhost,::1" NO_PROXY="127.0.0.1,localhost,::1" ~/Documents/fulttersdk/flutter/bin/flutter test`
- **Flutter SDK 在 `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH，须全路径调用）**。旧记忆记的 `/Users/yunqi/Documents/flutter` 已失效（2026-09-15 实测）。
- `flutter analyze` 可用且很快（~5s）。`flutter analyze lib` 可排除 test 目录。
- 注意：`flutter analyze` 的退出码常非 0（沙箱拦 dartServer 临时文件写），**看输出里的 `No issues found!` 而非退出码**。

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
- ⚠️ **协议泄露判据不得绑定工具名**（2026-09-15 修）：`_text_looks_like_tool_call` 原为「协议标记命中 **且** 点名已注册工具」。模型把 `list_wrong_questions` 幻觉成 `get_mistakes` 时点名必然落空 → 整段 `<tool_calls><invoke name="get_mistakes">…` 落库并下发（会话 `ff07d664…`）。现拆**强/弱两档**：强标记（`<invoke name=` / `</invoke>` / `<parameter name=` / `<function_calls>` / `antml:`）**命中即判泄露、与工具名无关**；弱标记（`"name": "` 等可能与正文同形者）保留点名收紧。另新增 `_PARTIAL_TOOL_CALL_HINT`：`native_fc_seen=True`（数据卡已下发）时报「本轮未完成、上方数据已给出」，不复述「查询无法执行」。守卫 `tests/ai/test_tool_loop_bounds.py`（24→28 passed）。
- **模型侧已知事实：默认模型 `deepseek-v4-flash`（`openai_compat` / `api.deepseek.com`）在多轮 tool loop 里会把调用退化成 XML 文本**，参数含长 uuid 时尤甚（与 ADR-0040 的「strict 必填陷阱 → 空转 → 把调用叙述成文本」同源）。**对策是减跳数而非只堵输出**：`query` SOP 与 `_SYSTEM` 已改为优先用 `child_name` 一跳直达，仅昵称歧义时才取 `child_id`；`list_children` 描述同步删掉「不确定时先调本工具」的引导。
- ✅ **AI 气泡 Markdown 渲染已落地**：`gpt_markdown` → `shared/widgets/app_markdown.dart#AppMarkdown`（设计令牌映成 `GptMarkdownStyleSheet`；代码块复制按钮关闭、沿用原生整条复制；根 CupertinoApp 无 Material 祖先），接入 `assistant_message_list.dart`。落地 `349e4ec`（`pubspec` 加 `gpt_markdown`）。

## 视觉语言（ADR-0044，2026-09-15 定，代码未动）
- **新粗野**已定为新视觉语言，取代 Linear 克制风：高饱和原色撞色 + 2px 墨黑描边 + 无模糊硬阴影 + 弹性动效。层级靠描边/位移，不靠色块面积。
- **色块是强调件不是铺底**（统一到家长端上限）：填充 ≤ 卡片 40%、单屏色相 ≤ 3、列表行禁整行填充。双端**统一强度**，不设 parent/child 双色板；仅保留 ADR-0014 的 Child 字号放大一档。
- **配色硬约束（实测 AA）**：亮块只能配墨黑 `#111110`，深块（violet/red/blue）只能配白字——高饱和色配白字最高仅 4.78，过不了。相邻色块对比中位数 1.67 → 墨黑描边是功能必需，不可「简化」掉。
- 动效弃用 `Curves.easeOutBack`，改真弹簧（`SpringDescription`/`springster`）。
- 迁移顺序：token 层先行 + 试点，**禁止一次性全量重做**。
- 设计单一事实源是 `.impeccable.md`（2026-09-15 首次建立，此前缺失但代码已引用它）；术语见 `CONTEXT.md` §设计语言。

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
- **`git push` 2026-09-15 实测可通**（此前记忆记「沙箱阻断」，已不成立；成功推 `349e4ec..77cf7e1`）。仍可能随网络波动，失败时重试。
