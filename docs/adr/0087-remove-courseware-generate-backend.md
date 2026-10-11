# ADR-0087 · 补删 `courseware_generate` 后端半边（ADR-0086 遗漏）

- **状态**：已接受（Accepted）
- **日期**：2026-10-11
- **分支**：`ai-intent-routing`
- **取号**：本分支最大 ADR 为 0086，顺延取 0087（并行 `figlib` 分支占用的 0083 不计入本分支）。

---

## 1. 背景（Context）

ADR-0086 端到端删除了课堂练习环节（`SectionPractice` 组件、`section.practice` 字段、编辑入口、前端测试），
但其「关键判定」与「相关」两节声称：

> 后端动作键 `courseware_generate` / `courseware_hint` / `quiz_judge` 仍被浮标使用，**不删**。

事后复核（2026-10-11，基于代码实态 grep 全仓）发现该判断**不准确**：

- 浮标 `DraggableAssistantFab` → `AssistantChatPage(coursewareContext)` 只下发 `courseware` 上下文；
  后端 `_build_intent_signal` 在 ADR-0086 后**仍会发射** `courseware_generate`（当课件上下文文本被分类为「求题」），
  落到 guide 子代理的 `if isinstance(courseware, dict):` 分支调 LLM 出大屏题。
- 但 ADR-0086 已删掉消费该题面的 `SectionPractice` 大屏结构化 UI，于是 `courseware_generate` 变成一个**孤儿键**：
  浮标不再有对应 UI，出题结果降级成聊天里的纯文本题面。这是一次**不完整的删除**——前端删了，后端半边漏删。

ADR-0085 当时把 `courseware_generate` 列为「B 不触碰项」是准确的（那时课堂练习还在）；
ADR-0086 延续了该键但误判其「仍被使用」。本 ADR 修正这一判断并完成后端清理。

---

## 2. 决策（Decision）

移除 `courseware_generate` 的后端半边，使 ADR-0086 的删除彻底闭环：

- guide 子代理**不再持有任何结构化动作键**（其「发布任务 / 题库」引导纯由文本 `triggers` 命中）。
- 课件上下文在信号归一化里只产生两个方向：**答错求提示 → `courseware_hint`（tutor）**，其余（含求题 / 求讲解）→ `action=None` 交回文本路由到 tutor。
- 课件里问「出几道题」现在会落到大屏答疑（tutor），不再有「引导到课堂大屏出题」的语义。

---

## 3. 删除清单（What Removed）

**后端代码**

- `app/features/assistant/service.py`
  - 常量 `_ACTION_COURSEWARE_GENERATE = "courseware_generate"`。
  - `_build_intent_signal` 的课件分支：去掉 `classify` 调用与 `courseware_generate` 发射，改为 `action = _ACTION_COURSEWARE_HINT if "提示" in text else None`；移除 `classify` import。
  - 同步修正顶部注释块与函数 docstring（移除「课件练习方向」「两种出题」中关于 `courseware_generate` 的表述）。
- `app/ai/subagents/guide/manifest.py`：`"actions": ["courseware_generate"]` → `"actions": []`，更新注释。
- `app/ai/subagents/guide/agent.py`：删除 courseware 出题分支（`if isinstance(courseware, dict):`）、`_COURSEWARE_SYSTEM` / `_COURSEWARE_LLM_UNAVAILABLE` / `_CoursewareQuestion` / `_courseware_prompt` / `_render_courseware_question`，及因此失效的 import（`sqlmodel`、`StructuredDone`、`normalize_options`/`schema_field`、`check_output`）；保留 `TARGET_CREATE_TASK` / `TARGET_QUESTION_BANK` 与导航卡分支。

**后端测试**

- `tests/ai/test_intent_routing_contract.py`：移除 `_EXPECTED_ACTION_OWNERS` 中的 `courseware_generate` 项，删除 3 个用例（`test_decide_courseware_generate_routes_to_guide`、`test_quiz_generate_is_distinct_from_courseware_generate`、`test_two_generate_intents_have_independent_action_keys`）。
- 删除 `tests/features/courseware/test_courseware_practice.py`（整文件）——它测的正是被删的课件练习后端半边（出题→guide、无模型提示语等）；其存活的 `courseware_hint` 方向已由 `test_intent_routing_contract.test_decide_courseware_hint_routes_to_tutor` 覆盖。

**文档**

- `docs/ai-architecture-map.md`：修正「`courseware_generate` 已休眠」为「已彻底移除（ADR-0087）」；guide 动作键改为（无）；能力映射图移除 `courseware_generate` 节点；quiz 闭环标注「保留」。

---

## 4. 保留（What Kept）

- guide 的「发布任务 / 题库」导航卡（`TARGET_CREATE_TASK` / `TARGET_QUESTION_BANK`）与文本 `triggers`（创建任务 / 布置作业 …）——与 `courseware_generate` 无关。
- `courseware_hint`（课件答错求提示 → tutor）与浮标入口。
- **出题-判断闭环**（`pending_quiz` / `_quiz_generate_stream` / `_consume_pending_quiz` / `quiz_generate` / `quiz_judge`）：本次复核确认其**完整存活**（后端处理函数 + 前端「出一道判断题」按钮 `quiz:true`），未随 ADR-0086 删除，故保留。
- `question` 的 `task_generate` / `quiz_generate`；`task_generate` 的专属 `/tasks/generate` 出题端点。

---

## 5. 与既有 ADR 的关系

- **Supersede ADR-0086** §关键判定 / §相关：其「`courseware_generate` 仍被浮标使用、不删」的判断被本 ADR 修正——前端 `SectionPractice` 删除后该键已成孤儿，本 ADR 补删后端半边。
- **修正 ADR-0085** §B 列表的隐含延续：0085 当时把 `courseware_generate` 列为 B 不触碰项是准确的，但 0086 在 B 已部分删除后仍延续了该键，本 ADR 收口。
- **不触发 ADR-0084** 的「重生成」删除范围，亦不触碰 quiz 闭环。

---

## 6. 验证（Verification）

- `ruff check` 改动文件全绿（含 `guide/agent.py` import 排序）。
- `pytest tests/ai/test_intent_routing_contract.py tests/ai/test_guide_subagent.py tests/features/assistant/test_quiz_loop.py` → **30 passed**。
- `pytest tests/features/assistant tests/api/routes` → **215 passed**（覆盖 `chat` 编排、`_build_intent_signal`、quiz 闭环、推荐操作）。
- 全仓 grep `courseware_generate` 除历史文档/注释外零代码引用。

---

## 7. 提交拆分

1. 后端清理（service.py / guide/manifest.py / guide/agent.py + 测试删除与修订）。
2. 文档（`docs/adr/0087` + `docs/ai-architecture-map.md`）。
3. `chore(memory)`：记本次补删与「先前提「休眠」实为漏删」的复核结论。
