# 08 — IntentRouter + Tutor 领域服务

**What to build:** 新增 `domain/intent.py` 与 `domain/tutor.py`，含 `IntentRouter`（解释/生成/辅导分发）与 `Tutor`（适龄讲解）抽象 + 工厂，复用 `LLMProvider`；为三期伴学打底。

**Blocked by:** 03 — 可插拔 LLM 真接通 smoke

**Status:** ✅ done

- [x] `IntentRouter` 能按查询意图分发到对应能力（故事 19）
- [x] `Tutor` 经 `LLMProvider` 给出适龄讲解，接口契约明确（故事 18）
- [x] 意图路由与 Tutor 均有单测（fake provider 返回结构化结果）
- [x] 遵循 ADR-003：不重复封装 LangChain provider 抽象，仅封框架适配 + 领域接口

> 回填说明（2026-09-04）：功能已随三期落地。**结构偏差**：原 ticket 要求独立 `domain/intent.py` + `IntentRouter` 类，实际落地时意图分发（解释/生成/辅导）已并入 `domain/tutor.py` 的 `TutorService`（输入安全校验 → 知识库检索注入 → provider 讲解 → 输出安全校验），未单独建 `IntentRouter` 模块。功能等价覆盖 ADR-003，但与 ticket 描述不符。
> 后续建议：补一条 ADR 正式确认「意图路由并入 TutorService」的架构决策，或择机重构拆出 `IntentRouter` 以贴合原始设计（当前非阻塞）。
