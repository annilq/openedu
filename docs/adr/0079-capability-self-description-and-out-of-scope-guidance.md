# ADR-0079 能力自述与超范围引导：capability 意图 + 服务端固定目录

- 状态：提案（待评审）
- 日期：2026-10-10
- 关联：ADR-0024/0025/0026（悬浮助手与路由）、ADR-0030（启发式兜底 + priority 即路由权重）、ADR-0033（query 只读工具与 `requires_tool_data`）、ADR-0042（受控动作枚举 / 卡片契约）、ADR-0054（路由优先级即功能）、ADR-0072（推荐操作目录）

## 1. 背景（Context）

用户问「你能做什么」时，助手答不上来，甚至可能答不出来直接失败。读码核实（非凭记忆）：

1. **没有能力自述**：路由兜底是 `tutor`（`tutor/manifest.py:19` `priority=-10`），任何认不出意图的问题都落到它，`tutor_system_prompt`（`domain/safety.py:46`）只有一句「与学习无关请温和引导回学习主题」——**有拉回，无能力清单**，用户不知道助手边界在哪。
2. **唯一写了能力自述的地方反而会硬失败**：`query` 的 `_SYSTEM` 明确要求「与学情数据无关的请求……直接说明你能查什么」（`query/agent.py:40`），但同一文件 `requires_tool_data = True`（`query/agent.py:56`，注释自认）规定「整轮零工具调用却给出正文＝模型在编」，由 runtime 硬失败拦截。**指令与结构互相打架**：能力说明本身就是「不查就答」，必被拦。
3. **`requires_tool_data` 不能放宽**：它的存在是为了挡住本地小模型在流式下编造「3 个学生 / 掌握度 85%」（真机实测）。放宽等于重新打开编造口子。

结论：与其让 `query` 破例，不如**把「你能做什么」这类元问题从 `query` 手里整个接走**，交到一个**只读、零 LLM、可控**的专门意图。

## 2. 决策（Decision）

### 2.1 新增 `capability` 意图（零 LLM 的专门 subagent）

- 新建 subagent `capability`（`app/ai/subagents/capability/`）：`business="capability"`，`roles=["teacher","student"]`，**不声明 tools**，`run` 直接产出固定事件序列（`run_started → assistant_message(文本) → data_event(能力卡) → done`），**全程零 provider 调用**。
- 能力文本与能力清单为**服务端常量**（纯函数，按角色分叉），**非 LLM 生成**——与 ADR-0072 推荐操作目录同一原则。
- 文本含一句**职责边界**：「我只做学习相关的事，不能改数据、不能代做题。」

### 2.2 路由优先级 16（压过 query，不抢 guide）

- `capability=16`：`query=12 < capability=16 < guide=20`。必须压过 `query` 的泛词（`查` / `有哪些`），又不能抢 `guide`（写意图，triggers 为高精度短语）。
- `triggers` 只收完整短语（`你能做什么` / `你会什么` / `你有什么功能` / `怎么用你` / `你是谁` …），`hints` **留空**——与 `guide` 同策略，高精度优先，宁可漏给 `tutor` 也不误抢查询/写意图。

### 2.3 超范围问题由 tutor 补一句自我说明

- `tutor_system_prompt` 末尾**补一句常量**：「若问题超出学习范围，用一句话说明你能做什么，并给出一个下一步方向。」**不列具体能力**（清单在 capability 目录，单一事实源）。
- ⚠️ `tutor_system_prompt` 是**安全锁**（按 `grade/subject` 生成），改动必须保持签名与调用点不变，且不得混入业务焦点（知识点聚焦是 ADR-0080 的独立注入段）。

### 2.4 能力卡 v1 复用既有渲染器

- v1 输出「文本 + `list` 卡」（`assistant_cards.dart` 已有 `AssistantListCard`），**前端零改动、纯后端可测**。
- 专属 `capability` 卡种属增强，另拆。

## 3. 后果（Consequences）

- 「你能做什么」不再落 `tutor` 泛兜底、不再被 `query` 硬失败；用户能立刻看清助手边界并获得可点方向。
- `query` 的 `requires_tool_data=True` **保持不变**（安全优先），冲突通过「接走」而非「放宽」解决。
- 新增一处路由词表，须与 `query`/`guide` 的 triggers 保持互斥（测试守护：写意图/查询意图不被 capability 抢走）。
- 用户放行后实现，落到 ticket `.scratch/ai-prompts-hardening/issues/01-*.md`。

## 4. 备选（Considered Options）

- **放宽 `query.requires_tool_data`**：否决。会重新打开模型编造数字的口子（安全优先）。
- **在 `service.chat` 做确定性关键词分支（照 `req.quiz`）**：否决。`quiz` 是「结构化标记」而非自由文本意图；路由词表应单一事实源在 manifest（ADR-0030/0054），散到 service 会与其它意图不一致。
- **让 LLM 自由自述能力**：否决。能力清单是编译期常量，不该由模型发挥（与 ADR-0042/0054 一致）。
