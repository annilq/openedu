# AI 线路地图与结构分析（why 调查）

> 来源：`@skill:why` 流程——2 名 investigator（git 沿革 / 仓库内 long-form docs）+ 1 名 synthesizer。
> 调查日期：2026-10-10。证据档位（Direct / Supported / Inferred / Speculative / Unknown）逐条标注，未改写置信语言。
> 本文件是 `.scratch/ai-prompts-hardening/` 工作流的分析输入，**不改任何业务码**。

---

## 0. 速查：线路地图（Direct 证据）

| # | business | priority | roles | 是否跑模型 | 是否声明工具 | 产出 | 备注 |
|---|---|---|---|---|---|---|---|
| 1 | `guide` 任务引导 | **20** | 仅 teacher | **分两面**：引导卡不调模型；课件上下文下**调模型**出题 | 否 | 受控跳转卡 `{actions}` / 课堂单题 `{stem,options}` | **四条线路里唯一没有 SOP** 的 |
| 2 | `query` 学情查询 | **12** | teacher + student | 是（tool loop） | **8 个只读工具** | 工具结果 → 类型化卡片 + 结论 | 唯一 `requires_tool_data=True` |
| 3 | `question` 出题 | **0** | 仅 teacher | 是（schema 约束解码 + 流式） | 否 | 题卡（含解析） | 走共享 `question.pipeline` |
| 4 | `tutor` 伴学答疑 | **-10** | teacher + student | 是（单调用 + 安全闸门） | 否 | 讲解正文 + TutorLog | 路由兜底 |

**入口只有 1 个**：`POST /api/v1/assistant/chat`（`features/assistant/router.py` docstring：「所有 AI 功能经此单入口」，并列出已废弃的 `/ai/tutor/ask`、`/ai/tasks/generate`、`/tutor/ask`）。
所以准确表述是：**1 个入口下挂 4 条路由线路 + 若干上下文分支**。
⚠️ `kind="agent"`（`assistant/service.py:525`）**不是第 5 条线路**，它只是输入被安全闸门拦截（`decision.business is None`）时的落库兜底字符串。

**上下文分支（不是独立线路）**：课件练习 = 同一线路上的分支——`service.py:439-481` 按消息含「提示」分流到 `tutor`、按 `decision.business=="question"` 分流到 `guide`。

---

### The Question

用户在 openedu（Flutter + FastAPI 的 K12 错题复习应用）里觉得「AI 相关功能有点混乱」，需要厘清四件事：(1) AI 有几条线路（business 路由 / 功能入口）？(2) 每条线路上有哪些功能？(3) 有无重复功能可融合？(4) subagent 能否按 teacher/student 分类？

两个内嵌假设被独立检验、不预设成立：**「重复功能可以融合」**（Q3）与 **「可以按 teacher/student 分类 subagent」**（Q4）。

### The Code in Question

- `backend/agent_core/{registry,router,runtime,subagent}.py` — manifest 发现、`classify()`（规则→启发式→最低 priority 兜底）、`visible_businesses(role)`、`run_with_tools` / `requires_tool_data`
- `backend/app/ai/subagents/{guide,query,question,tutor}/{manifest,agent}.py` — 四条线路的声明与执行体
- `backend/app/features/assistant/{service,router}.py` — 唯一入口编排 + 判断题闭环 + `build_suggested_actions`
- `backend/app/domain/{safety,prompts}.py`、`features/{courseware,materials}/service.py` — 散落的系统提示词

---

## 1. 线路沿革（Direct）

- **线路集合演化（`git ls-tree` 三阶段实测）**：`08af442` / `666777b` = `{question, tasks, tutor}` → `b92fee4` = `{query, question, tutor}`（**删 `tasks`、加 `query`**）→ `e6e8374` = `{guide, query, question, tutor}`（= HEAD）。**从无 `agent` business。**
- **`tasks` 是被删的唯一业务**：`query/manifest.py:2` docstring「`query` **吸收并取代**原 `tasks`：只读查询属同一类意图，散成多个 subagent 会让路由权重互相打架（原 `tasks` 为抢「任务题目」把 priority 抬到 10）」；`b92fee4` body「退役 tasks SubAgent 与 app/ai/tools（逻辑并入 query / 零调用方）」。
- **priority 演化的理由都写在作者文本里**：
  - `666777b` 一次性引入 `tasks=10 / question=0 / tutor=-10`。`tutor/manifest.py` 注释「无兜底词：规则与启发式都没命中时，优先级最低者（本业务）接住（ADR-0030）」。
  - `b92fee4`：`query=12`，注释「接住原 tasks 的 priority=10，并压住 question 的「题目」」。
  - `e6e8374` body：「后端新增 `guide` SubAgent（priority=20，压过 query 的 12…）」；`guide/manifest.py` 注释自述「这条优先级是本 subagent 存在的理由——「创建 / 派发」是**写意图**…（实测：`'帮我创建一个任务，包含四年级数学题'` 在只有 query/question/tutor 时路由结果为 `query`）」。
- **文档明确承认过抢路由事故**（不是推测）：
  - `ADR-0050:43-47`「踩坑修正：初版曾加「年级」「题目」作触发词，但路由是子串匹配、query 优先级最高，导致「帮我出 3 道三年级分数选择题」因含「年级」「题目」被误抢到 query（出题意图丢失）」
  - `ADR-0054` 全篇是一份真机报障，`:27` 根因「query 的 triggers 含泛词「任务 / 作业」，且 priority=12 是当时最高 → 任何带「任务 / 作业」的写意图都被只读 agent 接走」；`:42` 决策「写意图独立成 guide，priority=20 压过 query」。
  - `ADR-0054:51-54` 承认代价「宁可漏给 query，也不误抢查询——guide 主动放弃了启发式兜底」。
- **被废弃/回归的功能（实测删除清单）**：`28cb4be` 移除「兴趣画像 / focus_interest」；`e5b3d71` 删「每日配额」（`domain/quota.py` + `TutorQuota/TutorUsage`，**保留 TutorLog**）；`b92fee4` 删 `tasks` + 整包 `app/ai/tools`；`666777b` 删旧出题薄封装 `domain/question_generator.py`；`117a13a`（ADR-0036）删娃娃端独立对话栈，AI 能力收敛单入口。

---

## 2. 每条线路的功能（Direct）

- **guide（20，仅 teacher）双面功能**：(a) 写意图引导卡——不持工具、不调模型，直接产受控跳转卡（`guide/agent.py:119-130`）；(b) **课件上下文下会调模型出题**——`ctx.extra["courseware"]` 非空时走 `_COURSEWARE_SYSTEM` + `_CoursewareQuestion` 契约（只含 `stem/options`）。**guide 没有 SOP**（`guide/skills/` 不存在，四条线路里的孤例）。
- **query（12，双端）**：只读学情查询，声明 **8 个**工具（`query/tools/registry.py:19-28`：`list_students` / `list_teacher_tasks` / `list_today_tasks` / `list_wrong_questions` / `list_due_reviews` / `list_bank_questions` / `get_progress` / `get_mastery`）；唯一 `requires_tool_data=True` 的线路（`query/agent.py:56`）；学生端经 `project_for_role` 去答案 + 恒查自己（ADR-0033 决策 8/9）。
- **question（0，仅 teacher）**：出题（schema 约束解码 + 流式），走共享 `question.pipeline`。
- **tutor（-10，双端）**：适龄讲解（单调用 + `StudentSafety` 安全闸门 `safety.py:85-94`）；学生端落 `TutorLog`；课件上下文下有分级提示 `_courseware_hint_context`（「任何级别都不得直接给出答案、最终结论或完整解法」）。
- **tutor↔question 的边界无专门 ADR**：只能靠两份 SOP（`tutor_sop.md:3`「面向孩子的适龄讲解」/ `question_sop.md:3`「面向家长的出题助手」）与 manifest 触发词推断——**这是文档空白**。

---

## 3. 重复功能（Q3 独立检验）

- **[Direct] 主出题能力已是单源**：`question.pipeline`（`build_question_prompts` / `stream_question` / `generate_question`）被**三处共用**——`question/agent.py`、`features/assistant/service.py:40,270`（判断题闭环）、`features/tasks/service.py:483+`（批量出题落库）。`pipeline.py` 注释自述「流式与落库**同一份** prompt，杜绝两路口径漂移」。`ADR-0072:39-43` 明文「**复用** question 管线 + grader，不新建自由对话判定」。
- **[Direct] 但「出题」存在第二条平行实现**：`guide/agent.py:48-53` `_COURSEWARE_SYSTEM` + `_CoursewareQuestion` 是**独立 prompt + 独立输出契约**，与 `question.pipeline` **不共用任何函数**。
- **[Direct] 文档否认这是重复**：`ADR-0072:29-30` 把课堂练习与新浮层入口描述为「与之互补而非重复」；`ADR-0067:157-165` 把「任务出题」与「课堂即时出题」当两个语境。**即：代码层两套出题并存，文档层未承认其重复。**（矛盾，见 §4 H2）
- **[Direct] 另两处提示词是不同能力，非重复**：`courseware/service.py:58-76` `_DRAFT_SYSTEM` 产 `sections` 环节（`practice` 只是配置块）；`materials/service.py:329-333` `_EXTRACT_SYSTEM` 抽学科/年级/知识点——产物不同。
- **[Direct] 「讲解」不是重复而是三种载体**：`tutor_sop.md`（自由正文）vs `question_sop.md:8`（题解析，落 `explanation` 字段且会落库）vs ADR-0061 交互场景（结构化渲染）；`CONTEXT.md:243-244` 明确「解析（题目上的 explanation，会落库）」与「出题思路（不落库）」不同源。
- **[Direct] 「知识点/资料」三者不同能力**：`_EXTRACT_SYSTEM`（KP 涌现）、RAG（检索注入）、课件（消费 KP 快照）；`ADR-0067:127` 明确 Material 与 CoursewareAsset 分实体。
- **[Direct] 仓库有「重复即合并」的既有正典（唯一、非 AI 案例）**：`ADR-0075:9-17,32-37`——概览的掌握度/薄弱点「完全可由统计页在 scope=all / dimension=knowledge_point 下复现」，「本质是对 analyticsRepository 的重复消费（写死参数版）……违反 ADR-0059 单源精神」→ 合并为单一「教师工作台」，删 `teacher_overview_provider.dart`。**这是本仓处理功能重复的模板。**

---

## 4. 按 teacher/student 分类（Q4 独立检验）

- **[Direct] 角色可见性机制已存在且是唯一真相源**：`roles`（`registry.py:32-33`，默认 `["teacher","student"]`）+ `runtime.visible_businesses(role)`（`runtime.py:64-66`）；`runtime.py:89` 注释「角色可见性是唯一真相源：classify 只在 visible 内决策」。当前值：`guide=[teacher]`、`question=[teacher]`、`query=[teacher,student]`、`tutor=[teacher,student]`。
- **[Direct] 角色只作「过滤器 + 工具侧裁剪」，不是 agent 拆分轴**。文档唯一被论证的拆分裂是**「业务 × 学科两维正交」**：`ADR-0003:10` / `ADR-0021:11` 的 Considered Options 明确**否决**①「每学科每业务各一个 Agent（组合爆炸）」②「单一通用 Agent 带 system 切换」。
- **[Direct] 「按角色拆 subagent」在整个 `docs/` 中从未被提出、更未被论证或否决。** 对 `docs/` 全文正则检索（`按角色|角色拆|拆.*subagent|per-role|双端|角色分叉`）命中全部是「按角色分派回调」「roles 声明」「**同一 subagent 内**按角色分叉输出」（`ADR-0079:22`、`ADR-0072:226-227`）。
- **[Direct] 既有先例是「同 agent 内分叉」而非拆 agent**：`build_suggested_actions` 在同一函数内按 `role` 切 label（`service.py:198-204`）；`QuerySubAgent.initial_system` 按 role 追加 `_CHILD_HINT`/`_PARENT_HINT`（`query/agent.py:64-69`）。
- **[Direct] 学生端安全收敛是刻意的**：`ADR-0026:3-5`「儿童角色……出题 / 查任务等意图重定向到 tutor」；`ADR-0054:56-57`「娃娃端没有布置任务入口，也不该被引导到一个它进不去的页面……这是对的，不是遗漏」；`question/manifest.py:4`「出题仅教师端，ADR-0026 安全：学生端永不暴露出题/答案」。
- **[Direct] roles 演化**：首见于 `08af442`（`question=[parent]` / `tasks=[parent]` / `tutor=[parent,child]`）；`b92fee4` 新增 `query` 时 `roles=["parent","child"]`（docstring 自述「ADR-0033 放宽 ADR-0026 的『娃娃端仅伴学』」）——**唯一一次学生端可见性放宽**；`e6e8374` `guide=["parent"]`；`1f018ad`（ADR-0065）为**纯重命名** `parent→teacher` / `child→student`，`git show` 确认仅字符级 diff，**未改可见集合**。

---

## 5. What We Can Reasonably Infer

- **[Inferred] 「混乱感」的结构性来源更可能是「同一能力在不同上下文里表现不一致」，而非线路数量本身。** 推理链：入口确实只有 1 个（Direct）；但「出题」在**四个位置**以不同形态出现——question 线路（含解析）、`guide._COURSEWARE_SYSTEM`（课堂大屏，不返答案）、quiz 闭环（剥掉答案解析）、tasks 批量落库（走同一 pipeline）。
- **[Inferred] `guide` 承载课堂出题，最可能是路径依赖而非设计选择。** 推理：`e6e8374` 引入 guide 的理由写得很清楚（写意图抢路由，ADR-0054），但课件出题分支在 ADR 侧**无独立决策**（`_COURSEWARE_SYSTEM` 的输出契约无 ADR 记录）——它像被「塞进」了 guide 这个已有出口。
- **[Inferred] 「按角色拆 subagent」即使技术上可行，也与本仓既有决策取向相反。** 推理链：① roles 现作**过滤器**；② 唯一被论证的拆分裂是业务×学科；③ 遇「角色需要不同输出」时的既有先例是**同 agent 内分叉**；④ `ADR-0079` 面对 query 元问题被拦时选择**接走**（新增 capability）而非拆 agent。**注意这是「缺乏支持证据」，不是「被否决」。**
- **[Inferred] 主出题的「单源」是刻意维护的，guide 的第二套出题更可能就是「未被纳入同一收口」的遗留。** 推理：`pipeline.py` 明写「杜绝两路口径漂移」说明作者对该口径漂移有明确敏感度，而 `_COURSEWARE_SYSTEM` 未被纳入任何收口文档。

---

## 6. Competing Hypotheses

**H1（线路数）**：「4 条」vs「3 条 + 分支」vs「5 条（提案态）」。代码事实支持 4（Direct），但文档口径在 2~5 间摇摆（Direct：`CONTRIBUTING.md:23`=3 而 `:50`=4，同一文件自相矛盾）。两种解释（文档滞后 / 对「什么算一条线路」无共识）**现有证据无法区分**。

**H2（两套出题：重复 vs 互补）**：文档说「互补而非重复」（Direct），代码显示两套独立 prompt + 契约（Direct）。二者可同时为真——**若**「课堂即时出题」与「自主练习出题」在业务语境上确实不同（一个不落库/不记错题、一个进闭环），则「互补」成立；**但**若只是入口不同，则属可融合的重复。**判定关键在于产品意图，文档未提供决定性证据。**

**H3（能否按角色分类）**：「不被支持」vs「未被考虑」。证据明确：从未被提出/否决（Direct）。两种解释：(a) 没必要（现有 roles 过滤已足够）；(b) 没人想过。**均为推测**。

**H4（「混乱」根因）**：线路过多 vs 上下文分叉过多 vs 提示词散落。本报告倾向后者，但**未排除**前者——`guide` 同时做「引导卡」和「课堂出题」两件不相关的事，本身就是认知负担。

---

## 7. What We Don't Know

- **GitHub Issues / PRD 不可查询**：仓库用 GitHub Issues 承载 issue/PRD（`docs/agents/issue-tracker.md`），但本环境 `gh` 未认证（`gh issue list` → "please run: gh auth login"）。**所有「用户报障 → 设计决策」的一手讨论无法取证。**
- **团队实时沟通**：无匹配 MCP（仅 agent-mail）。`ADR-0054/0072` 背后的口头权衡无法验证。
- **基础设施可观测性 / 错误追踪 / 产品分析**：均无匹配 MCP，未搜索。**无法用真实使用数据判断哪个功能实际被用到。**
- **前端 UI 入口未逐一核对**：ADR-0036/0047 声称「每角色恰好一个 AI 入口」，但这是**文档声明，非前端实测**。
- **`guide` 课件出题的引入决策**：`docs/adr` 侧无独立决策记录；**为什么课堂出题与 question 出题要分两套，无文档解释**。
- **一处 citation 修正**：Investigator A 称 `git log -S 'roles'` 命中「08af442 / b92fee4 / 1f018ad」；实测命中「08af442 / b92fee4 / **e6e8374**」（`1f018ad` 是纯重命名，`roles` 字符串计数不变故不被 `-S` 捕获）。**实质结论不受影响。**

---

## 8. Sources Consulted

- **Source control history（git）**：已查。实测 `ls-tree` / `show` / `-S` 于 `08af442`、`666777b`、`b92fee4`、`e6e8374`、`1f018ad` 及 HEAD；读了 11 个 commit 的完整 body；读四个 manifest + 目标文件注释 + `tests/ai/*`。
- **代码内注释 / docstring / manifest 文本**：已查（视作作者意图的一手证据）。
- **Long-form documents（仓库内 ADR / specs / CONTEXT / agents docs / SOP / 学习文档）**：已查。~50 份文档全文或相关段。
- **Issue / ticket tracker**：**未查**。`gh` 未认证。
- **Real-time team chat**：**未查**。无匹配 MCP。
- **Infrastructure observability / Error tracking / Product analytics warehouse**：**均未查**。无匹配 MCP。
- **Model substitution note**：pstack 配置要求 `why investigators: grok-4.7-high-fast` / `why synthesizer: claude-opus-5-5-high`，但本 harness 的 subagent 工具不接受该 slug，故 investigator 用 default、synthesizer 用 reasoning 档位运行。

---

## 9. Confidence Summary

| 结论 | 档位 | 强度 |
|---|---|---|
| HEAD 有 4 条 business，且只有 1 个 HTTP 入口 | **Direct** | 极高 |
| `agent` 非 business，仅是落库兜底串 | **Direct** | 极高 |
| 线路数文档无唯一口径（2~5 摇摆） | **Direct** | 高 |
| 各线路功能清单（Q2） | **Direct** | 高 |
| 主出题能力已单源（`question.pipeline`，3 调用点） | **Direct** | 高 |
| 存在第二条平行出题实现（`guide._COURSEWARE_SYSTEM`） | **Direct** | 高 |
| 「是否可融合」的**判定** | **Inferred / Unknown** | **低**——需产品意图 |
| 角色可见性机制已实现且是唯一真相源 | **Direct** | 极高 |
| 「按角色拆 subagent」从未被提出/否决 | **Direct**（「未找到」是搜索结论） | 高 |
| 「拆 agent 与既有拆分裂取向相反」 | **Inferred** | 中 |
| 残留/过时项清单 | **Direct** | 高 |
| 用户「混乱感」的根因 | **Inferred / Speculative** | 低-中 |

> **总体**：线路的**结构与沿革**证据充分（Direct），可直接行动；**「重复是否该融合」** 与 **「是否该按角色拆」** 两个用户内嵌假设，证据只支持到「未被否决 / 缺产品意图」——不建议据现有材料直接动手。

---

## 10. Preserve / Change / Avoid / Risk

### Preserve（动它会破不变量或安全边界）

1. **`visible_businesses(role)` 作为角色可见性的唯一真相源**（ADR-0036:11、`runtime.py:89`）。
2. **`requires_tool_data`**（ADR-0033:12、ADR-0079:12-13）——放宽 = 重开「未查先答」编造口子。
3. **`priority` 即功能，不可当调参**（ADR-0054:42-44；守卫 `test_guide_subagent.py:73`）。
4. **单入口 `POST /assistant/chat`**（ADR-0036，双入口方案已被否决）。
5. **业务 × 学科两维正交，角色不是拆分轴**（ADR-0003:10、ADR-0021:11）。
6. **`project_for_role` 裁剪只在一处**（ADR-0033 决策 8/9、ADR-0065:97）。

### Change（有 Direct 证据支持可以动）

1. **清理残留**：空目录 `backend/app/ai/subagents/tasks/`（`git ls-files` 空）；`query/tools/registry.py:1`「7 个」措辞；三份 SOP 的旧术语与已删概念（`query_sop.md` 通篇「家长/娃娃」、`question_sop.md` 残留「兴趣融入须来自受控分类叶子」）。
2. **给 `guide` 补 SOP，或明确「无 SOP 是刻意的」**——四条线路里唯一的孤例。
3. **stale 文档对齐**：`CONTRIBUTING.md:23/50` 自相矛盾、`docs/agents/architecture.md:56,75` 只列 3 条、`docs/learning/.../cheatsheet.html:50-53` 的 roles 列仍 `parent/child` 且误标 guide「不调模型」。
4. **ADR-0072:237-243 的未落地项**（pending_quiz 锁死 / 分级提示文案硬编码 / §2 系统提示未落地）——已在既定三切片范围内。

### Avoid

- **【已明确否决】** 放宽 `query.requires_tool_data`（ADR-0079:49）；让 LLM 自由自述能力（0079:51）；在 `service.chat` 做确定性关键词分支（0079:50）；通用 GenUI（ADR-0042）；每学科每业务各一个 Agent（ADR-0003/0021）。
- **【未被否决、但缺证据支持】** **按 teacher/student 拆 subagent。** 诚实说明：**这不是「被否决」，而是「从未被提出或论证」**。因此不能引任何 ADR 说它「被否」；只能说它与既有拆分裂（业务×学科）和既有先例（同 agent 内分叉）取向相反（Inferred）。若要做，**它是新决策，需自己的 ADR + 守卫**，不能当作「整理现状」。
- **【高风险】** 直接改 roles 可见集合（如放开学生端出题）：触碰 `test_decide_student_*`、`test_student_out_of_scope_stays_tutor`、`test_student_never_sees_guide`、`test_student_query_visible` 一批守卫，且与 ADR-0026/0054/0065 的安全收敛正面冲突。

### Risk

| 改动 | 风险 | 「完成」的条件 |
|---|---|---|
| 清理空目录 / 注释计数 / stale 文档 | 低（无行为） | `git ls-files` 无残留；文档与四 manifest 值域一致 |
| 给 guide 补 SOP | 低-中 | 不改 guide 的零-LLM 引导路径；`_CoursewareQuestion` 契约不变；`test_guide_subagent.py` 全绿 |
| 收口两套出题 | **中-高**：口径/契约/是否落库/是否记错题都不同 | 先有 ADR 判定「两语境是否同一能力」；契约测试覆盖两入口差异；不破 ADR-0072 闭环 |
| 修 pending_quiz 锁死 | 中：跨请求状态 | 非「对/错」输入能退出判定或清状态；加回归测试 |
| 任何 roles 变更 | **高** | 新 ADR + 更新 `test_decide_student_*` 系列 + 交叉引用 ADR-0026/0047 |
| 按角色拆 subagent | **最高**：无先例、无支持证据 | 先有 ADR 论证收益 > 拆分裂代价；否则不做 |

### 偏序建议

1. **先做「零风险对齐」**——清空目录 + 修计数注释 + 对齐 stale 文档。理由：纯事实错误、不改行为，且是「混乱感」的真实来源之一（文档自相矛盾）。
2. **再做已拍板的「提示词/闭环加固」三切片**（ADR-0079 / ADR-0080 / ADR-0072 修订）。理由：既定范围，且与「能力自述」这一用户可感知的混乱直接相关。
3. **然后处理 `guide` 的定位**——补 SOP 或明确其无 SOP 是刻意的。理由：guide 是唯一同时做两件不相关事、且唯一无 SOP 的线路。
4. **最后才议「两套出题是否融合」**——先出 ADR 判定，再决定收口。理由：这是证据最不足以定论的假设（H2），需产品意图输入。
5. **「按角色拆 subagent」不作为独立动作项**——若确有此需求，走新 ADR 单独评审。**默认不动。**
