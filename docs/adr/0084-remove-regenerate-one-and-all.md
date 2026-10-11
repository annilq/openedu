# ADR-0084 移除「换一题」与「整卷重生成」，收敛为「整份重来 or 逐题编辑」

- 状态：已采纳（已实现）
- 日期：2026-10-11
- 关联：ADR-0056（生成-审阅闸门；本 ADR 反转其「保留单题换一题」的后半句）、ADR-0057（生成可观测性与停止；其少题文案约束随之更新）、ADR-0081（出题收敛到 chat；本 ADR 抽掉其动机之一）、ADR-0023（单流收口；其「整卷重生成复用共享核心」的结论作废）、ADR-0004（题型模型，不动）
- **Supersede**：ADR-0056「草稿页去掉整卷重生成，**保留**单题换一题」中的**后半句**被反转（换一题也删除）；ADR-0081 §2.1 表中「换一题（`…/regenerate-stream`）」与「整卷重生成」两条通道的动机失效。**不动** ADR-0056 的其余结论（审阅闸门、整卷重生成从前端移除），也不动 ADR-0004 的题型模型。
- 依赖：无（纯删减）。

## 1. 背景（Context）

### 1.1 两条服务端重生成能力

| 能力 | 端点 | 粒度 |
|---|---|---|
| 换一题 | `POST /tasks/{id}/questions/{tq}/regenerate` 与 `…/regenerate-stream` | 草稿态就地换一道题，题数不变 |
| 整卷重生成 | `POST /tasks/{id}/regenerate` | 按 `Task.specs` 全量重跑并替换草稿项（R-Q2=c） |

### 1.2 它们与「生成一份新的试卷」是同一件事

出题本身就是「按规格生成一份草稿」的一次调用：`POST /tasks/generate`（流式出卡）→ `POST /tasks/from-generated`（落库成 draft）。**「重新生成试卷」不过是同一件事再跑一遍。** 教师对整份不满意时，「回生成页重来一份」与调「整卷重生成」结果上无差别，而后者额外维护了一条独立的 LLM 调用路径与一整套「全量替换 + 实出题数不足即中止」的落库校验。

换一题的价值更低：它只能原地替换一道题，却为此维护了**两个**端点——同步版常撞前端 30s `receiveTimeout`，于是又补了流式版 `regenerate-stream`。

### 1.3 两条能力都已成为「无入口的遗留」

按 ADR-0056，草稿审核页的「整卷重生成」按钮已被移除；此后单题「换一题」按钮也一并移除。**前端已无任何调用方**，端点只剩后端与 API 测试在用——它们看着还活着，容易被后来者误当成可用能力。

### 1.4 动作键名与语义早已不匹配

`question` 清单声明的结构化动作键 `task_question_regenerate` 名义上是「换一题」，但唯一消费者是**整卷重生成**路径（`tasks/service.py::_regenerate_events`）。键名指向了一个已不存在的功能。

## 2. 决策（Decision）

### 2.1 删除「换一题」全链（前后端）

- 后端：`POST /{task_id}/questions/{tq_id}/regenerate` 与 `…/regenerate-stream` 两个端点、`regenerate_one` / `regenerate_one_stream` / `_regenerate_one_inputs` / `_swap_question` / `_question_from_payload` / `_collect_regenerate_payloads` 及随之孤立的 helper，`repository.regenerate_one_task_question`。
- 前端：`streamRegenerateOne` / `regenerateOne`（客户端与端口）、草稿页「换一题」按钮与卡内流式推理面板、`ReviewLoaded.liveText` 字段与 `ReviewNotifier._assistant` 依赖。

### 2.2 删除「整卷重生成」后端端点与动作键

- 后端：`POST /{task_id}/regenerate` 端点、`regenerate_all` / `_regenerate_all_inputs` / `_commit_regenerated` / `_regenerate_events` / `_collect_regenerate_payloads` / `_task_question_from_payload` / `_is_question_frame` / `_question_fields` / `_expand_spec_items` 及仅供它们使用的 `_question_ctx` / `_count_unindexed`，`repository.regenerate_all_task_questions`。
- 动作键：从 `question` 清单 `actions` 删除 `task_question_regenerate`，契约测试的完整词表同步删除。
- 测试：删整卷重生成回归测试文件；删 `_question_fields` 的孤立单测（其守的「reasoning 不落库」已由 `from-generated` 路由级测试覆盖）。

### 2.3 明确保留的部分

- **`Task.specs` 保留**：仍是审核页摘要展示的取值来源（注释不再说「以便整卷重生成」）。
- **`Task.model` 保留**：批改（`answer`）经 `resolve_engine` 沿用同一模型。
- **`POST /tasks/generate`（流式）+ `/tasks/from-generated`（落库）两步法保留**：这才是「重来一份」的正路。
- **逐题编辑 / 删除 / 加入题库 / 锁定 / 派发 / 作废保留**：草稿页的精修能力不变。

### 2.4 收敛后的语义

教师对一份草稿只有两种处置：**逐题精修**，或**整份重来**（回生成页「重新生成」）。中间粒度的「服务端重生成」不再存在。

## 3. 后果（Consequences）

- 少两条 LLM 调用路径、三个端点、一个动作键，以及一整块「全量替换草稿项」的落库 helper；`tasks/service.py` 显著变薄。
- 少题文案（`agent.py` 收尾语、`home_notifier` 的 `shortMessage`）不再指向已不存在的入口，改为「回生成页重来一份」。
- 代价：丢失「保留其余题面、只换一道」的能力。判为可接受——教师可直接编辑该题，或整份重来。
- **文档债清偿**：ADR-0056 的「保留换一题」与 ADR-0081 围绕换一题的动机由本 ADR 追认；ADR 只读不重写，旧文不再回改。
- 契约守护：动作词表测试（`tests/ai/test_intent_routing_contract.py`）改为「无孤儿 / 无悬空」，`task_question_regenerate` 一旦被重新引入即失败。

## 4. 备选（Considered Options）

- **保留换一题、只删整卷重生成**：换一题有独立维护面（同步 + 流式两个端点、卡内流式面板），且其价值随「整份重来足够便宜」而下降。否决。
- **把两条能力搬进 `/assistant/chat` 的结构化动作**（ADR-0081 原计划）：否决——它们本就无入口，搬进去只是把死代码换个地方，还扩大了 chat 的动作面。
- **保留端点、仅标注 dead code**：正是这种「看着还活着」诱发了本次删除，标注不足以阻止误用。否决。
