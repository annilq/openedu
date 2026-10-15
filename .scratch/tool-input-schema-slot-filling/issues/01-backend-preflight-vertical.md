# 01: 后端垂直切片 — 出题业务缺槽追问端到端闭环

**What to build:** 在助手聊天里，当用户发起出题（"出几道数学题"）却缺必填槽（subject / grade / qtype）时，系统只追问缺失项、用结构化澄清消息返回；跨轮记住已收集槽位（已填槽不丢，用户只补说仍缺的项——如回「三年级」后只再问 qtype）；必填齐备后先发一条汇总确认、再出題。整条链路（schema→引擎→持久化→API 接线→后端测试）在本票内一次打通，无需前端即可经集成测试演示。

**Blocked by:** 00（schema 落地，已完成，无门禁）

**Status:** done（已合入 `integration/tool-input-schema-slot-filling`）

> 实现补丁（合入时补记）：预检齐备后必须把 merged 槽位写入 `ctx.extra["specs"]`，
> 否则生成步会回落自由文本兜底、丢失已收集的科目/年级/题型；另修正 int 抽取把年级
> 当成数量的问题（`count` 与 `grade` 现按槽名分派）。

- [ ] `slot_filling` 引擎（纯函数、无 IO）：载入 business 的 `input_schema` 并解析 `enum_ref`；从「已持久化槽位 + 本轮消息 + ctx.extra」抽取；`merge`；校验 `required`；构造澄清帧。原型形状（来自设计，编码决策比文字精确）：
  ```
  fill_slots(schema, collected, incoming) -> {
      extracted,            # 本轮抽到的槽
      merged,               # merge(collected, extracted)
      missing,              # required 且未填（带 prompt/type/enum/min/max）
      clarifying,           # 有 missing 时为 True，产出澄清帧
  }
  # clarifying -> 调用方写回 merged 到 Conversation.slots 并 return 澄清帧（不生成）
  # 否则 -> 先发汇总确认（覆盖默认填充的 optional 槽），再进生成
  ```
- [ ] 缺 `required` 槽 → 返回 `clarifying=True` 且 `missing_slots` 含正确 name/prompt/type/enum/min/max；齐备 → `clarifying=False` 含默认填充项；`merge` 覆盖语义正确；`enum_ref` 解析为 `SUBJECTS`；多 business 载入各自 schema 互不串；空消息不抛异常、不产生伪澄清。
- [ ] `Conversation.slots` 持久化：新增 JSON 列（`none_as_null=True`）+ 幂等迁移 + 读写 helper；读写往返一致（int/enum/bool/string）；空 slots → NULL 不污染；迁移重复执行幂等。
- [ ] `assistant/service` 预检接线（question 先接）：`subagent.run` 前调 `fill_slots`；`clarifying` → 写回 `merged`、return 澄清帧（不出題）；下一轮只补 `grade` → 合并后继续生成；齐备 → 先发汇总帧再生成。澄清帧为普通消息落库（复用 `AssistantEvent`，`extra.clarify` 承载，不新增 eventType）。
- [ ] 集成测试（对照 `tests/api/routes/test_assistant*.py` / `tests/ai/test_subagents_seam.py`）：缺 subject/grade 时响应含 `extra.clarify` 且无非澄清 DATA；跨轮合并续接；结构化 `POST /tasks/generate` 路径行为不变（回归）。

## 纪律 / 实施提示
- 新增 JSON 列须 `JSON(none_as_null=True)`（ADR-0061）；迁移加列、幂等 DDL（ADR-0053）；对照 `tests/core/test_*_migration.py`。
- 引擎复用既有 `parse_specs_from_text` 做文本抽取（对照 `tests/ai/test_generate_question.py`）；纯函数、无 DB/网络 IO。
- 预检确定性（不引入 LLM 调用）；不破坏结构化 `POST /tasks/generate` 路径。
- 唯一事实源 = 各 manifest 的 `input_schema`；`enum_ref` 指向 `app.domain.subjects.SUBJECTS`（ADR-0055 §11）。
