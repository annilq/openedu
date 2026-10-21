# ADR-0105 无命中兜底改为能力引导：执行体必须被显式路由

- 状态：已采纳
- 日期：2026-10-20
- 关联：ADR-0104（§2.1「兜底助手」子句由本 ADR 取代）、ADR-0079 / ADR-0097（capability 能力自述，零 LLM 固定清单）、ADR-0081（动作直配，不受影响）、ADR-008（学生 TutorLog 随之只在显式 tutor 轮落库）
- **修订（2026-10-21，ADR-0107）**：本 ADR 的「命中」原定义为「模型给出一个业务且 pmax ≥ 0.5」（阈值在决策模型适配器内）。门控上移后，「命中」= **模型给出的业务通过了 runtime 的门控**（`min_adopt_score`：业务自述 → 角色覆盖 → 默认 0.5）。落点与「至多一个业务声明 `fallback_guide`」的纪律不变，判定位置从适配器移到 runtime。
- 实现：分支 `ticket/08-decision-routing`，本轮（继 `4fcc686` 决策模型、`d8a9ed0` LLM 分类、`20a77a0` rule 移除之后）

## 1. 背景

ADR-0104 移除规则路由后，「都没有命中」（策略原语——决策模型 / LLM 分类——均不可用
或不决策）的落点是**可见集中 priority 最小者**，生产拓扑即 tutor(-10)。这带来两个
问题：

1. **tutor 成了隐式入口**：它从未被「选择」，只是数值最小。路由模型超时、语法错乱的
   消息、「随便聊聊」——全都静默得到一段伴学讲解，而其中很多本应得到「你能做什么」
   的引导。执行体被兜底语义绑死，显式路由反而成了例外。
2. **兜底与显式路由不可区分**：`routed_by="default"` 与 `"llm"` 的差别只存在于
   `extra`，用户视角下「模型选了 tutor」与「没得选落了 tutor」完全同形。

用户据此定调（2026-10-20）：**tutor 也需要显式触发，不作为兜底逻辑；都没有命中则
提示自身能力引导**。

## 2. 决策

**「都没有命中」的落点从 tutor 改为能力引导（capability）；所有执行体（tasks /
tutor）必须被模型显式路由到。**

- `SubAgentManifest` 新增声明式字段 **`fallback_guide: bool = False`**：声明「策略
  原语均不决策时，由本业务接住并给出自身能力引导」。内核不硬编码任何业务键——
  「谁是引导业务」随清单走。
- `runtime._fallback_business`：可见集中声明了 `fallback_guide` 的业务即无命中落点；
  没有任何业务声明（或声明业务对当前角色不可见）时，退到可见集中 priority 最小者作
  **最后防线**——当前生产拓扑不可达（capability 双端可见且已声明），仅为将来的清单
  变化保住「路由永不返回 None」。
- capability manifest 声明 `fallback_guide=True`：它零 LLM、返回服务端固定的「职责
  边界 + 你可以让我：…」清单（ADR-0079 / ADR-0097），正是「提示自身能力引导」的
  现成载体；「你能做什么」类元问题同时继续由模型按能力清单**显式**路由到它。
- tutor / tasks 的 `priority` 语义纯化为「能力清单呈现顺序」，不再有兜底含义。

## 3. 后果

- **行为**：无任何路由模型（都不命中）时，用户收到能力引导（「我可以帮你……你可以
  让我：· 任务学情与出题助手：… · 伴学答疑：…」），而非一段可能答非所问的讲解。
- **tutor 只在显式路由到时执行**：学生端 TutorLog（ADR-008 / F-305）随之只在显式
  tutor 轮落库；端点测试的学生伴学用例改为经 `route_to` 显式声明落点（替身不猜）。
- **会话 kind**：都不命中的新建会话 `kind="capability"`（前端 run_trace 已有
  `'capability' => '能力自述'` 映射，无需改动）。
- **可观测性**：`routed_by="default"` 从此稳定等价于「都不命中 → 能力引导」。
- **测试面**：兜底回归表（8 句）从 tutor 翻转为 capability；新增「声明业务优先于
  priority 最小者」与「无声明时的最后防线」两层合成测试。
- **已知代价**：路由模型长时间不可用时，真实问题也只会得到能力引导——这是用户明确
  接受的方向（「都没有命中则提示自身能力引导」），模型恢复后行为自动回归显式路由。

## 4. 备选（否决）

- **保留 tutor 兜底，仅追加「连续多轮 default 才给引导」**：两套兜底语义、状态ful
  分支，且违背用户「tutor 不作为兜底逻辑」的原话。
- **在内核硬编码业务键 "capability"**：破坏 agent_core 的业务无关性（内核零业务
  依赖是其分层不变量）；声明式字段 + 契约测试是本项目既有的表达习惯（cf. 动作归属
  唯一性）。
- **用 priority 数值重新指定（capability 改 −20）**：把「清单呈现顺序」与「无命中
  落点」耦合进同一个数字——将来任何新业务只要数值更低就静默接管兜底；且 capability
  的 priority 当前是惰性的（自身不出现在能力清单里），改它会留下「为什么是 −20」
  的谜。声明字段把两个语义显式分开。
- **删除兜底、允许返回 None**：`run` 的 None 分支是 INPUT_UNSAFE 错误帧，「没有
  可用助手」会被说成「输入不适当」；且破坏 ADR-0104 建立的「永不返回 None」不变量。

## 5. 守卫

| 测试 | 锁什么 |
|---|---|
| `tests/ai/test_capability_subagent.py::test_manifest_declares_unique_fallback_guide` | 全清单至多一个业务声明 `fallback_guide`，且双端可见 |
| `tests/ai/test_agent_runtime.py::test_decide_without_models_falls_back_to_capability_guide`（8 句参数化） | 都不命中恒落 capability / `routed_by="default"`（规则确已移除 + tutor 不再兜底） |
| `tests/ai/test_llm_routing.py` / `test_decision_model_routing.py` 兜底组 | provider 不可用 / 未配置 / 畸形 / 不可见业务 → capability / default |
| `tests/ai/test_runtime_abstractions.py::test_decide_prefers_declared_fallback_guide` | 声明业务优先于 priority 最小者（与数值无关） |
| 同文件 `test_decide_last_resort_falls_back_to_lowest_priority_business` / `test_decide_visible_set_bounds_fallback` | 无声明时的最后防线 + 可见集边界（声明业务不可见则跳过） |
| `tests/api/routes/test_assistant.py::test_student_tutor_ask_returns_answer_and_logs` | tutor 显式路由才落 TutorLog（不声明落点则进 capability） |
