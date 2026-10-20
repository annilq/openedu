# T01 — 删除 question/students 空壳目录 + 陈旧「question subagent」字符串（候选 5）

**What to build:** 把 ADR-0098 收敛二执行体时遗留的死代码彻底清掉。`app/ai/subagents/question/` 与 `app/ai/subagents/students/` 的源 `.py` 已被 ADR-0098 删除，现仅剩空 `__init__.py` + 陈旧 `__pycache__/*.pyc` 字节码壳；另有 3 处文档/测试字符串仍写「question subagent」，但 business 键早已是 `tasks`。删壳、改字符串，使仓库与 `tasks` 业务键一致。

**Blocked by:** 无（可立即开工）
**Status:** ready-for-agent

## 决策锚点

- 本次是**纯删除**，零行为变化：空壳目录无任何 import（已 `grep` 确认 `subagents.question`/`subagents.students` 全仓零引用），删掉不影响任何一次运行。
- 3 处字符串是「过时命名」而非「不同概念」：它们指的就是现在的 `tasks` subagent 流式题卡，统一改成「tasks subagent」即可，不要新造术语。
- 删除 `__pycache__/*.pyc` 是清理 stale 字节码，CI 重跑会重生，不影响。

## 验收

- [ ] `app/ai/subagents/question/` 与 `app/ai/subagents/students/` 目录（含其 `__pycache__`）已从工作区删除
- [ ] 全仓 `grep -rn "question subagent"` 归零（`app/features/tasks/router.py:81`、`app/features/tasks/schemas.py:63`、`tests/api/routes/test_tasks_generate.py:5` 三处改为 `tasks subagent` 或等价表述）
- [ ] `grep -rn "subagents.question\|subagents.students"` 全仓无引用（删除前本就为零，确认未因改名引入）
- [ ] 全量后端 `pytest` 绿；`ruff` 改动文件净
