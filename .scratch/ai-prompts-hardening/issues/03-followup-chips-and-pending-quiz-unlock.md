# 03: 回复后 follow-up chips + pending_quiz 锁死修复

**What to build:** 两件同属「助手闭环出口」的事——**（a）** 让每一轮回复之后都有一组「下一步」推荐 chips（现状只在空态出现，发出首条消息即消失），仍走**服务端固定目录、非 LLM**；**（b）** 修掉 `pending_quiz` 的会话锁死：当待判定会话收到的消息既不是「对/错」也不是讲解意图时，**先清 `pending_quiz`、再把这条消息交给常规路由**（新问题正常走 LLM），并补上「跳过 / 算了 / 下一题 / 不做了」作为显式退出口。

**Blocked by:** 01（follow-up 词条与能力卡/目录同源，需在同一轮统一目录形态）

**Status:** ready-for-agent

## 为什么（Round 2 核实结论）
- **（b）是真缺陷**（`service.py:353-364`）：`pending_quiz` 写入后，`service.py:554` 在**任何 provider 调用之前**把该会话**任意**后续消息都送进 `_quiz_judge_stream`；非「对/错」输入回落固定文案「请用「对」或「错」回答这道题哦～」且**不递增 attempts、不清 `pending_quiz`** → 新问题永远到不了 LLM，用户被永久卡在判断题里。可退出口仅「对/错」或 `_EXPLAIN_HINTS`（讲解/为什么/教我/不懂/不明白/解释/说说/怎么理解）。
- **（a）现状**：`suggested_actions` 只在空态渲染（`assistant_chat_page.dart:337` `messages.isEmpty`），`GET /assistant/suggested-actions` 是只读目录；SSE 帧里没有 suggested action 概念。
- **Q5 更正（用户追问）**：`build_followup_actions` **尚不存在**，它只是提议名。现状只有 `build_suggested_actions`（`service.py:179`）。两者**同形态不同用途**（同 `SuggestedAction` 契约、同「非 LLM 静态目录」原则；差异在入参多 `business`、时机是「每轮后」、下行走 SSE 帧）→ 应抽**共享词条 + 统一装配入口**，而非并列两个近重复函数。

## 设计
### a. 统一推荐操作装配（取代「新增 build_followup_actions」的双函数方案）
- 抽 **共享词条常量**（单一事实源）：`_ACTION_CATALOG`，键为 `business` + 是否空态，值为 2–3 条 `SuggestedAction`（含既有全局 4 条 / 知识点 3 条）。
- **统一入口** `build_actions(*, situation, business=None, role, knowledge_point_id, teacher_id, session) -> list[SuggestedAction]`：
  - `situation="empty"` → 复现现 `build_suggested_actions` 行为（全局 / 知识点 + 全局）；`GET` 端点改调它（**保持端点契约不变**）。
  - `situation="followup"` → 按本轮 `business`（query/tutor/question/guide/capability）选一组 follow-up chips；带 kp 时叠加知识点向 chips。
  - 保留 `build_suggested_actions` 作为薄封装（或不保留，见下「待确认」），避免破坏既有单测 `test_suggested_actions.py`。
- **下发行**：SSE 新帧 `type: suggested_actions`，`data` 载荷 = `list[SuggestedAction]`。**在哪发**：常规路径在 `ASSISTANT_MESSAGE` 收尾后（`event_stream` finally 前）补发一帧；quiz 出题/判定两个子生成器也各补一帧。
- **前端**：`assistant_notifier.dart` 的 fold 增加该帧类型 → 存到消息对象（如 `List<SuggestedAction> followups`）；`AssistantSuggestedActions` 增加**「给定列表」模式**（不再走 provider 拉取），由 `AssistantMessageList` 在**最后一条 ai 消息下方**渲染。空态仍走现有 GET 端点不变。

### b. pending_quiz 准入与退出口（确定性判定本身不动）
- 新增**纯谓词** `_is_quiz_reply(message)`（＝ `_parse_yes_no is not None` 或 `_is_explain_request`）与 `_is_quiz_abort(message)`（`_QUIZ_ABORT_HINTS = {跳过, 算了, 不做了, 下一题, 换一题, 换个题}`）。
- 改造 `chat` 的准入分支（`service.py:554`）：
  ```
  if conv is not None and conv.pending_quiz is not None:
      if _is_quiz_reply(message):   → return _quiz_judge_stream(...)      # 现状不变
      if _is_quiz_abort(message):   → conv.pending_quiz = None; commit;
                                      return 固定文案「好，这道判断题先放一放～」
      # 其余 = 用户改问了新问题：
      conv.pending_quiz = None; commit
      quiz_dropped_note = "（这道判断题先放一放～）"
      # fall through 到常规路由；最终答案前拼该 note
  ```
- `_is_quiz_abort`/`_is_quiz_reply` 与 `_parse_yes_no` 同文件、纯函数，可单测。
- ⚠️ 求讲解分支（`_quiz_judge_stream` 内）行为不变（揭示答案+清空）。
- ⚠️ 不新增表、不加 DB 列；`pending_quiz` 仍是 `Conversation` 上的 JSON 字段。

## 验收清单
- [ ] 判断题待判定中，用户答「对/错」→ 走确定性判定（零 LLM），与现状一致
- [ ] 待判定中用户说「跳过 / 算了 / 下一题」→ 清 `pending_quiz` + 固定退出口文案，**零 LLM**
- [ ] 待判定中用户问**新问题**（如「那三角形呢？」）→ 清 `pending_quiz`，该问题**正常走路由/LLM**并作答，答案前带「先放一放」提示（可用桩 runtime 断言 provider 被调用）
- [ ] 任意一轮回复后，前端在答案下方渲染 follow-up chips；空态 GET 端点行为不变
- [ ] follow-up 词条为**服务端固定目录**，**非 LLM 生成**；`build_actions` 的 `empty` 分支与旧 `build_suggested_actions` 输出**逐条等价**（既有 `test_suggested_actions.py` 不改即过，或仅改 import）
- [ ] SSE 新帧 `type: suggested_actions` 落库策略明确（建议**不落库**——它是「下一步入口」而非对话内容，避免污染历史回放；需在 ADR-0072 修订中写明）
- [ ] 前端 fold 未知帧类型时安全忽略（旧客户端不崩）；`AssistantSuggestedActions` 空列表 → `SizedBox.shrink()`
- [ ] `pytest tests/ai/ tests/features/assistant/` 全绿；前端 `flutter analyze` No issues + 定向 widget 测试
- [ ] 文件规模棘轮 ≤400 行（`service.py` 若逼近上限，把目录常量拆到独立模块如 `assistant/action_catalog.py`）

**决策锚点：** 并入 **ADR-0072 修订**（不另开号）；follow-up 帧**不落库**；旧 kind 兼容不适用（本票不含 schema 变更）；`pending_quiz` 判定保持确定性（ADR-0040/0042）。

## 待确认（用户放行实现前回一句即可）
- **Q-a**：`build_suggested_actions` 是**保留为薄封装**（零破坏既有单测）还是**直接改名 `build_actions`**（更干净、需同步改 4 处测试调用）？
- **Q-b**：follow-up 帧**不落库**（我的建议：它是入口而非内容）——是否同意？若同意，历史回放里不会出现 follow-up chips（与现状一致）。
