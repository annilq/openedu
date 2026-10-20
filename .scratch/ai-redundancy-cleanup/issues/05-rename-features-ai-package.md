# T05 — 重命名 `app/features/ai` → `app/features/agent_debug`（候选 4，内核 `app/ai` 不动）

**What to build:** 两个包都叫 `ai` 且语义不同、互相无关：内核 `app/ai/`（~55 处 `from app.ai` 引用，承载 subagents / tools / 与 `AgentRuntime` 的集成）与 REST 层 `app/features/ai/`（仅 6 处引用：`app/api/main.py:3` 挂载 + 包内 5 处自引；含 `masking.py`/`repository.py`/`schemas.py`/`router.py`，服务 `/ai/debug/*` 运行轨迹与脱敏，ADR-0088）。重命名**较小的 REST 包**为 `app/features/agent_debug`，消除撞名；内核 `app/ai` 引用面大（55 处）**绝不改动**。URL 前缀 `/ai/debug` 由 `router.py` 的 `APIRouter(prefix="/ai")` 固定，与包名无关，故 API 契约不变。

**Blocked by:** 无
**Status:** ready-for-agent

## 决策锚点

- **只动小包**：`app/features/ai` 仅 6 处引用，爆炸半径可控；内核 `app/ai` 55 处，重命名是独立大重构，不在本票。
- 新名 `agent_debug` 直述其职（agent 运行轨迹调试 + 破窗审计），也可选 `ai_debug`——以「不丢失 `/ai/debug` URL 语义」为约束，名字本身由执行者从二者择一并在 PR 注明。
- 这是**纯重命名、零行为变化**：不改 `router.py` 的 `prefix="/ai"`，不改任何函数/签名，只动 import 路径与目录名。
- 必须在隔离 worktree 执行（项目纪律），跑完全量 `pytest` 后再合。

## 验收

- [ ] 目录 `app/features/ai/` 重命名为 `app/features/agent_debug/`，包内 `from app.features.ai...` 全部改为 `from app.features.agent_debug...`
- [ ] `app/api/main.py:3` 的挂载 import 同步改为 `app.features.agent_debug.router`
- [ ] 全仓 `grep -rn "app.features.ai"` 归零；`grep -rn "app.features.agent_debug"` 命中 6 处（main.py + 包内 5）
- [ ] `GET /ai/debug/conversations` 等端点仍 200（契约不变）；`curl` 或现有 api 测试验证
- [ ] 全量后端 `pytest` 绿；`ruff` 改动文件净
