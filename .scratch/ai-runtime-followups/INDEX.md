# AI 运行时四项跟进：容器化决策模型 / 动作出口 / 批量出题 / 无据重路由

> 来源对话：2026-10-21 用户「按照 4 个提案优化」（提案出自此前的 why 追溯：四条里三条是
> 刻意取舍、一条是历史惯性；本次按其**收益面**重排后落地前四项）。
> 术语以 `CONTEXT.md` 为准。

一句话：**把「路由与出题的等待」和「路由判错后的僵住」这两类用户可感缺陷各修一处，
并把本地已验证的决策服务推进容器化。**

## Tickets

| ID | 标题 | Blocked by | Status |
|----|------|-----------|--------|
| 01 | [容器化部署补上 `OLLAYA_URL`](issues/01-ollaya-container-deploy.md) | — | done（2026-10-21，真机冷卷验证） |
| 02 | [动作直配做成会话内显式切换出口](issues/02-action-chip-switch.md) | — | done（2026-10-21） |
| 03 | [同规格出题合并为一次请求](issues/03-batch-question-generation.md) | — | done（2026-10-21，ADR-0108） |
| 04 | [无据正文改为换业务重来一次](issues/04-unverified-reroute.md) | 03 | done（2026-10-21，ADR-0109） |

04 写在 03 之后仅因两者都改 `tasks` 的 `generate_questions`，合并会让一张票跨两个决策；
04 对 03 无功能依赖。

## 关联 ADR

- `docs/adr/0108-batch-question-generation.md`（03）
- `docs/adr/0109-unverified-answer-reroute.md`（04，修订 ADR-0033 末闸的**兑现方式**）

## 未落地的两项（记录，避免重复讨论）

- **沿用 `Conversation.kind` 跳过续轮路由**：两个实测反证——① 极简二分类检测器不比全量分类
  便宜（p50 1052 ms vs 928 ms，延迟由往返 + 模型调度主导，不是输出 token）；② 库里 7 对相邻
  轮次中有 2 对业务确实变了。且撞 ADR-0104「每轮保持所有消息上下文」。结论：生产要的是
  **给容器装 ollaya**（01 做完后续轮 23 ms），而不是省掉那次判定。
- **去掉 subagent、一次调用做分类 + 执行**：已调研否决，见
  `docs/research/merge-routing-into-execution.md`（`GenkitProvider.stream` 的 `schema`/`tools`
  分支互斥 + ADR-0033 的 `requires_tool_data` 要求 ≥2 轮 + 出题主流式逐题）。
