# ADR-0042：助手卡片协议——类型化卡片（kind + 结构化载荷），不做通用 GenUI

需求：AI 用工具查到数据后，消息里应以**卡片**呈现（任务卡、题目卡、学情卡），而不是把数据拼成一句话。本文记录为此确立的卡片契约，以及**为什么不做通用 GenUI（服务端下发 UI schema）**。

## 改动前的三处「判别键被丢掉」

`DATA` 帧本身一直是开放通道——`data.result` 是任意 JSON、业务类型走 `extra.type`，`agent_core` 不感知任何卡片语义（ADR-0025）。问题不在通道，在**契约只有一种形状**：`render_cards` 把工具结果压成 `{type: 标签, subject, stem}`，其中 `stem` 是用 `；` 拼好的一行展示串（`backend/app/ai/subagents/query/render.py`，ADR-0033 决策 11）。在这套形状下，「按类型渲染不同卡片」**根本无从实现**，因为同一个判别键在三处被丢掉：

1. **同名异义**：`result.type` 是**标签**（「错题」「今日任务」），信封里的 `data.type` 是**种类**（`query`）。前端解析时只能二选一地误读。
2. **前端丢弃**：`AiTextFold` 只取 `ev.data['result']`，`data.type` 直接扔（`frontend/lib/features/assistant/domain/ai_text_fold.dart` 改动前 `_withCard`）。
3. **落库丢弃**：`cards.append(ev.data.get("result", ev.data))` —— 落库的 payload 也认不出种类（`backend/app/features/assistant/service.py`）。

后果（实测，非推断）：出题卡的载荷是 `asdict(GeneratedQuestion) + reasoning`，**没有 `type` 字段**，于是前端渲染成「数学 + 题干」——题型 / 难度 / 选项 / 答案 / 解析 / 出题思路**全部不可见**；而同一张卡在家长出题表单里是全的（`parent_task_form_view.dart` 的 `_PreviewCard`）。查询卡则相反：明细被 `；` 压成一行，前端拿不到「哪段是学科、哪段是次数」。

## 决策

1. **`DATA` 帧仍是唯一卡片通道**，信封沿用 ADR-0025 的 `{status, type, result}`。`type`（由 `extra.type` 写入）升格为**卡片种类判别键**，取值细化为：`question` / `task_list` / `wrong_question_list` / `due_review_list` / `mastery_list` / `child_list` / `progress` / `notice`（既有的 `question` / `task` 语义不变，`task` 仍归 `/tasks/{id}/regenerate` 流自读）。一个判别键，不再有第二层。
2. **载荷只放结构化字段**：`{title, subject, items?, stats?, total?, text?}`。`text` 只用于「无结构可言」的情形（空结果、查询失败）。明细的**排序、分行、图标、标签色一律由前端决定**——服务端不再拼展示串（`items[]` 截断时用 `total` 报真实条数，前端渲染「共 N 条」）。
3. **后端成对返回**：`render.py` 产出 `Card(kind, payload)`，`QuerySubAgent.render_tool_result` 把 `kind` 写进 `extra={"type": ...}`、`payload` 写进 `data: {...}`。新增工具必须登记 kind 与明细形状；未登记走 `notice` / 通用行，**不丢帧**。
4. **前端按 kind 分派**：`AssistantCard.fromData` 解析信封 → 类型化对象（`frontend/lib/features/assistant/domain/assistant_card.dart`），`AssistantCardTile` 分派到题目卡 / 列表卡 / 指标卡 / 提示卡（`presentation/widgets/assistant_cards.dart`）。**未登记的 kind 降级**：有 `items` 走通用列表行，否则走提示卡——v1 的 `stem` 为空即 `SizedBox.shrink()` 会让新卡片整张静默消失。
5. **落库整帧 `data`**（含判别键），payload 自描述。会话已持久化卡片但还没有回放端点（`_currentSessionId` 仍是进程内），回放落地时必须按本 ADR 的信封读 `data.type`。
6. **卡片渲染在气泡外侧**：卡片自带 `surfaceRaised` 底 + 1px `outline` 描边，套进气泡是双层容器；气泡只承载正文 / 「思考中」。
7. **复制入口覆盖卡片**：判据从「有正文」改为「正文或卡片非空」，复制内容 = 正文 + 卡片纯文本；纯文本走与视觉**同一份**行投影（`_rowOf` / `_statsOf`），避免两套排版各自漂移。

## 明确不做：通用 GenUI（服务端下发 UI schema）

不做「服务端用 JSON 描述组件树、客户端通用渲染」。三条理由：

1. **消费者只有一个**：单 Flutter 客户端 + 单一设计系统（`AppColors` / `AppSpacing` / `AppRadius`，ADR-0004 / ADR-0014）。通用性没有第二个兑现方。
2. **边界会外移**：一旦允许服务端描述布局，设计系统的一致性与可达性（「一色 + 四档语义色」、密排字号基线、双模式字号映射）就从客户端契约变成服务端契约，而服务端既不知道当前是家长端还是娃娃端，也不该知道。
3. **与既有取向冲突**：本仓对「先上机制」的态度是明确的——`translate.py` 写着「事件类型超过 5 个再考虑换成注册表；现在上注册表是过度设计」。卡片种类目前 8 个、每种的版式就是一张卡，前端一个 `switch` 足够。

**Consequences**：新增卡片 = 后端登记 kind + 明细形状、前端加一个渲染器；漏了渲染器也不会丢内容（降级卡）。代价是两端各持一份 kind 常量表（`AssistantCardKind` ↔ `render.py#_KIND`），由**契约测试**对齐而非靠 review（见下）。

## 验证判据

- 后端：`tests/ai/test_query_subagent.py`（kind 与结构化载荷、明细截断 + `total`、`progress` 走 `stats`、未指派走同一形状、卡片不含答案/解析）、`tests/api/routes/test_assistant.py`（端到端帧 `data.type` + 落库 payload 自描述 + 娃娃端无答案泄漏）。
- 前端：`test/assistant_card_test.dart`（解析 + 容错：字段缺、类型歪、未知 kind、非对象明细）、`test/ai_text_fold_test.dart`（kind 透传、空载荷不挂卡）、`test/assistant_notifier_test.dart`（卡片与文本同挂一条气泡）。
- 分层不变量：`frontend/test/feature_boundaries_test.dart` R1/R2/R3 仍成立（只经 `shared/` 复用，未新增跨 feature 引用）。

## 已知遗留

1. **学科标签的颜色**由前端从 `subject` 字段推（`SubjectAccent.fromName`），服务端只发学科名——颜色属设计系统，不进线协议。
2. **题型 / 难度的两套文案**在 `home` 内并存：短标签（「计算 / 选择」，出题表单预览）与长标签（「计算题 / 选择题」，草稿审核页、题库页）。本次只把短标签抽到 `frontend/lib/shared/utils/question_labels.dart` 供出题预览与题目卡共用，**长标签未统一**——改文案会改变既有页面字面量，属产品决定。
3. **`task` 类型的 DATA 帧**（`app/features/tasks/service.py` 的重生成流，`extra={"type": "task"}`）仍由各页面自行折叠，不进聊天卡片渲染器：它承载的是「整卷重生成的响应体」，不是给人看的摘要卡。
4. **卡片历史回放端点仍缺**：会话与卡片都已落库，但前端会话 id 进程内有效、重启即新建会话。落地回放时必须按本 ADR 的信封读 `data.type`（这正是第 5 条改成整帧落库的原因）。
