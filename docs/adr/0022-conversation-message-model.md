# Conversation / Message 数据模型：多轮会话与 Agent 运行轨迹

多轮 AI 会话以 `Conversation` + `Message` 两张表建模：一次 AI Agent 运行（出题/答疑/批改…）对应一个 `Conversation`，其内部每步（输入/检索/推理/生成/工具/输出）对应一条 `Message`，安全标记挂在 `Message` 上，便于事后审计被拦截步骤。

- **运行容器**：`Conversation` 是一次 AI Agent 运行的容器，含 `kind`（运行类型）、`parent_id`/`child_id` 归属、`model` 模型引用、`ref_task_id` 追溯到题、`status`（`backend/app/db/models/conversation.py:11`、`:21`、`:26`）。
- **带 role+step 的一步**：`Message` 是 Conversation 内带 `role`（system/user/assistant/tool）与 `step`（input/retrieval/reasoning/generation/tool_call/output/error）的一步，记录运行轨迹（`backend/app/db/models/conversation.py:39`、`:51`、`:52`）。
- **安全标记挂 Message**：`input_safe` / `output_safe` / `blocked` / `block_reason` 直接落在 Message 行，ADR-008 安全闸门的结果可定位到具体被拦步骤（`backend/app/db/models/conversation.py:56-59`）。
- **会话持久化复用**：悬浮助手端点复用 `Conversation` / `Message` 做会话持久化，ADR-0022 升级为助手会话（supersede 旧设计）（`backend/app/features/assistant/router.py:9`）。
- **规避命名冲突**：通用响应体原本叫 `Message`，为避免与调试库 `conversation/message` 的 `Message` 表冲突，改名为 `StatusMessage`（`backend/app/features/auth/schemas.py:49`、`:50`）。

**Considered Options**：① 每个业务各建独立会话表（重复、审计难，拒绝）；② 统一 `Conversation`+`Message` 以 step 维度记录轨迹、安全标记挂行（采用）。

**Consequences**：所有 AI 运行可回放与审计；安全拦截可精确到单步；`Message` 命名占用后，其它通用响应体须避开 `Message` 名（如 `StatusMessage`）。
