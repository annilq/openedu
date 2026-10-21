# 去掉 subagent、一次 LLM 调用同时做分类与执行，可行吗？

> 研究问题：ticket 13 实测显示 LLM 分类器比本地决策模型更准（留出集 9/10 vs 5/10）。既然如此，能不能去掉
> subagent 分层，让一次 LLM 调用同时完成「意图分类」和「任务执行」，从而省掉多余请求？
>
> 结论先行：**不能整体去掉**。「一次调用」只在 tutor 自由文本路径上技术可行，而那条路径能省的恰恰不是请求
> 的大头。三条硬约束挡住了它在 tasks 上的应用：`schema` 与 `tools` 互斥、tasks 强制工具取证（至少两轮）、
> 出题的 N 次调用与路由无关。
> 但**用户的直觉在生产拓扑下成立**：容器化部署里没有 `OLLAYA_URL`，决策原语不可用，**每轮都要付一次 LLM
> 分类**（p50 1084 ms，纯前置延迟）。真正该修的是「每轮都从零重跑路由」——`Conversation.kind` 已经在首轮
> 定了，续轮没有理由再问一次模型。

---

## 1. 一轮到底发几次请求（file:line）

`decide` 在 `chat()` 内被 `await`（`app/features/assistant/service.py:453`），而 `chat()` 在
`StreamingResponse` 构造前就被 await（`app/features/assistant/router.py:54-58`）。所以路由是**纯前置延迟**，
不与流式重叠，用户完整感知。

| 场景 | 前置（非流式） | 流式 | 合计 |
|---|---|---|---|
| a) 教师出题 5 题 | 0（本地决策模型）或 **1**（部署无 ollaya → 落 `classify_llm`） | FC 轮 + **5 次** schema 出题 + 收尾轮 = 7 | 7 ~ 8 |
| b) 学生辅导一句话 | 同上 | 正文流 1 + 场景卡 schema 0~2 | 1 ~ 4 |
| c) 问「你能做什么」 | 同上 | **0**（固定清单，零 LLM） | 0 ~ 1 |

证据：

- 路由：`app/features/assistant/service.py:453`；SSE 建于 `app/features/assistant/router.py:54-58`
- 决策模型是本地 HTTP、不走 LLM provider：`agent_core/adapters/laya.py:94-97`、`agent_core/runtime.py:309-318`
- 退化到 LLM 分类：`agent_core/runtime.py:363-365`、`agent_core/adapters/llm_route.py:89-91`
- FC 首轮下发 12 个工具：`agent_core/subagent.py:296`、`app/ai/subagents/tasks/agent.py:80-84`、
  `app/ai/subagents/tasks/tools/__init__.py:31-47`
- 出题**每题一次** schema 调用：`app/ai/subagents/tasks/generation/pipeline.py:232-234`
- 工具结果回灌后的收尾轮：`agent_core/subagent.py:384-389`
- tutor 正文流：`app/domain/tutor.py:320-330`；场景卡两次 schema：`app/ai/subagents/tutor/scene_intent.py:134`、`:227`
- capability 零 LLM：`app/ai/subagents/capability/agent.py:85-88`

### 1.1 前置延迟的两个来源，量级差 16 倍

来自 `.scratch/ai-intent-routing/eval/results-2026-10-21-consensus.json`（n=47，同一批用例、同一台机器）：

- 决策模型 `decision_ms`：p50 **66 ms**，p90 89 ms，max 223 ms
- LLM 分类 `llm_ms`：p50 **1084 ms**，p90 1361 ms，max 2083 ms

数字的限制因素要分开看：决策模型是本机 MLX 推理（Apple Silicon），零网络往返；LLM 分类是一次
**不带流式的结构化单发**到远端 provider，整段都是用户等待。两者不可直接比「模型快慢」——比的是
「本地 vs 一次远端往返」。

### 1.2 部署拓扑：生产里那次分类调用是真实存在的

`OLLAYA_URL` 在全仓只出现在 `backend/.env:32`，`docker-compose.yml` 的 `backend.environment` 没有它，
`backend/Dockerfile` 也没有。`available()` 判定为「本地引擎须已配置」（`agent_core/adapters/laya.py:131-140`），
因此**容器化部署下决策原语恒不可用，每轮都走 `classify_llm`**。本地开发（`.env` 有值）才享受 66 ms。

---

## 2. 三条硬约束：为什么「一次调用」在 tasks 上不可能

### 2.1 `schema` 与 `tools` 在适配器里互斥

`GenkitProvider.stream` 是三分支，先判 `schema` 并 `return`，再判 `tools`
（`agent_core/adapters/genkit.py:460`、`:475`）。**同一帧不可能既约束结构化输出、又带 function calling。**
「一次调用既给出 route 又执行」要求二者同帧，直接撞墙。

### 2.2 tasks 语义上必须 ≥2 轮（强制工具取证）

`app/ai/subagents/tasks/agent.py:72`：`requires_tool_data = True`。ADR-0033 的硬约束是「整轮零工具调用却给出
正文＝模型在编造」，由 runtime 硬失败拦截，不把编造内容下发。这条约束在语义上要求先调工具、再作答，**天然是
两轮以上**。去掉它就等于去掉反编造闸门。

### 2.3 请求大头在出题，不在路由

出题 5 题 = 7~8 次请求，其中 5 次是逐题 schema 生成（`pipeline.py:232`）。省掉路由那 1 次，是 8 → 7。

---

## 3. 三种「一次调用」的形态与各自代价

| 形态 | 能否工作 | 代价 |
|---|---|---|
| A 前缀分类（`ROUTE: tutor\n…正文`） | 仅自由文本路径可行 | 分类错了 token 已流出，**无法「不采纳」**——ADR-0107 的 `rejected`／落引导门控失去意义；模型会漂移；无 schema 约束 |
| B function calling 当路由（调 dispatch 工具） | 可行但**不省请求** | 工具结果回灌后仍要一轮才能出正文，请求数与现状持平；且撞 2.1，出题无法同时用 |
| C 结构化输出同时给 `route` + `answer` | 仅纯文本业务可行 | schema 分支不能带工具（tasks 不可用）；流式变成 JSON 增量解析，前端渲染契约全部重写 |

---

## 4. 合并会失去什么

- **capability 从 0 请求变成 1 次完整生成**（`capability/agent.py:85-88` 现在是零 LLM 固定清单）。寒暄和
  「你能做什么」要为一次模型生成付费并等待，是纯回归。
- **业务 system prompt 隔离消失**：tasks 的 12 个工具与 tutor 的场景提示合并进同一个 prompt，工具声明翻倍、
  指令 adherence 下降；tasks 的「结论必须有据」（`tasks/agent.py:72`）会被自由作答稀释。
- **路由层角色可见闸消失**（`agent_core/runtime.py:481-500`）。handler 层仍在
  （`app/ai/subagents/tasks/tools/create_draft.py:46-47`、`app/ai/shared/tool_support.py:172-189`），但
  「该业务对当前角色不可见」这层语义没了。
- **可观测性塌一层**：`routed_by` / `prob` / `min_adopt_score` / `rejected`（`agent_core/runtime.py:326-333`）
  不再有独立取值；`Conversation.kind`（`service.py:489`）、TutorLog 触发（`service.py:795`）、`routing_ms`
  独立计时（`service.py:454-456`）失去意义或拿不到值。

---

## 5. 真正省请求的两个杠杆（都比合并划算）

**L1 会话内不要每轮重路由。** 现状：`Conversation.kind` 在首轮由路由决策定下（`service.py:489`），但**每一轮
都重新 `decide`**（`service.py:453`），且完全没有复用 `kind`。续轮沿用 `kind`，出口留给三处：动作直配
（ADR-0081，等值匹配，永远最前）、本地决策模型做「是否换业务」的变更检测（66 ms，比后置拦截便宜）、显式切换
信号。N 轮会话省掉 N−1 次分类调用——在无 ollaya 的部署里就是每轮 1084 ms 的纯前置延迟。这拿到的正是合并
方案想要的收益，但不动架构、不丢闸门。

**L2 出题批量化。** 一次 schema 调用产出 N 题（array schema），3+N 降到 2~3。代价：逐题安全闸门与
`QuestionFailed` 粒度变粗（`pipeline.py:232` 现在是逐题的），前端逐卡流式的 UX 要重做。

---

## 6. 对「LLM 分类更好」这一前提的修正

ticket 13 的 9/10 vs 5/10 是**单轮**用例上的比较。会话内续轮有 `kind` 先验，分类难度远低于首轮。所以
「LLM 更准」买到的主要是**首轮那一次**，而首轮恰恰是唯一必须付的一次。合并不改变这个事实，只改变了它的
呈现位置。

---

## 7. 建议

不整体去掉 subagent。若要降延迟，按 L1 → L2 的顺序做，L1 是单行改动级别、收益最大、风险最低。
若要拿 LLM 的分类质量，配套形态是「首轮用 LLM 分类，续轮沿用 `kind` + 本地模型做变更检测」，而不是把分类
塞进执行调用里。

---

## 8. 追加：续轮沿用 `kind` 时，用户中途改主意怎么办

第 7 节的 L1 有个没回答的问题：沿用上轮业务，那用户中途切换意图怎么办。补了两次实测，**结论要下调 L1 的评级**。

### 8.1 实测一：极简二分类检测器并不比全量分类便宜

脚本 `eval/switch_detection_eval.py`，真实 provider（`deepseek-v4-flash`），12 条「会话中途」用例，
每条同时跑全量 `classify_llm` 与「只输出 `switch: bool`」的极简二分类：

| 形态 | p50 | p90 | max |
|---|---|---|---|
| 全量分类（现状每轮都付） | **928 ms** | 1514 | 2935 |
| 极简二分类（带 2 轮历史） | **1052 ms** | 1202 | 2204 |
| 极简二分类（不带历史） | 1116 ms | 1822 | 2943 |

检测器**不比它想替代的分类快**。延迟由往返与模型调度主导，不是输出 token——把输出从
「业务键 + reason + confidence」砍到一个布尔，省不下钱。

代价不对称也不站在沿用这边：漏检（真切换判成不切换）＝沿用错业务＝答非所问，是**有害错**；
误报（不切换判成切换）＝多付一次全量路由，只是延迟。所以检测器必须做得敏感，而一旦敏感，
误报率上升 → 触发全量分类的次数上升 → 省钱的效果被吃回去。本次 12 条上 0 漏检 0 误报，
但 prompt 里明写了「拿不准选 true」（人为偏向敏感），n=12 不足以定论。

### 8.2 实测二：切换可能不是罕见事件，不能假设「续轮大多不切」

`app.db` 里 `step='routing'` 消息只有 17 条、10 个会话，其中 5 个多轮、7 对相邻轮次，**2 对业务发生变化
（2/7）**。样本太小不能下结论，但它指向的是：切换不是可以假设「基本不发生」的边缘情况。
沿用 `kind` 的错误率若真在这个量级，就是不可接受的。

### 8.3 三条可用的出路（按代价从低到高）

1. **零成本出口，已有基础设施**：动作直配（`agent_core/runtime.py:210-223`）。用户在 UI 上点
   「出题」/「查数据」这类结构化动作 → 与 manifest `actions` 等值命中，直接改判，不需要任何检测。
   这是最可靠的显式切换信号，前端只要在这些入口带上 `action` + `session_id`。
2. **tasks 侧把「这不是我的事」从硬失败改成重路由**：`agent_core/subagent.py:414-420`。今天
   「声明了结论必须有据却整轮没调工具」= 硬失败 `TOOL_UNSUPPORTED`。但在走到这一行之前
   **没有任何正文流出**（思维链在 `:422` 之后才 flush，`:385` 的 flush 只在有工具调用的分支上），
   所以把它改成「回报 runtime 重路由一次」在用户侧只是多等一个 FC 轮，看不到错误。
   需要防重路由循环（只允许一次）。
3. **tutor 侧没有对等信号**：tutor 无工具要求，会硬着头皮自由作答，用户拿到一段「聊出来的题」
   而不是题卡。要么给它也加一个自报（等于又付一次判断），要么明确接受这个降级。

### 8.4 修正后的结论

L1 不再是「收益最大、风险最低」。它在两种前提下才有价值，而两种都不便宜：

- **生产没有 ollaya**：沿用 `kind` 要真省钱就必须完全不调 LLM，那就必须接受切换轮的失误，
  靠 8.3 的 1 + 2 兜底。节省的 928 ms 换来一个「切换时降级」的新失败模式。
- **给生产部署 ollaya**（一次部署改动，`OLLAYA_URL` 现在只在 `backend/.env:32`）：续轮路由回到
  66 ms，**根本不需要沿用 `kind`，也不需要检测器**。这一条现在是我的首选——它不动架构、不动前端、
  不引入新的失败模式，还顺带解决 ticket 14 的延迟。

顺带一个零成本的小改动：`classify_llm` 的 prompt 只有能力清单 + 对话上下文
（`agent_core/adapters/llm_route.py:53-59`），**没有注入「本会话当前业务」这个先验**。注入它可能提升
续轮准确率，但也会提高黏性、让真切换更难识别；在 8.2 的量级下，注入之前需要先确认它不会压低切换的召回。
