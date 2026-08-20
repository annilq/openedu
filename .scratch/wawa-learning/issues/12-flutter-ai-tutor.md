# 12 — Flutter AI 伴学模块

**What to build:** 在 App 中新增 `ai_tutor` feature：娃娃自然语言提问、看适龄讲解、违规内容转家长提示；受时长与内容范围管控。

**Blocked by:** 08 — IntentRouter + Tutor 领域服务, 09 — 内容安全层 + 家长 AI 日志, 10 — 每日 AI 时长与内容范围管控, 11 — 教材知识库 RAG 检索

**Status:** ready-for-agent

- [ ] 娃娃可提问并获得适龄讲解展示（故事 18）
- [ ] 被拦截的不安全内容对娃娃显示家长提示而非原文（故事 20/21）
- [ ] 受每日 AI 时长与内容范围约束（故事 23/26）
- [ ] 家长可在 App 查看 AI 交互日志（故事 22）
- [ ] notifier 状态机（Idle/Loading/Success/Error）有 mocktail 单测

