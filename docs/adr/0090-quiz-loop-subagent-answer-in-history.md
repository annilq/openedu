# ADR-0090 · 判断题闭环子代理化（答案进历史）

- **状态**：已接受（追认，实现先行）
- **日期**：2026-10-13
- **分支**：`main`
- **取号**：`docs/adr/` 内最大号为 0089（`0089-scene-aware-ai-generation.md` / `0089-spec.md`，未提交工作），本 ADR 顺延取 0090。
- **Supersede**：ADR-0072 的 `pending_quiz` 服务端待判定状态设计；ADR-0086 / ADR-0087 中的 `quiz_generate` / `quiz_judge` 动作键。

---

## 1. 背景（Context）

出题与判定的旧形态是一整块**服务端分支逻辑**：

- `service.py` 的 `_build_intent_signal()` 把 `req.action` / 按钮负载 / 关键词归一化成 `IntentSignal`，紧跟一组 if/elif 早返回（`quiz=True` 走 `_quiz_generate_stream`，`pending_quiz` 非空走 `_consume_pending_quiz`）。
- 判定侧 `_judge_answer_bool()` 只把模型返回的答案文本收口成布尔，**真正的对错比对与讲解本就由 tutor LLM 完成**——服务端那层归一化不产生任何判断价值。
- `Conversation.pending_quiz` 列把「待判定的题」钉在会话行上：题卡先被 `_strip_and_record_quiz` 剥掉答案再落库，答案只活在 pending 列里， tutor 只能从这一列读。

诉求：**去掉 `_build_intent_signal` 与服务端 quiz 分支，出题与判定都交给子代理**，减少逻辑分支；题卡（含答案）直接进对话历史， tutor 从历史读答案判定，前端对待揭示的判断题卡隐藏答案。

---

## 2. 决策（Decision）

### 2.1 删除服务端 quiz 状态机

- 删 `Conversation.pending_quiz` 列（`db/models/conversation.py`）；启动期幂等迁移由 ADD COLUMN 改为 **DROP COLUMN**（`core/db.py`：SQLite 先 `PRAGMA table_info` 探列再 `ALTER TABLE … DROP COLUMN`；Postgres 走 `DROP COLUMN IF EXISTS`）。
- 删 `service.py` 的 `_JUDGE_FALSE_WORDS` / `_judge_answer_bool` / `_resolve_kp_context` / `_quiz_intro` / `_strip_and_record_quiz` / `_quiz_generate_stream` / `_consume_pending_quiz` / `_stream_sse` 与 `_ACTION_*` 常量、`_build_intent_signal`（原址留 ADR-0090 注释占位）。
- `chat()` 改为 `signal = IntentSignal(text=message, action=req.action)`，quiz 早返回块与 pending 消费块整体移除；`ctx.extra` 不再注入 `"pending_quiz"`。
- `schemas.py`：删 `SuggestedAction.quiz` 与 `AssistantChatReq.quiz`；`build_suggested_actions` 去掉 `quiz=True` 参数。

### 2.2 出题：question 子代理自主判定 judge

- `GeneratedQuestion` / `QuestionOut` / `QuestionSpec` 新增 `judge: bool = False`，经 `assemble_question` → `pipeline.stream_question` → `translate`（`asdict`）贯通进题卡 JSON。
- `question/agent.py` 的 `parse_specs_from_text` 自判 `judge`（文本含「判断题 / 判断对错 / 判断正误」）；`run()` 增加 `ctx.extra` 回填：无 specs 且文本无学科时用 `ctx.extra["subject"]` / `grade` / `courseware.knowledge_point` 补全规格——「出一道判断题」按钮在知识点语境下依然可用。
- `question/manifest.py`：`actions` 由 `["task_generate", "quiz_generate"]` 收敛为 `["task_generate"]`；`triggers` / `hints` 增加「判断题」，纯文本「出一道判断题」改走文本路由。

### 2.3 判定：tutor 从历史读答案

- `assistant/repository.py` 的 `_read_history` 原先只取 `{role, content}`、**丢弃 `payload["cards"]`**，导致 tutor 从历史读不到答案。新增 `_question_card_text(card)`：把题卡（题干 / 选项 / **正确答案 / 解析**）渲染成文本拼进 assistant content，闭环补齐。
- `tutor/agent.py`：删 `_quiz_hint_context` 与 `run()` 的 pending_quiz 读取注入块；`tutor_sop.md` 新增「## 判断题待判定（ADR-0090）」小节——判定依据是历史里题卡自带的 `answer`；说对/错先判再讲、答错先给支架、含糊请其对/错回答、求讲解揭示答案、不得编造题卡外结论。
- `tutor/manifest.py`：`actions` 由 `["courseware_hint", "quiz_judge"]` 收敛为 `[]`。

### 2.4 前端：判断题卡答案待揭示

- `assistant_question_card.dart`：`raw['judge'] == true` 时下传 `isJudge`；`_QuestionBody` 改 StatefulWidget（`_revealed`），`showAnswer = _revealed || !isJudge`。未揭示时展示提示文案「请判断「对」或「错」后回答，判完再点这里核对。」+ `AppTextAction('显示答案')`；答案 / 解析 / 出题思路只在 `showAnswer` 时渲染。
- `assistant_suggested_action.dart` 删 `quiz` 字段；`assistant_requests.dart` / `assistant_notifier.dart` 删 `quiz` 请求参数；`assistant_suggested_actions.dart` 的 `onPrompt` 改签名为 `void Function(String payload)`，调用点传 `a.payload`。

---

## 3. 影响（Consequences）

- **正面**：service.py 少一整块 if/elif 与两个流式助手函数；出题/判定的领域知识全部下沉到子代理 prompt 与 SOP；题卡即答案载体，历史回放天然完整。
- **代价**：`_read_history` 的 content 现在拼入题卡文本（token 变多）；判断题卡的「隐藏答案」依赖前端状态，刷新页面即揭示（无持久揭示态）。
- **迁移**：老库 `conversation.pending_quiz` 列在启动期被 DROP；既有未判定的 pending 题随列消失（视为会话已结束，不补偿）。
- **测试**：`test_quiz_loop.py` / `test_assistant_quiz.py` 重写为覆盖 judge 识别、题卡含答案落库、纯文本不经 action 直达 question、tutor 不注入 pending_quiz、SOP 判定口径；`test_intent_routing_contract.py` / `test_suggested_actions.py` / `test_assistant_suggested_actions.py` 同步动作键收敛。
