# AI 单入口（前端）：娃娃端收敛到整页对话，删除 TutorNotifier

后端早已单入口（ADR-0024：所有 AI 能力经 `POST /api/v1/assistant/chat`），但前端并存两个 AI 入口——家长/娃娃通用的悬浮球「AI 学习助手」与娃娃端页签「问 AI 老师」——各自持有独立 notifier、独立会话线、独立渲染实现。本 ADR 把前端也收敛为单入口：**一个 provider、一份渲染、一条会话，由角色决定入口形态**。

- **单一状态源**：娃娃整页与家长浮层同读 `assistantNotifierProvider`，不再有第二套对话状态（`frontend/lib/features/assistant/presentation/screens/assistant_chat_page.dart:18`、`frontend/lib/features/assistant/presentation/widgets/floating_assistant.dart:96`）。收敛前 `AssistantNotifier` 与 `TutorNotifier` 各持一个 `_currentSessionId`，同一个娃娃在两个入口得到两条互不可见的会话。
- **单一渲染**：气泡 / 题卡（DATA 帧）/ 安全标记 / 复制按钮统一在 `AssistantMessageList`（`frontend/lib/features/assistant/presentation/widgets/assistant_message_list.dart:17`），两个形态共用。收敛前整页只渲染 `fold.text`，`fold.cards` 被静默丢弃——娃娃经该页提问「我的错题」时题卡不显示。
- **角色决定形态**：家长端挂悬浮球，娃娃端不挂（AI 只从页签进），每个角色恰好一个入口（`frontend/lib/main/app.dart:118`）。
- **娃娃端落点**：导航页签改挂 `AssistantChatPage`，导航名与页标题统一为「问 AI 老师」（`frontend/lib/features/home/presentation/screens/home_screen.dart:251`）。
- **清理死 UI**：旧页面的学科 / 年级 / 知识点三个控件不进请求体——`TutorAskReq.subject/grade/knowledgePoint` 从未被发往后端（后端 `subject` 由 `detect_subject(message)` 重算、`grade` 取 JWT 的 `caller.user.grade`、`knowledge_point` 恒 `""`；`backend/app/features/assistant/service.py:93,177,279`）。随本次删除 `tutor_notifier.dart`、`tutor_chat_screen.dart`、`tutor_message_list.dart`、`tutor_chat_input_bar.dart`、`tutor_welcome_hint.dart` 及 `TutorAskReq`。
- **`features/tutor` 的保留边界**：只留家长侧日志 `GET /tutor/logs`（`frontend/lib/features/tutor/presentation/providers/tutor_logs_notifier.dart:12`、`backend/app/features/tutor/router.py:39`）。它非 AI 生成端点，不并入 assistant 入口；「AI 答疑记录」页面据它渲染。
- **权限边界未变**：可见 SubAgent 仍由后端单点决定——`AgentRuntime.visible_businesses(role)`（`backend/agent_core/runtime.py:63`）。前端收敛不改任何鉴权/配额/安全语义。

**Considered Options**：① 保留两个入口、只修三处缺陷（渲染逻辑双写，下次改动必然再次漂移，拒绝）；② 前端收敛为单入口、按角色决定形态（采用）。

**Consequences**：新增 AI 能力（新 SubAgent）前端零改动；`cards` / 安全兜底 / 复制行为只有一处实现，不再分叉。已知代价：娃娃端的 AI 从浮层改为整页，导航标签由「AI 伴学」改为「问 AI 老师」——这是刻意的，单入口需要一个名字。遗留项已由 ADR-0037 处理：`features/tutor` 下混放的模型管理三件套（`models_notifier.dart` / `parent_model_management_screen.dart` / `model_form_dialog.dart`）已迁至 `features/model_management/`，本 ADR 的 `features/tutor` 保留边界不变（只剩 `GET /tutor/logs`）。
