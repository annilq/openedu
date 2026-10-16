# 业务 agent 化 · INDEX

> SPEC：[SPEC.md](SPEC.md)。ADR：`docs/adr/0097-business-feature-agents.md`（权威决策）。
> 分支：`integration/business-feature-agents`（自 main 拉出）。

## 共同纪律

- 分层不变量：归属只许 `core.guard`；`agent_core` 零业务依赖（shared 层放 `app/ai/shared/`，不进内核）。
- 前端禁 Material 控件（`InkWell/Icons/Scaffold/ListTile/Divider/Tooltip`），可点区 `AppFocusableAction`，输入 `CupertinoTextField`；新文件 ≤400 行。
- 后端测试必带 `--basetemp=/tmp/<新目录>`；跑 pytest 前 `mv .env .env.hidden`、跑完还原。
- 每票一个逻辑提交批次；测试随票走，不留「最后一起补」。

## 依赖链

```
01 agent_core 流式 tool 扩展
02 shared 层迁移（query/_shared → app/ai/shared）
        ┌──────────┴──────────┐
03 questions agent      04 tasks agent      05 students agent
        └──────────┬──────────┘
06 删 query/guide + capability 清单生成
07 前端草稿确认卡 + 卡片渲染
08 测试与全量回归（贯穿）
```

##  Tickets

| # | 票 | Blocked by | 状态 |
| --- | --- | --- | --- |
| 01 | [agent_core 流式 tool 扩展](issues/01-agent-core-stream-tool.md) | — | ready |
| 02 | [shared 层迁移](issues/02-shared-layer.md) | 01 | ready |
| 03 | [questions agent](issues/03-questions-agent.md) | 01, 02 | ready |
| 04 | [tasks agent](issues/04-tasks-agent.md) | 02 | ready |
| 05 | [students agent](issues/05-students-agent.md) | 02 | ready |
| 06 | [删 query/guide + capability 生成](issues/06-remove-query-guide.md) | 03, 04, 05 | ready |
| 07 | [前端草稿确认卡](issues/07-draft-confirm-card.md) | 04 | ready |
| 08 | [测试与全量回归](issues/08-tests-regression.md) | 01–07 | ready |

## 关键锚点（grill 决策）

1. 粒度：**按助手能力域粗切 4 个**（tasks / questions / students + capability/tutor 保留），不按 features 一级目录细切——聚合问题（错题+掌握度）无处路由。
2. 出题与题库：**合并为一个 agent，出题降级成 tool**（用户拍板，覆盖顾问「分开」建议）；代价用 agent_core 流式 tool 扩展兜住（SPEC §2.2）。
3. 写确认：**AI 起草 + 会话内确认卡**，确认按钮直走 REST confirm/assign，不新造 AI 确认机制。

## 实测基线（合并后主仓）

后端 954 passed / 1 既有红（`test_empty_text_422`）；前端 687 passed / 1 既有红
（`file_size_guard`: `home_screen.dart` 672>665）。query 8 工具 schema 合计 3934 字符
≈ 2000 token/轮——重组后按域付费，各域实测数在 08 票更新。
