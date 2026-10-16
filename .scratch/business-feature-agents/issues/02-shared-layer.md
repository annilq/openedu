# 02 · shared 层迁移

## What to build

`app/ai/subagents/query/tools/_shared.py`（282 行）整体迁至 `app/ai/shared/`，按内容重组：

- `envelope` / `student_block` / `dump`：学生分块信封（跨域学情查询统一形状）。
- `project_for_role`：角色裁剪（答案/解析剥离，ADR-0033）。
- `resolve_students` / `resolve_teacher` / `student_meta` / `caller_role`：定位与角色工具。
- `LOCATOR_PROPS` / `optional_str` / `optional_int` / `ToolArgumentError` / `NO_FILTER`：schema 与参数归一。

模块命名去掉 query 字样（如 `app/ai/shared/query_support.py` 或按职责拆两三个文件，≤400 行/文件）。**不进 `agent_core`**（零业务依赖纪律）。

## Blocked by

01（无硬依赖，仅同批开工避免 import 翻修两轮）。

## 验收

- 迁移后 `query/tools/` 的 import 改为 `app.ai.shared.*`；`app/ai/shared/` 无 `agent_core` 反向依赖之外的业务耦合。
- 既有 `_shared` 相关测试（若有）随迁或更新；`tests/ai/` 分层不变量测试绿。
