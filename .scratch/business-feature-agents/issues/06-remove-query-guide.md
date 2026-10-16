# 06 · 删 query/guide + capability 清单生成

## What to build

- 删 `app/ai/subagents/query/`（agent.py / render.py / tools/ 全部）与 `app/ai/subagents/guide/`。
- `capability/agent.py`：`capability_catalog(role)` 改为从 `runtime.manifests` 生成（manifest 发现后构造 AgentRuntime 传入，或 capability agent 构造时接收 manifests 引用——后者避免循环依赖，具体实现按装配点定）；按 role 过滤可见 business，取 `name` + `description` + 工具名列表；边界文案重写：「我可以帮你起草任务与题目；发布前会请你确认」。
- `service.py` 等对 query/guide 的引用清理（routing extra、kind 展示名等）。

## Blocked by

03、04、05（三域就位）。

## 验收

- `AgentRuntime.discover()` 的 manifests 恰好 5 个：tasks / questions / students / capability / tutor。
- capability 清单内容 = 新拓扑的真实能力（无 query/guide 残留字样）。
- 契约测试：动作归属表不变；纯文本回归表按新优先级重写（「任务题目」→ questions、「创建任务」→ tasks、「我有哪些任务」→ tasks、「你能做什么」→ capability、兜底 → tutor）。
- query 的工具单测全部迁址或重写；无 import query 的残留。
