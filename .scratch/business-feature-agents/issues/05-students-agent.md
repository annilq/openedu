# 05 · students agent（人群域）

## What to build

新建 `app/ai/subagents/students/`：

- **tool**：`list_students`（从 query 迁入，import 改 shared）。
- **agent.py**：tool loop agent（单工具）；`initial_system` 简短（人群查询 SOP：教师=名下全部，学生=自己，仅用于定位与「有哪些学生」类问题）；`requires_tool_data = True`。
- **manifest.py**：business `students`；triggers（「哪些学生」「我班」「名下」「孩子们」…）；priority 10；roles 双端；无 input_schema（无槽）。
- classes 域**不进 AI**（SPEC Out of Scope：重表单管理，AI 价值低）。

## Blocked by

02（shared）。

## 验收

- 「我班有哪些学生」路由 students；学生端问同样问题返回自己。
- 契约测试回归表含 students 行。
