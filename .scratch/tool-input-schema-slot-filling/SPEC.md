# 工具输入 schema 与缺槽追问 · Spec

> 来源：ADR-0095（本轮权威决策记录，冲突以它为准）。
> **[INDEX.md](INDEX.md)**：依赖链 + grill 决策锚点 + 共同纪律。tickets 是垂直切片。
> 本地 `.scratch`（gh 未认证，未建 GitHub issue）。每张 ticket 含 What to build / Blocked by / Status / 验收；新票统一打 `ready-for-agent` 分诊标。

## Problem Statement

当用户在 AI 会话里发起一个复杂流程任务（如「新建一个任务」「出几道题」）却没带齐必要参数（年级、学科、知识点、题型、是否多学科组卷）时，当前的 AI 不会逐项追问缺失信息。证据（见 `docs/research/slot-filling-analysis.md`）：

- 提问子代理只有一条粗粒度兜底——连学科都抽不到才提示「请告诉我科目、年级和题型」，且不区分缺哪个槽。
- 年级静默默认 0、知识点静默留空，从不作为必填槽。
- 追问后不跨轮累积，用户必须重发整条才能继续。
- 真正收集年级 / 学科 / 知识点的是前端表单驱动的 `POST /tasks/generate` 结构化路径；`ctx.extra["specs"]` 只在该路径注入，助手会话路径 100% 走自由文本分支，因此 AI 对话里完全没有 slot filling。

用户诉求：给每一个工具（subagent 业务）定义输入 schema，当用户查询缺参数时持续提醒输入，直到必填参数齐备。

## Solution

为每一个 subagent 业务在 manifest 声明 `input_schema`，作为该工具全部输入槽位的唯一事实源；并在 subagent 生成前插入一个**确定性的预检层（slot_filling）**：载入 schema → 从持久化槽位 + 本轮消息抽取 → 合并 → 校验必填 → 缺槽则产出**澄清帧**并写回已知槽位、return（不生成），齐全则进入生成并先发一条**汇总确认**再出数据帧。半成形意图跨轮保存在 `Conversation.slots`，使下一轮只需补说缺失项、无需重述整条。追问策略采用**最小阻塞**：只阻塞 `subject` + `grade`（出题业务再加 `qtype`），其余槽用默认值并在汇总里声明。

澄清帧复用普通助手消息帧（不新增事件类型），文本为各缺槽 `prompt` 拼接，`extra` 带 `clarify: {"missing_slots": [...]}`；前端据此渲染引导输入卡。

## User Stories

1. As a 学生, I want 在对话里说「出几道数学题」时系统追问我还缺什么（年级、题型）, so that 我不必自己猜该提供哪些参数。
2. As a 学生, I want 被追问后只回「三年级」就能继续, so that 我不用把整条需求重发一遍。
3. As a 学生, I want 系统在我没说年级时先问我年级（而不是直接默认 0）, so that 出的题符合我的实际年级。
4. As a 学生, I want 系统在我没说知识点时按教材随机出题（并在汇总里告诉我「知识点：未指定」）, so that 我不必为每个请求都硬凑知识点。
5. As a 学生, I want 看到一条「已确认规格」汇总（科目/年级/题型/数量/难度/知识点）, so that 我在生成前有机会修正。
6. As a 教师, I want 在对话里「布置一份练习」时系统追问学科与年级, so that 布置的任务归属到正确的班级与科目。
7. As a 教师, I want 可以选择多学科组卷, so that 一份练习覆盖多个科目而非手动分多次布置。
8. As a 教师, I want 系统识别我在自由文本里提到的多个科目并分别出题, so that 我不用逐科目发起请求。
9. As a 学生, I want 查询学情时（如「看看我的错题」）即使不指定科目系统也能回答, so that 读操作不因缺参数而卡住。
10. As a 学生, I want 答疑时把问题直接发出来系统就解答, so that 我不用先填一堆元数据。
11. As a 学生, I want 刷新页面后已填的槽位不丢, so that 多轮补全不被一次刷新打断。
12. As a 系统, I want 每个 subagent 的槽位定义集中在一处（manifest）, so that 前端渲染选项与后端校验不再各写一套、不再漂移。
13. As a 维护者, I want 必填槽的判定是确定性的（规则而非模型随机）, so that 追问行为可单测、不会漏问或乱问。
14. As a 维护者, I want 澄清帧作为普通消息落库, so that 历史回放里是正常的气泡、不会出现不可辨识的帧类型。
15. As a 前端, I want 收到 `extra.clarify` 时渲染可点选/可输入的引导卡（枚举按 `enum`/`enum_ref` 出选项）, so that 用户补参的体验是一致的结构化卡片而非裸文本。
16. As a 用户, I want 多选/枚举槽以选项卡片呈现而非让我手打, so that 我不会被要求记住合法的取值集合。
17. As a 系统, I want `enum_ref` 引用的可选项（如学科清单）解析为单一权威列表, so that 选项增减只改一处。
18. As a 学生, I want 出题时模型识别到「选择题」就把它当作题型槽填入, so that 我不必额外声明 `qtype=choice`。

## Implementation Decisions

- **承载单元**：每个 subagent 在 manifest 增加 `input_schema` 字段，作为该工具槽位定义的唯一事实源；结构化 `actions`（ADR-0081）复用所属业务的槽位，不在 action 层另写一份。manifest 仅加新键，旧代码不读它，向后兼容。
- **槽位定义字段**：`name` / `type`（`enum`|`int`|`bool`|`string`）/ `required`（是否阻塞）/ `prompt`（缺槽话术）/ `enum`（可选项）/ `enum_ref`（引用外部常量，避免重复漂移）/ `min`+`max`（int 范围）/ `default`（optional 默认值）/ `source`（`text` 自由文本抽取、`context` 透传 `ctx.extra`、`both`）。
- **预检层（确定性，非模型随机）**：在 subagent 生成前插入 `slot_filling` 步骤。原型函数形状（来自设计，编码决策比文字更精确）：

  ```
  fill_slots(schema, collected, incoming) -> {
      extracted,            # 本轮从 message + ctx.extra 抽到的槽
      merged,               # merge(collected, extracted)
      missing,              # required 且未填的槽（带 prompt/type/enum/min/max）
      clarifying,           # 有 missing 时为 True，且产出澄清帧
  }
  # 调用方：clarifying -> 写回 merged 到 Conversation.slots，return 澄清帧（不生成）
  #        否则 -> 先发汇总确认（覆盖被默认填充的 optional 槽），再进生成
  ```

- **跨轮记忆**：新增 `Conversation.slots` 列，类型 JSON（`none_as_null=True`，遵循 ADR-0061），按 business + intent 累积槽位字典；追问时写回已知槽位；规格解析完成后清空或保留至会话结束。迁移为加列、幂等 DDL（ADR-0053 纪律）。
- **追问策略（最小阻塞）**：只阻塞 `subject` + `grade`，出题业务再加 `qtype`；其余槽（`count` / `knowledge_point` / `difficulty` / `semester` / `multi` / `judge` / `multi_subject`）一律 `required=False` + 默认，只在汇总里声明。`query` / `tutor` / `guide` 不阻塞（读操作与问答过度追问反而干扰）；`capability` 无输入。
- **多学科组卷**：建模为 question 的 optional 槽 `multi_subject`；自由文本出现多科目时由既有 `_subject_summary` 自动识别并分别出规格；单科目场景不作为必问项。
- **澄清帧契约**：复用 `agent_core/protocol.py` 的 `AssistantEvent`（业务字段走 `extra`），不新增 eventType；`extra.clarify = {"missing_slots": [{"name","prompt","type","enum","min","max"}]}`。
- **不破坏现有**：结构化 `POST /tasks/generate`（注入 `specs` 那条）路径不受影响；前端仅在消息流里识别 `extra.clarify`，改动量小。
- 各工具的初版 `input_schema`（question 10 槽 / query 6 optional / tutor 4 / guide 3 optional / capability 空）已写入 5 个 manifest（落地 ticket 已完成）。

## Testing Decisions

- **什么是好测试**：只测外部行为——即「给定入参与已累积槽位，预检层返回澄清帧还是放行、澄清帧的 `missing_slots` 内容、跨轮合并后的结果」，不测内部 dict 形态细节。集成层只测助手响应是否含 `extra.clarify` 且未发非澄清 DATA 帧，不测内部调用顺序。
- **三档接缝（用户确认全要）**：
  - **① 单元层 — `slot_filling` 纯函数**：最高隔离，无 IO。对照现有 `parse_specs_from_text` 测试范式。覆盖：缺 required 槽→返回澄清帧且 `missing_slots` 正确；齐全→放行；`merge` 覆盖语义；默认填充；`enum_ref` 解析；多业务载入各自 schema。
  - **② 集成层 — `assistant/service` 预检接线**：对照 `tests/api/routes/test_assistant*.py` 与 `tests/ai/test_subagents_seam.py`。覆盖：缺 `subject`/`grade` 时助手响应含 `extra.clarify` 且无非澄清生成；下一轮只补 `grade` 则合并后继续生成；汇总帧覆盖被默认填充项；`query`/`tutor` 不阻塞。
  - **③ 前端层 — `extra.clarify` 渲染**：对照现有 widget 测试（几何断言，**禁截图装置**）。覆盖：收到 `clarify` 渲染缺槽引导卡、枚举按 `enum`/`enum_ref` 出选项、点选/输入回填、汇总帧展示默认项。
- **持久化接缝（并入 ②）**：`Conversation.slots` 迁移后断言列存在、读写往返、`none_as_null`、空 slots 不污染、迁移幂等（对照 `tests/core/test_*_migration.py`）。

## Out of Scope

- 不引入 LLM 强制抽取（`request_clarification` 工具调用）——灵活但非确定，已否决。
- 不新增 CLARIFY 事件类型——前端改动大，用户选「普通消息 + 标记」，否决。
- 不做全槽阻塞（每个必填槽都追问）——打扰多，否决，改最小阻塞。
- 不改动结构化 `POST /tasks/generate` 路径（其 `specs` 收集由前端表单负责，与对话 AI 路径隔离）。
- 不引入跨会话的 `draft_intent` 落库表——跨轮记忆用 `Conversation.slots` 列即可，不另建重表。

## Further Notes

- 设计权威记录见 `docs/adr/0095-tool-input-schema-slot-filling.md`；术语见 `docs/glossary.md`（槽位 / 输入 schema / 必填槽 / 澄清帧 / 槽位记忆 / 预检层 / 最小阻塞 / 多轮澄清 / enum_ref / 汇总确认 / 多学科组卷）。
- 主流 slot-filling 实现对比（OpenAI/Anthropic 工具 schema、LangChain Pydantic、Rasa Forms、Dialogflow CX、LangGraph interrupt、ReAct）见 `docs/research/slot-filling-mainstream.md`；本设计落在「Schema 契约式 + 确定性预检 + 跨轮状态」组合上。
- 编号：本 ADR 原拟 0094，因并行会话已在每日日志取号 0094（genkit 主题）而改 0095，manifest 注释同步。
- 票型：`to-spec` 初版为分层票（引擎/持久化/接线/前端），经 `to-tickets` 重切为垂直 tracer bullet（T1 后端垂直 / T2 前端垂直 / T3 拓宽），见 `INDEX.md` 依赖链与 `issues/01-03`。每票跨层、可独立演示。
