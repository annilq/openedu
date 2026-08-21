# T12 · Flutter AI 伴学模块收尾（故事 18/20/21/22/23/26 / AC-307）

> 范围来源：ticket `.scratch/wawa-learning/issues/12-flutter-ai-tutor.md`。核心功能主体已由 **T08**（答疑 + 内容安全 + 家长日志）与 **T10**（时长/次数/内容范围管控）落地，本票为 Flutter 侧**收尾补齐**。

## 验收（来自 ticket）
- [x] 娃娃可提问并获得适龄讲解展示（故事 18）→ T08 `tutor_chat_screen` + `TutorNotifier.ask`（POST /tutor/ask）
- [x] 被拦截的不安全内容对娃娃显示家长提示而非原文（故事 20/21）→ T08 后端 `SAFE_REFUSAL` + 前端「（已启用内容安全保护）」标注；原文永不渲染
- [x] 受每日 AI 时长与内容范围约束（故事 23/26）→ T10 后端 `check_quota` 强制（越界 403/超额 429）+ 前端透出文案气泡
- [x] 家长可在 App 查看 AI 交互日志（故事 22）→ T08/T07 `parent_dashboard` AI 答疑日志区块（GET /tutor/logs）
- [x] notifier 状态机（Idle/Loading/Success/Error）有 mocktail 单测 → 本票补齐

## 本票改动
- **状态机补齐** `tutor_notifier.dart`：`TutorState` 由 Initial/Loaded 两态扩展为 **Idle(TutorInitial) → Loading(TutorLoading) → Loaded(TutorLoaded)**；`ask()` 提交即入 Loading（娃娃气泡即时上屏），回复后入 Loaded。
- **对话场景的错误处理**：错误不销毁对话，以**提示气泡**保留在消息列表（AppException 透出 429/403 文案，网络异常提示重试）——这是 Error 态在对话 UI 的适配变体，语义在 `TutorLoaded` 内表达。
- **答疑页适配** `tutor_chat_screen.dart`：switch 增加 `TutorLoading` 分支，与 Loaded 共用 `_messageList` 渲染，Loading 时末尾追加「AI 老师正在思考…」占位气泡。
- **mocktail 单测** `test/tutor_notifier_test.dart`：新增 `MockNetworkService`，覆盖 Idle→Loading→Loaded 状态迁移（Completer 悬挂断言中间态）、AppException 文案透出、Loading 期间防重入仅一次请求；并为 Logs/Quota/Usage 三个 notifier 补四态（Initial→Loading→Loaded/Error）迁移测试。
- **顺带修复**：`flutter create .` 生成的 `test/widget_test.dart`（引用不存在的 counter 模板）替换为真实根组件 `MyApp` 冒烟测试；`pubspec.yaml` 补 `flutter_lints`（analysis_options.yaml 引用却未安装）；清理 2 个新启用的 lint（dangling doc comment、多余字符串插值花括号）。

## 测试
- 前端：`flutter analyze` 0 问题；`flutter test` **26 passed**（含 8 条 mocktail 状态机用例 + 1 条根组件冒烟）。
- 后端无改动（T10 已 91 passed + 1 skipped）。

## 提交
见 `git log`（feat(frontend): T12 Flutter AI 伴学收尾 ...）。
