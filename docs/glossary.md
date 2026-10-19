# 术语表

本表定义 AI 助手缺槽追问设计（ADR-0094）中的术语。术语按字母序排列，中文为主、英文为辅。

## 槽位（slot）

一个工具（subagent 业务）需要的单个输入参数，例如 `subject`、`grade`、`knowledge_point`。槽位在 manifest 的 `input_schema` 中声明。

## 输入 schema（input schema）

某工具全部槽位的定义集合。每条定义包含 `type`、`required`、`prompt`、`enum` / `enum_ref`、`min` / `max`、`default`、`source`。manifest 的 `input_schema` 是槽位定义的唯一事实源。

## 必填槽（required slot）

`required=True` 的槽。缺失时阻塞生成并追问。本设计只把 `subject` + `grade`（出题再加 `qtype`）设为必填。

## 可选槽（optional slot）

`required=False` 的槽。缺失时取 `default` 值，不追问，只在生成前的汇总里声明被默认填充的项。

## 缺槽（missing slot）

当前应为必填但尚未填值的槽。预检层据此产出澄清帧。

## 澄清帧（clarification frame）

缺槽时发给用户的引导消息。复用普通助手消息帧，文本是一句「还差什么 + 怎么一次说清」（`slot_clarify.clarify_sentence`，见 ADR-0100），`extra` 带 `clarify: {"missing_slots": [...]}`。不新增事件类型。**不做选项表单**：补槽应一次往返，不该拆成逐项点选。

## 槽位记忆 / 槽位持久化（slot memory）

把已填槽位跨轮保存在 `Conversation.slots`，使追问只问缺失项、下一轮合并续接，用户无需重述整条。

## 预检层（preflight / slot_filling layer）

在 subagent 生成前校验并补全槽位的逻辑层。负责载入 schema、抽取、合并、校验、产出澄清帧。

## 最小阻塞（minimal blocking）

只阻塞 `subject` + `grade`（出题加 `qtype`）的追问策略。其余槽用默认值，避免打扰。

## 多轮澄清（multi-turn clarification）

用户分多次补全槽位的循环：每轮只补缺失项，预检层合并后继续，直到必填槽齐备。

## enum_ref

schema 中引用外部常量的键（例如 `question.SUBJECTS`），用来避免可选项在多处重复与漂移。`slot_filling` 载入时按注册表解析为实际列表。

## 汇总确认（resolution summary）

必填槽齐备后、生成前发出的一条消息，展示被默认填充的槽（如知识点留空、难度取 medium），供用户确认或修正。

## 多学科组卷（multi-subject paper）

`question` 的 optional 槽 `multi_subject`。自由文本出现多科目时由既有 `_subject_summary` 自动识别并分别出规格；单科目场景不作为必问项。
