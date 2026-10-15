# 00: 各 subagent manifest 写入 input_schema（已完成）

**What to build:** 在 5 个 subagent 的 `MANIFEST` 新增 `input_schema` 字段，作为各工具槽位定义的唯一事实源。question 10 槽（subject/grade/qtype 必填，余默认 + multi_subject），query 6 optional，tutor 4（question_text 必填），guide 3 optional，capability 空。

**Blocked by:** 无

**Status:** done

## 范围
- 非破坏性新增键：旧代码不读 `input_schema`，向后兼容。
- `enum_ref` 指向 `app.domain.subjects.SUBJECTS`（ADR-0055 §11 收敛为 数学/语文/英语）。
- 编号避让：ADR 原拟 0094，因并行会话已在每日日志取号 0094（genkit 主题）改 0095，manifest 注释同步。

## 验收
- [x] 5 个 manifest `py_compile` 通过。
- [x] import 校验：每个 manifest 的 `input_schema` 长度正确（question 10 / query 6 / tutor 4 / guide 3 / capability 0）。
- [x] `enum_ref` 全部指向 `app.domain.subjects.SUBJECTS`，无残留旧路径 `question.SUBJECTS`。

## 实施记录（2026-10-15，主线）
- 文件：`backend/app/ai/subagents/{question,query,tutor,guide,capability}/manifest.py`。
- 随 ADR-0095 一并写入；注释引用 ADR-0095。
- 下一步 frontier = T01（slot_filling 预检模块）。
