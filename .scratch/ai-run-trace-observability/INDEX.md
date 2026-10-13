# AI 运行轨迹可观测 UI 与管理员（admin）· Tickets 索引

> 来源 spec：`.scratch/ai-run-trace-observability/SPEC.md`（GitHub issue 正文源）。
> 决策依据：[ADR-0088 AI 运行轨迹可观测与管理员](../adr/0088-ai-run-trace-observability-and-admin.md)。
> 发布形式：本地 `.scratch` 文件（未建 GitHub issue；`gh` 未登录）。后续 `gh auth login` 后可一键转 issue 并打 `ready-for-agent`。
> 术语以 `CONTEXT.md` 为准；每个 ticket 文件含 `What to build` / `Blocked by` / `Status: ready-for-agent` / 验收清单。
> ⚠️ **全部 5 票（00–04）本轮已 done**：ADR-0088 实施闭环。

## Tickets（依赖序，blockers first）

| ID | 标题 | Blocked by | Status |
|----|------|-----------|--------|
| 00 | 账户角色枚举化与 admin 落地（Role + require_admin + require_owned_or_admin + debug 端点 admin 接线 + env 种子） | — | ✅ done |
| 01 | `Message` 步级 usage/latency/model/safety 落库 | — | ✅ done |
| 02 | 前端独立「运行轨迹」页（镜像双消费者：全步骤 + token/延迟，与历史会话分离） | 01 | ✅ done |
| 03 | 内容默认脱敏 + 破窗访问留痕（admin 看全部时 PII 脱敏，全文走 break-glass 并记日志） | 00, 02 | ✅ done |
| 04 | 端到端回归与文档收口（关闭 ADR-0088 §7 三个开放问题） | 01, 02, 03 | ✅ done |

> 并行分析：00 ‖ 01 文件集不相交（00=角色/auth/guard/debug 端点，01=assistant 落库），可并行；02 依赖 01（token/延迟列必须有值才展示）；03 依赖 02（脱敏与破窗作用在轨迹页渲染与端点）；04 收口待 01/02/03。

## 决策锚点（写进每张 ticket）

- **角色枚举与调用面分离**：`Role(student/teacher/admin)` 只在 `app` 层；`agent_core` 只认 `teacher/student` 两种 surface，靠 `_surface_of` 在 assistant 编排边界折算（admin 复用 teacher 面），绝不污染分层不变量。
- **DB 列保持 `VARCHAR(16)`**：不用原生枚举迁移；历史字符串与枚举双向 coerce；`admin` 是新值。
- **双消费者，不混入口**：历史会话投影「气泡」、运行轨迹投影「全步骤 + 元数据」，同一张 `Conversation`/`Message` 表、两种口径、同一套归属校验；不得再派生第三套步骤→气泡逻辑。
- **usage 走步级原语**：填既有 `Message` 列（`usage/latency_ms/model/safety`），零 schema 改动；步级可 `GROUP BY` 上推会话级总成本。
- **脱敏 + 破窗红线**：默认看不到学生 PII 原文；看全文走 break-glass 并留痕；admin 口令从环境变量读、绝不写死。
- **导航单源 + 禁 Material**：运行轨迹页扩展既有导航密封类，`flutter analyze` 真构建。

## 最容易回归的断言（实施时不可省）

- **00**：`pytest` 全绿（791 passed 基线已含）；`require_admin`/`require_owned_or_admin` 断言 admin 看全部、教师只看自家、学生被拒；`agent_core` 无 `Role` import（`test_layering_invariants`）。
- **01**：落库后抽样 `Message` 行，`usage`/`latency_ms`/`model` 非空（至少 generation/tool 步）；`GROUP BY conversation_id` 能得会话总成本。
- **02**：轨迹页渲染全步骤（routing/tool_call/tool_result）+ token/延迟；不进历史气泡；入口与历史页分离；导航单源测试无并行状态。
- **03**：默认 PII 脱敏可见；破窗后原文可见且访问被记录；未授权全文访问被拒。
- **04**：`flutter analyze` 零错误 + `flutter test` 零回归；ADR-0088 §7 三个开放问题关闭（或显式记入 Backlog）。

## 测试缝

- **后端角色边界缝（00）**：`require_admin` / `require_owned_or_admin` / `_surface_of` 返回值。
- **后端 usage 落库缝（01）**：落库路径断言每步 `Message` 的 `model`/`usage`/`latency_ms`/`safety` 非空。
- **后端 debug 端点 admin 口径缝（00/03）**：`GET /ai/debug/conversations` 对 admin 返回全部、对教师只返回自家；详情越权 403。
- **前端运行轨迹页缝（02，最高位输出侧）**：喂多步会话，断言全步骤 + token/延迟渲染、不进气泡、入口分离、导航单源。
- **破窗留痕缝（03）**：默认脱敏、破窗后原文可见且留痕、未授权被拒。

## 转 GitHub issue 步骤（待登录）

1. `gh auth login`
2. 按编号 00→04 顺序建 issue，`Blocked by` 指向 blocking issue 编号（00 已 done，可标 closed 或并入集成分支）
3. 全部打 `ready-for-agent` 标签（00 标 `done`/closed）

建 issue 命令模板：
`gh issue create --title "T0N — <标题>" --body-file .scratch/ai-run-trace-observability/issues/0N-<slug>.md --label ready-for-agent`

## Backlog（延后待办，不在本轮 5 票内）

- 独立 OTel / Langfuse 后端 trace 体系（规模化后再叠）。
- durable execution（Temporal/Restate/Inngest）长程任务持久化。
- admin 跨教师看 `tutor_logs` 伴学安全审计（ADR-0088 §7 待定，可能单列）。
- 会话级 usage 汇总列（步级可上推，暂不建）。
- `Message` 原生枚举迁移（保持 `VARCHAR(16)`）。
