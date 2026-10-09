# AI 提示词与助手闭环加固（ai-prompts-hardening）· Tickets 索引

> 来源：`@skill:grill-with-docs` 对现有 AI 系统提示词的盘点（11 处提示词 + suggested_actions + pending_quiz 闭环）。
> 本地 `.scratch` 文件（未建 GitHub issue）。每张 ticket 含 `What to build` / `Blocked by` / `Status` / 验收清单。
> 决策由 grill-with-docs 流程先追问后落地（Round 1–2 已与用户对齐）。

## 背景（一句话）
现有助手把三件事混在一起且各缺一角：**（a）** 无课件上下文时「知识点」恒为空、`knowledge_point_id` 下发了但 tutor/query 都不读（ADR-0072 §2 未落地）；**（b）** 超范围提问没有能力自述，且 `query.requires_tool_data=True` 会把「你能查什么」类元问题硬失败；**（c）** recommended actions 只在空态出现、发出首条消息即消失，且 `pending_quiz` 写入后会把整段会话锁死在判断题里。

## Tickets 状态（共 3 票，执行序 B → A → C）

```
01 [B] 能力自述与超范围引导（capability 意图 + 服务端固定目录） ── None
02 [A] 知识点聚焦注入会话系统提示（knowledge_point_id → ctx.extra） ── None
03 [C] 回复后 follow-up chips + pending_quiz 锁死修复 ── 01
```

**执行顺序 B → A → C 的理由（用户拍板）**：B 纯常量/提示词、可后端单测、用户立刻可感知；A 次之；C 最重（动 SSE 帧契约 + 前端渲染 + 判定分支准入）。

## 相关 ADR
- **0079** 能力自述与超范围引导（capability 意图 + 服务端固定目录）→ 票 01
- **0080** 知识点聚焦注入会话系统提示 → 票 02
- follow-up 帧与 `pending_quiz` 修复**不另开 ADR**，并入 **ADR-0072 的修订**（其 §2/§3/§已知遗留）→ 票 03

## 硬约束（三票共同遵守）
- 分层不变量 9：归属判定只走 `core.guard`（`require_owned`），禁内联比较；改 `features/*/service.py` 必跑 `tests/ai/`。
- 提示词资产：`tutor_system_prompt`（`domain/safety.py`）是**安全锁**，按 grade/subject，**不得混入业务焦点**（知识点聚焦走独立注入段）。
- 路由优先级即功能（ADR-0054）：新增意图必须显式给 `priority`，且 `triggers` 收「动作+对象」完整短语、谨慎用泛词。
- 推荐操作一律**服务端固定目录、非 LLM**（ADR-0072）；`SuggestedAction.kind` 受控枚举 `prompt|navigate`。
- 前端零 Material 控件；可点区 `AppFocusableAction`；文件规模棘轮 ≤400 行（ADR-0058）。
