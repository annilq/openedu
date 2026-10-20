# ADR-0103 聊天题卡也要带图：流式帧上盖章 + 前端按选项对象解析

- 状态：已采纳
- 日期：2026-10-20
- 关联：ADR-0089（选项图形身份键，模型不给顶点）、ADR-0091（SceneSpec 新形）、ADR-0061 §M（`scene_spec` 快照）、ADR-0101 / ADR-0102（同一次报障的前两道闸门）

## 1. 背景

修完 ADR-0101（路由）与 ADR-0102（场景模板 / 知识点回落）后，读者会以为「配了场景就能出图」。
实测不是：**聊天题卡这条链路上，图形数据在两端各丢一次。**

### 1.1 后端：题卡流式帧上没有图

`generate_questions` 的流式 handler 只做了两件事：注入 `source_refs`、把题卡塞进
`generated`。而模型给的选项是 `{text, figure_key}`（**只有身份键**，ADR-0089 明令
模型不得产出顶点）——几何原本应在**落库前**由 `tasks/service.py::_stamp_option_figures`
从图库盖章。于是：

- **落库后的**任务页 / 题库页有图（那里读了盖过章的 `options`）；
- **聊天里的**题卡永远没有图，因为 SSE 下发的是盖之前的帧。

同一件事还有 `scene_spec`：它由落库路径 `build_scene_spec_for_question` 构建，
聊天帧里根本没有这个键——前端 `AssistantQuestionCard` 早就能渲染 `scene_spec`，
但它永远拿不到。

### 1.2 前端：选项是对象，却被当字符串读

`assistant_question_card.dart` 读选项用的是：

```dart
options: (raw['options'] as List).map(cardStr)…
```

`cardStr` 是 `'$v'.trim()`，实测：

```
cardStr({'text': '房子', 'figure_key': 'house'})
  → "{text: 房子, figure_key: house}"
```

即：即使后端盖了章，卡片上看到的也只是一串 map 文本，而不是图形缩略图。
能正确解析 `{text, figure}` 的 `QuizOption.parseList` 当时只在 `QuestionPreview` 用——
**同一份数据两套解析**，正是「换个地方就没图」的复生点。

## 2. 决策

**在流式帧上就把题卡补成「可渲染形态」，前端统一走 `QuizOption`。**

### 2.1 后端：`_enrich_card`（`generate_questions.py`）

题卡一旦产出（在 `yield` 之前），补两样：

1. **选项盖章** `_stamp_option_figures`：`figure_key --stamp_figures--> Figure{key,label,points,edges}`，
   与落库路径共用同一套原语（`stamp_figures` / `allowed_keys_for_question`）；
   **全-or-无**——任一键不合法 / 部分选项没图 → 整题退化纯文字（半套图会误导成
   「这个选项不是图形」）。无论有无图，选项都归一成 `{text, figure}` 对象（前端一个形状）。
2. **交互讲解快照** `_attach_scene_spec`：`build_scene_spec_for_question` 算出本题
   `scene_spec` 随帧下发；取不到模板就**不写该键**（写 `None` 会让前端误以为
   「有 spec 但解析失败」）。

两者全程容错：任何异常只意味着「这张卡没有图」，绝不让一道好题因为图挂掉
（与 `_figure_catalog` 同一纪律）。

### 2.2 前端：`QuizOption.parseList` 统一入口

- 题卡选项改读 `QuizOption.parseList(raw['options'])`（tolerant：`String` → 纯文字；
  `Map` → `text` + 可选 `figure`），旧会话回放的纯字符串选项零回归。
- 带图形的选项右侧渲染 52×52 缩略图（`FigureThumbPainter`，只画不判）；点缩略图弹
  **完整**对折演示（`ReflectionSceneDialog`），与练习页 `AppOptionTile` 同一入口、
  同一视觉语言。可点区走 `AppFocusableAction`（ADR-0046：桌面端 Tab 要跳得到）。
- 复制文本（`card_payload.dart::cardQuestionLines`）同步改走 `QuizOption`：
  几何复制不出来，但至少复制出人话——`A. 正方形（图：正方形）`，而不是 map 字符串。

## 3. 后果

- 「知识点配了场景」在聊天里**当场可见**：题卡带图形缩略图 + 可点开的对折演示；
  回传落库后任务页 / 题库页看到的仍是同一份几何（快照自包含）。
- 代价：出具题卡时多两次数据库查询（图形目录 + 知识点模板）。都在 `session` 上、
  单题一次；出题本身是一次 LLM 调用，这点开销可忽略。取不到就跳过，不阻断。
- 代价：题卡选项形状从「字符串」变成「对象」。前端由 `QuizOption` 单点兜住；
  后端落库路径早已按对象处理（`normalize_options`），**没有第三处消费者**。
- 不变：模型仍然只给身份键、绝不产出顶点；几何权威仍是图库（ADR-0089 不动）。

## 4. 备选（否决）

- **只在前端按 key 回查图库**：运行时就要拉全量图库、且离线不可用——违反 ADR-0083
  决策 7「运行时零图库依赖」，也把几何权威从「快照」改回「库」。
- **只在落库时盖章，聊天里等前端回传**：题卡不会二次下发，用户当场就是看不到图。
- **让模型直接产出顶点**：模型编不出正确坐标，且会让几何失去权威（ADR-0089 的核心否决项）。
- **前端写第二套选项解析**（在卡片里再判一次 `Map`）：那就是本次被消灭的「两套解析」。
  统一到 `QuizOption` 后，卡片 / 练习页 / 题库页读的是同一个模型。

## 5. 守卫

| 测试 | 锁什么 |
|---|---|
| `tests/ai/test_tasks_generation_stream.py::test_stream_question_card_stamps_option_figures` | 流式帧上的选项已是 `{text, figure}`（不再有 `figure_key`），几何带 points/edges |
| `…::test_stream_question_card_attaches_scene_spec` | 配了模板 → 题卡带 `scene_spec` |
| `…::test_stream_question_card_without_template_omits_scene_spec` | 没配模板 → **不写**该键（而非 `None`） |
| `…::test_invalid_figure_key_degrades_to_text_not_crash` | 幻觉键 → 整题纯文字，不抛、不半套图 |
| `frontend/test/assistant_question_card_test.dart` | 选项不渲染成 map 字符串；带图选项各一张缩略图；纯文字题零变化 |
| `frontend/test/no_bare_gesture_guard_test.dart` | 缩略图可点区走 `AppFocusableAction` |
