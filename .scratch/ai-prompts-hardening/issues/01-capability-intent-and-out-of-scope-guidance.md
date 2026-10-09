# 01: 能力自述与超范围引导（capability 意图 + 服务端固定目录）

**What to build:** 当用户问「你能做什么 / 你会什么 / 怎么用 / 有什么功能」或问出明显超出助手范围的问题时，助手**主动说明自己的职责边界并给出一个可点方向**。做法是新增一个**零 LLM 的 `capability` 意图**（`business="capability"`），命中即返回**服务端固定常量文本 + 受控能力卡**，不再落进 tutor 的泛兜底、也不再被 `query.requires_tool_data=True` 硬失败。同时在 `tutor_system_prompt` 末尾补**一句**「超出范围时用一句话说明你能做什么，并给出一个可点方向」，让 tutor 偶发接住的超范围问题也能自我说明。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

## 为什么（Round 1–2 核实结论）
- 路由兜底 = `tutor`（`priority=-10`，`tutor/manifest.py:19`），认不出意图的问题全落 tutor；`tutor_system_prompt`（`domain/safety.py:46`）只有「与学习无关请温和引导回学习主题」——**有拉回、无能力清单**。
- `query` 的 `_SYSTEM` 明确写了「与学情无关的请求直接说明你能查什么」（`query/agent.py:40`），**但** `requires_tool_data=True`（`query/agent.py:56`，注释自认）会把这类零工具回答**硬失败** → 指令与结构互相打架。
- 结论：**从根上把这类问题从 `query` 手里接走**（新增独立意图），而不是放宽 `requires_tool_data`（那会重新打开「模型编造数字」的口子）。

## 设计（待用户确认的取舍已内联标注）
1. **载体 = 新 subagent `capability`**（`app/ai/subagents/capability/`）：`manifest` + `agent`，`roles=["teacher","student"]`，**不声明 tools**（走 BaseSubAgent 默认路径，`run` 直接 yield 固定事件序列：`run_started → assistant_message(文本) → data_event(能力卡) → done`），**全程零 provider 调用**。
   - *为何不用 service 里的确定性分支（如 `req.quiz` 那种）*：路由词表应单一事实源（ADR-0030/0054），放 manifest 才与其它意图一致；quiz 分支是「结构化标记」而非「自由文本意图」，不能照搬。
2. **路由优先级**：`capability` 给 **16**（`query=12 < capability=16 < guide=20`）。理由：必须压过 query 的泛词 `查/有哪些`，又不能抢 guide 的写意图（guide 的 triggers 是「创建任务」等高精度短语，不冲突）。
3. **triggers（只收完整短语，避免泛词）**：`你能做什么` / `你会什么` / `你能帮我什么` / `你有什么功能` / `有什么功能` / `怎么用你` / `你是谁` / `你是什么` / `你能干什么`。`hints` 留空（与 guide 同策略：高精度优先，宁可漏给 tutor 也不误抢）。
4. **能力清单 = 纯函数目录**（与 `build_suggested_actions` 同源风格）：`capability_catalog(role) -> list[str]`，按角色分叉——
   - 学生：「讲解不会的知识点」「按知识点出练习题」「帮你复习错题 / 看待复习」「分析你的掌握度与学习进度」；
   - 教师：「查学情（任务 / 错题 / 掌握度 / 进度）」「引导你发布任务」「围绕某个知识点讲解 / 出题」。
   文本前缀一句职责边界：「我只做学习相关的事，不能改数据、不能代做题。」
5. **能力卡**：v1 优先**纯文本 + 复用既有 `list` 卡渲染器**（`assistant_cards.dart` 已有 `AssistantListCard`），做到**前端零改动**、纯后端可测；若要做成 guide 式专属卡（`AssistantCardKind.capability`）则属增强，另拆。
6. **`tutor_system_prompt` 补一句**：仅加「若问题超出学习范围，用一句话说明你能做什么，并给出一个下一步方向」，**不列具体能力**（清单在 capability 目录，单一事实源）。⚠️ 这是安全锁文件，改动须保持「按 grade/subject 生成」的签名不变。

## 验收清单
- [ ] 学生/教师各问「你能做什么」→ 路由命中 `capability`（**不是** tutor / query），回复含职责边界 + 对应角色的能力清单，**无 LLM 调用**（断言 provider 未被调用）
- [ ] 教师说「帮我创建一个任务」仍命中 `guide`（priority 20），未被 capability 抢走
- [ ] 「查一下我的错题」仍命中 `query`，未被 capability 抢走
- [ ] 明显超范围（如「今天天气怎么样」）→ 落 tutor 但**不硬失败**，回复含一句「我能做什么」+ 一个可点方向
- [ ] `tutor_system_prompt` 仍随 `(grade, subject)` 生成（签名/调用点未变），新增句为常量尾句
- [ ] 能力清单为**服务端常量**，不经 LLM 生成；`_SYSTEM`/目录无重复词条（单一事实源）
- [ ] `tests/ai/` 全绿（改 `features/*/service.py` 若触及）；新增 `capability` 单测 + 路由优先级用例
- [ ] 分层不变量 9：capability 的 `run` 不触碰任何归属判定/ORM

**决策锚点：** ADR-0079；`requires_tool_data` **不放宽**（安全优先）；优先级 16；能力卡 v1 复用 `list` 渲染器。
