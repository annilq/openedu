# 娃娃端意图强制收敛到伴学 + 多轮会话持久化复用

儿童角色经 ADR-0024 端点接入时，其意图被强制收敛到「伴学答疑」，出题 / 查任务等意图重定向到 tutor，且支持带 `session_id` 多轮复用历史上下文。ADR-0033 随后放宽：娃娃端可**可见**学情查询，但工具侧恒查自己、去答案（不破坏本 ADR 的收敛底线）。

- **意图收敛由路由决策层强制**：儿童问「出几道数学题」决策被改写为 `tutor`（伴学答疑），而非 question（`backend/tests/ai/test_agent_runtime.py:78-81`）；端点单测验证娃娃端路由 THINKING 帧标 `routing:True` 且 `伴学答疑`，且不出 `question` 题卡（`:110-126`）。
- **会话持久化复用（repository）**：`get_conversation_by_id` 按主键取回会话、`load_chat_history` 取 `user/assistant` 的 `input/output` 轮次（最近 20 条）拼入 prompt（`backend/app/features/assistant/repository.py:15-44`）。
- **端点会话续接逻辑**：带 `session_id` 时校验归属（parent_id/child_id 一致）后载入历史并续写 `Message`；否则新建 `Conversation`，kind 由决策显式写入（`backend/app/features/assistant/service.py:89-131`）。
- **ADR-0033 放宽但不越界**：娃娃端 `query` 可见（`:84-88`），但工具恒查自己、帧与 TOOL_RESULT 皆去 `answer/explanation`，且不落 TutorLog（伴学才记）（`backend/tests/api/routes/test_assistant.py:205-234`）。

**Consequences**：儿童产品硬性隔离——非伴学生成在组织上不可达；多轮上下文由后端会话表托管，前端只需持有 `session_id`。收敛规则随路由决策单测守护，放宽仅限 query 且带去答案约束。
