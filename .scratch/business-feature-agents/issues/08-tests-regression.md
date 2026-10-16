# 08 · 测试与全量回归

## What to build

- agent_core 流式 tool 单测（01 已随票带，此票补集成面）。
- 三域 agent 测试：路由回归表（新优先级）、角色可见性、写工具学生端拒绝、create_draft 草稿态、generate_questions 流式帧序列。
- 删 query/guide 后的契约测试更新（06 已随票带）。
- 前端：确认卡 widget 测试（07 已随票带）；assistant 相关既有测试对齐。
- 实测各域 schema 上下文体量，更新 INDEX.md 基线数字。
- 全量回归：后端 pytest（`--basetemp=/tmp/<新>`）+ 前端 flutter analyze / test。

## Blocked by

01–07。

## 验收

- 后端全量 passed 数 ≥ 954，新增失败 0；既有红仅 `test_empty_text_422` 一条。
- 前端 analyze No issues found；全量 passed ≥ 687，既有红仅 file_size_guard 一条。
- INDEX.md 基线数字更新为实测值。
