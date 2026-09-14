# 悬浮助手统一 SSE 端点

所有 AI 能力经单一 HTTP 入口对外暴露：家长出题 / 伴学答疑 / 学情查询共用 `POST /api/v1/assistant/chat`，旧端点（`/ai/tutor/ask`、`/ai/tasks/generate`、`/tutor/ask`）已收敛到此（`backend/docs/agents/architecture.md:87` 注记废弃）。本 ADR 只定义「端点本身」，与事件帧契约（ADR-0025）、儿童意图收敛（ADR-0026）解耦。

- **单一入口路由**：`router.py` 仅挂 `POST /chat`（前缀 `/assistant`，全局 `/api/v1`），不按业务拆端点（`backend/app/features/assistant/router.py:26,29`）。
- **router 仅做 HTTP 适配**：空消息校验 + 包 `StreamingResponse`，外加 `X-Accel-Buffering: no` 禁代理缓冲以保证流式即时到达，不含任何 ORM / 路由逻辑（`backend/app/features/assistant/router.py:36-43`）。
- **编排收口于 service**：`assistant_service.chat` 持有角色解析、RuntimeDeps 构造、会话 upsert、事件流折叠持久化，router 只 `await` 其异步迭代器（`backend/app/features/assistant/service.py:42,150-220`）。
- **统一运行时驱动**：`rt.run` 返回 `AsyncIterator[AssistantEvent]`，逐帧 `ev.to_sse()` 下推，编排细节对 HTTP 层透明（`backend/app/features/assistant/service.py:159,220`）。
- **多端通用证据**：家长一句话出题 → question subagent，DATA 帧携带题卡（`backend/tests/api/routes/test_assistant.py:96-107`）；儿童伴学答疑落 TutorLog（`backend/tests/api/routes/test_assistant.py:65-81`）。

**Consequences**：前端只需对接一个 SSE 端点，新增 AI 能力（新 SubAgent）零端点改动；HTTP 关注点（鉴权、缓冲头、空校验）集中在 `router.py`，易审计；编排与协议升级互不影响（ADR-0025/0026）。
