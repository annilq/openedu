# 08 — IntentRouter + Tutor 领域服务

**What to build:** 新增 `domain/intent.py` 与 `domain/tutor.py`，含 `IntentRouter`（解释/生成/辅导分发）与 `Tutor`（适龄讲解）抽象 + 工厂，复用 `LLMProvider`；为三期伴学打底。

**Blocked by:** 03 — 可插拔 LLM 真接通 smoke

**Status:** ready-for-agent

- [ ] `IntentRouter` 能按查询意图分发到对应能力（故事 19）
- [ ] `Tutor` 经 `LLMProvider` 给出适龄讲解，接口契约明确（故事 18）
- [ ] 意图路由与 Tutor 均有单测（fake provider 返回结构化结果）
- [ ] 遵循 ADR-003：不重复封装 LangChain provider 抽象，仅封框架适配 + 领域接口
