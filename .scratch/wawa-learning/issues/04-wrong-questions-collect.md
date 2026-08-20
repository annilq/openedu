# 04 — 错题自动归集

**What to build:** 娃娃答错时系统自动把该错题写入错题集（数据模型 + API），为二期复习打底。

**Blocked by:** 02 — Flutter MVP 全量：Clean Arch + Riverpod 落地

**Status:** ready-for-agent

- [x] 答错记录自动进入错题集，按 `child + question` 唯一，重复错不建多条（故事 13）
- [x] 提供家长/娃娃可查的错题列表接口
- [x] 错题归集有单测覆盖：正确作答不归集、答错归集、重复错不重复
