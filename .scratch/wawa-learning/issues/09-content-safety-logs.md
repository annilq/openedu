# 09 — 内容安全层 + 家长 AI 日志

**What to build:** 所有 AI 输出经 `SafetyGuard` 双层防护；越狱/不安全响应拦截并转家长；家长可查全部 AI 交互日志。

**Blocked by:** 08 — IntentRouter + Tutor 领域服务

**Status:** ready-for-agent

- [ ] 所有 AI 输出经 `SafetyGuard`，越轨内容不显示给娃娃而转家长（故事 20/21）
- [ ] AI 交互（query/response/是否被拦截）写入日志且家长可查（故事 22）
- [ ] 安全层有单测覆盖拦截与放行路径
- [ ] 安全规则作为非功能约束写入实现，对应 ADR 内容安全条目
