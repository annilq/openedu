# 03: home_notifier 改经 assistant provider 层

**What to build:** home 的会话状态读取不再穿透到 assistant 的 domain 层；改为只依赖 assistant 暴露的 provider（Riverpod）。修复层违规（方向合法、层不对）。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `home_notifier` 不再 import `features/assistant/domain/*`（或任何 assistant 内部非 provider 层符号）。
- [ ] `home_notifier` 只通过 assistant 的 provider（如 `assistantNotifierProvider`）读取所需状态。
- [ ] `flutter analyze` 通过；home 功能区行为不变（教师大盘 AI 入口状态仍正确）。

_— 定位（volatile，仅供本次实施）—_
- `frontend/lib/features/home/presentation/providers/home_notifier.dart:6-8` 直连 `assistant/domain`
