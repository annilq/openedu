# 任务：后端 AI 意图路由归一（所有服务走同一个裁决点）

> 日期：2026-10-10 · 范围：`backend/agent_core/` + `backend/app/features/assistant/` + `backend/app/features/tasks/`
> 起因：用户提出「我想所有服务都走意图路由，这样逻辑是否更单一，也会避免竞争问题」，
> 并要求**反转 [ADR-0081 §2.3](../adr/0081-tasks-ai-converge-to-chat.md)**（该节原本决定：有 action 时
> 跳过多轮意图路由、直接定向 `question`）。
> 术语以 `CONTEXT.md` 为准。本文是**实施任务文档**，决策条目录在 ADR-0081 §2.3（已按本文反转）。

**结论先行：方向对，但不能按字面实现。**

「所有服务都走意图路由」如果理解为「把结构化请求合成一句自然语言，再让规则词去猜」，实测会**全线误判**
（见 §2：`出 3 道四年级下学期数学题` → `tutor`）。ADR-0081 §2.3 当初那段判断是对的，但它的**解法**
（绕过路由）制造了新的分裂。

正确的形态是：**把路由的输入从「一段文本」升级为「结构化意图信号」，路由仍是唯一裁决点。**
动作走的是一类**不参与文本竞争**的匹配（等值匹配，声明在 manifest 里），因此既拿不到误判，
也拿不到「谁的词更长 / 谁的 priority 更高」的军备竞赛。

---

## 1. 现状：1 个真路由 + 4 处覆盖/绕过

| # | 位置 | 形态 | 说明 |
|---|---|---|---|
| **R0** | `assistant/service.py:390` `rt.decide(...)` | ✅ **唯一真路由** | 全仓仅此一处调用 `decide` |
| **O1** | `assistant/service.py:393-404` | 路由**后**改判 | 课件上下文：「提示」→ `tutor`；`question` → `guide` |
| **O2** | `assistant/service.py:466-476` | **完全绕过 runtime** | `req.quiz` 直连 `question` pipeline，连 `rt.run` 都不走 |
| **O3** | `assistant/service.py:485-492` | 路由**后**改判 | 待判定态消费后强制 `tutor` |
| **O4** | `tasks/service.py:1590-1591` | **不调 decide，硬编码** | `rt.run("", ..., business="question")`，`message=""` |

即：**裁决点名义上是 `decide`，实际有四处旁路**。每加一个新特性，不是在路由器里加规则，
而是在 `chat()` 里加一个 `if`。这就是「逻辑不单一」的实证。

### 1.1 旁路已经造成的实际缺口

- **学生安全闸门在出题链路上完全失效**：`tasks/service.py:1532` 构造 `RuntimeDeps(..., safety=None)`，
  且根本不调 `decide`，所以 `StudentSafety` 对 O4 这条路径零作用。ADR-0081 让学生也能出题后，
  这个缺口从「教师路径无碍」变成「学生输入不设防」。
- **角色可见性被静默改写**：`runtime.py:90-91` 有兜底 `if business not in visible: business = visible[0]`。
  对文本路由是无害兜底；对动作路由是**把越权/错配静默变成答非所问**（教师动作落到 `guide`，
  学生动作落到 `query`），不报错、不拦截，最难排查。

---

## 2. 实测：为什么不能「合成一句话再让规则去猜」

用真实 manifest 实跑 `agent_core.router.classify`（非推测，2026-10-10）：

| 输入 | teacher 可见集 | 结果 | 期望 |
|---|---|---|---|
| `""`（**O4 现在传的就是空串**） | guide/query/question/tutor | `tutor` ❌ | `question` |
| `出 3 道四年级下学期数学题，知识点：轴对称` | 同上 | `tutor` ❌ | `question` |
| `换一题` | 同上 | `tutor` ❌ | `question` |
| `查一下这道题为什么选B` | 同上 | `query` ❌ | `tutor` |
| `帮我出2道四年级数学题` | 同上 | `question` ✅ | `question` |
| `今天有什么作业` | 同上 | `query` ✅ | `query` |
| `帮我创建一个任务，包含四年级数学题` | 同上 | `guide` ✅ | `guide` |

三条硬结论：

1. **空串 → `tutor`**。O4 直接改成 `rt.decide("")` 会把出题送进伴学答疑，比现在的硬编码更糟。
2. **合成的自然语言也会误判**。「出 3 道…数学题」不含 `question` 的任何 trigger
   （`出题`/`出几道`/`题目`/`来几道` 都不匹配「出 3 道…题」），启发式也落空，最终掉到兜底 `tutor`。
   **这不是词表不够全的问题，是「文本匹配」这个机制不适合结构化请求。**
3. **`查` 是 query 的单字 trigger**（`query/manifest.py` triggers 末位），priority=12 高于 `tutor`(-10)，
   所以「查一下这道题为什么选B」被只读检索接走，而用户要的是讲解。**这是既存缺陷，与本次改动无关但同根**
   （泛词 + 优先级抢答），应在本次一并修。

---

## 3. 目标形态：结构化意图信号 + 三级路由

### 3.1 路由输入升级

```python
@dataclass(frozen=True)
class IntentSignal:
    text: str = ""                    # 用户原始输入（结构化请求可为空）
    action: str | None = None         # 结构化动作键：task_generate / task_question_regenerate / ...
    context: dict[str, Any] | None = None   # 结构化上下文：courseware / pending_quiz / ...
```

`AgentRuntime.decide(signal, *, role, deps)` 取代 `decide(message, ...)`（保留文本签名一个迁移期）。

### 3.2 三级路由（现在是两级）

1. **动作直配**：`signal.action` 与各 manifest 的 `actions` **等值**匹配 → 命中即路由。
   不参与 priority 排序、不参与文本匹配，**不存在竞争**。
2. **规则匹配**：现有 `triggers` 逻辑（`_rule_match`，priority 降序）不变。
3. **启发式 + 兜底**：现有 `hints` → 最低 priority 业务。

### 3.3 映射声明在 manifest，不在 service

```python
# app/ai/subagents/question/manifest.py
"actions": ["task_generate", "task_question_regenerate"],
```

新增字段进 `SubAgentManifest`（`agent_core/registry.py:26-47`，现有 `raw: dict` 便于扩展）。

「哪个业务拥有哪个动作」从此是**一张表**，不是散在 `chat()` 里的 `if`。新增动作 = manifest 加一行，
不动任何 service。

### 3.4 动作路由必须显式处理两个边界（否则比现状更危险）

- **动作命中但业务对当前角色不可见**：**禁止**沿用 `runtime.py:90-91` 的 `visible[0]` 静默改写。
  应返回 `RouteDecision(business=None, extra={"reason": "action_not_visible"})`，由端点转 **403**
  （语义：我知道这个动作，但你的角色不能用）。静默回落会把越权变成答非所问。
- **action 未命中任何 `actions`**：落回文本路由（第 2/3 级），不报错——保持对未知动作的容错。
  但契约测试要保证**声明过的动作必有 owner**（见 §7）。

### 3.5 归一后的收益（这才是重点，不是"路由更准"）

| 收益 | 说明 |
|---|---|
| **裁决点唯一** | 安全闸门 / 角色可见性 / name 解析 / 将来的配额与观测，只在 `decide` 一处生效 |
| **消除优先级军备竞赛** | `guide` 抬到 20 是为压 `query`(12)；`query` 抬到 12 是为接住原 `tasks`(10)。动作通道**完全不参与**比较，新增业务不必再抬 priority |
| **补上安全缺口** | 学生走 `task_generate` 时 `StudentSafety` 生效（现在 O4 路径 `safety=None`） |
| **可单测** | 动作→业务是一张表，测「唯一性 + 无孤儿」即可，不用构造流式场景 |

---

## 4. 实施清单（分三批，每批可独立合入）

### P0 — 动作通道与死参数（本次的核心，ADR-0081 的前置）

1. `agent_core/router.py`：新增 `IntentSignal`；`classify()` 增加 `action` 参数并置于 `triggers` 之前；
   保持 `text` 单独调用的旧行为不变（向后兼容，避免一次性改所有调用点）。
2. `agent_core/registry.py`：`SubAgentManifest` 增 `actions: list[str] = field(default_factory=list)`。
3. `agent_core/runtime.py`：`decide()` 接受 `IntentSignal`；**动作命中且不可见时返回显式 not-visible，
   不回落 `visible[0]`**（改 `runtime.py:90-91`，需按「动作路由 / 文本路由」分两条分支）。
4. `app/ai/subagents/question/manifest.py`：加 `actions: ["task_generate", "task_question_regenerate"]`。
5. `app/features/assistant/service.py`：`_build_intent_signal(req, conversation)` 在 `decide` 之前
   把 action 归一出来；O4 撤销后 `business` 不再硬编码。
6. **删除 `llm_classify` 死参数**（见 §5）。
7. **修 `查` 泛词误判**：从 `query/manifest.py` triggers 移除单字 `查`，改为双字以上
   （`查一下`/`查询`/`查看` 已在列），并补 §2 的实测用例进回归。

### P1 — 把两处「路由后改判」迁进信号（消除 O1 / O3）

- `courseware` 上下文定向（O1）与待判定态定向（O3）改为在 `_build_intent_signal` 阶段产出
  action（`courseware_hint` → `tutor`、`quiz_judge` → `tutor` 等），声明进对应 manifest。
- ⚠️ 需产品确认一处语义：O1 里「出题 → `guide`」是**课件练习**特有的（引导到页面而非直接出题），
  与自由文本「出题 → `question`」不同。迁移时不要把它拍平成一个 action，
  否则会丢失「课件里出题要引导、助手里出题要出卡」的区别。

### P2 — `req.quiz` 走 runtime（消除 O2）

- `_quiz_generate_stream`（`service.py:228`）改走 `rt.run(business="question")`，
  与 ADR-0081 同源后拿到 RAG / Persona / `question_sop` / `source_refs` 溯源 / TOOL 信封
  （现在它直连裸 pipeline，**全部没有**）。
- 注意帧序变化：`rt.run` 会多出 `USER_MESSAGE` + 两条 routing `THINKING`，
  前端 `QuestionGenFold` 需同步忽略（ADR-0081 §落地顺序 ④ 已列）。

---

## 5. 待决：`llm_classify` 是一个从未生效的参数

`router.py:54-69` 收下 `llm_classify` 但**函数体里从未调用它**；`ports.py:197` 声明了它，
而两个 `RuntimeDeps(...)` 构造点（`assistant/service.py:387`、`tasks/service.py:1532`）**都没有注入**。
docstring 写的「规则 → 启发式 →（可选）LLM 兜底」三级，**第三级不存在**。

处置：**本次删掉该参数**（连同 `ports.py:190/197` 与 `runtime.py:87` 的透传）。
理由：留着一个不生效的 seam 会让后续改造误以为「接上 LLM 分类就好了」。
真需要弱意图兜底时，重写一个真被调用的 seam，并把「是否启用」做成显式配置——那是独立议题。

---

## 6. 风险与代价

- **动作名成为新的隐式契约**：action 字符串同时出现在请求 schema 与 manifest，
  两边不同步会静默落回文本路由（§3.4 第二条的容错会让错误不报错）。**必须靠契约测试兜**（§7）。
- **`decide` 签名变更影响调用点**：目前只有 `assistant/service.py:390` 一处真调用，
  但测试里有多个直接调 `classify` 的用例（`tests/ai/test_agent_runtime.py:59-97`），需一并改。
- **不改优先级语义**：文本路由的 priority 完全保留，本次不重排——重排会推翻 ADR-0054 的实测结论。
- **不属于本次**：ADR-0082 的 `owner_id` 归属模型、`project_for_role` 反转（ADR-0081 §2.8）、
  前端改动，均不在本文范围。

---

## 7. 验收

**契约测试（新增 `tests/ai/test_intent_routing_contract.py`）**
- 每个已声明的 `action` **恰好一个** owner；无孤儿 action（声明了但无请求方）/ 无悬空 action（有请求方但未声明）。
- 动作命中不受 priority 影响（打乱 manifest 顺序结果不变）。
- 动作命中但角色不可见 → 返回 not-visible，**不是** `visible[0]`。
- 未知 action → 落回文本路由。
- 学生走 `task_generate` 时 `safety.check_input` **被调用**（现在 O4 路径没调用）。

**回归测试**
- 钉住 §2 的实测表（`""` / `出 3 道…` / `换一题` 均 → `question`；`查一下这道题为什么选B` → `tutor`）。
- 既有路由用例全绿：`test_agent_runtime.py:59-97`。
- 全量后端 ~775 passed 保持。

---

## 8. 与 ADR 的关系

- **反转 [ADR-0081 §2.3](../adr/0081-tasks-ai-converge-to-chat.md)**：该节「有 action 时不调 `rt.decide`、
  直接构造 `RouteDecision(business="question")`"改为「有 action 时**仍走** `rt.decide`，
  以结构化信号命中 manifest 声明的 `actions`」。§2.3 的理由（让规则词猜结构化规格会误判）
  **经实测成立**，但解法从「绕过路由」改为「扩展路由输入」——已在 ADR-0081 中就地标反。
- **不动**：ADR-0030（运行时抽象收口）、ADR-0054（写意图 `guide`，其 priority=20 的实测结论本次不重排）、
  ADR-0033（query/question 边界）。
- **依赖顺序**：本文 P0 是 ADR-0081 落地顺序 ① 的前置——先有动作通道，schema 里的 action 字段才有落点。
