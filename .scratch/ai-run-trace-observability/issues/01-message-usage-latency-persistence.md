# Ticket 01 — `Message` 步级 usage/latency/model/safety 落库

- **What to build**: 在 AI 运行的落库路径，把每一步的 `model`（已有列）、`usage`（token 字典：prompt/completion/total）、`latency_ms`（本步耗时）、`input_safe` / `output_safe` / `blocked` / `block_reason` 写入 `Message`。`Message` 表已有这些列，只差落库时赋值，**零 schema 改动**。重点覆盖 generation（模型调用）步与 tool（工具调用）步——这两类是最该被成本/延迟/安全观测覆盖的。会话级总成本可由步级 `GROUP BY conversation_id` 上推，不额外建汇总列。
- **Blocked by**: —
- **Status**: ready-for-agent
- **验收清单**:
  - 落库后抽样 `Message` 行：generation 步与 tool 步的 `usage` / `latency_ms` / `model` 非空（至少这两个步）。
  - `input_safe` / `output_safe`（伴学/学生面）按实际安全判定写入；`blocked` / `block_reason` 在拦截步写入。
  - 不改 `Message` / `Conversation` 模型结构（保持 `VARCHAR(16)` 等既有列），无迁移。
  - 步级能聚合成会话级总成本（不依赖会话级汇总列）。
  - 既有落库测试（边流边记、收尾刷 `conversation.status`/`updated_at`、学生面 `TutorLog`）行为不变；`pytest` 0 回归。

## 决策锚点

- **步级原语，不建会话级汇总列**：步级填既有列即可，且能上推会话总成本；会话级汇总要改模型 + 迁移，且丢失「哪一步最费 token」的排障粒度（见 SPEC §Implementation Decisions）。
- **只填既有列**：`usage/latency_ms/model/safety` 在 `Message` 模型里已声明，本票只补赋值，不扩 schema。
- **usage 形状**：token 字典（prompt/completion/total），与 `MessageResp` 既有 `usage` 字段契约一致，前端可直接消费。
