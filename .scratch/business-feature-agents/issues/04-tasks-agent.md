# 04 · tasks agent（学情域读写）

## What to build

新建 `app/ai/subagents/tasks/`：

- **读 tools**（从 query 迁入，import 改 shared）：`list_teacher_tasks`、`list_today_tasks`、`list_wrong_questions`、`get_progress`、`list_due_reviews`、`get_mastery`。
- **写 tool**：`create_draft`——handler 调 `tasks_service` 的 from-bank 路径（题库选题组草稿，draft 态不派发）；参数：subject/grade/count/student_target（学生 id 或姓名，缺省=教师名下全部？不——create_draft 必须显式目标学生或班级，防误派发。验收钉死：无目标学生时工具报错要求指明）。
- **agent.py**：tool loop agent；`initial_system` 合并学情查询 SOP（原 query 的 `_SYSTEM` + 角色提示）与任务起草 SOP；`requires_tool_data = True`；`render_tool_result`：读工具卡片投影（从 query/render.py 迁入对应分支）+ `create_draft` 发 `task_draft_card` DATA 帧（`{task_id, title, subject, grade, question_count, students}`）。
- **manifest.py**：business `tasks`；triggers = guide 写意图词表（「创建任务 / 布置作业 / 派发…」完整短语）+ 学情查询词（「任务」「作业」「错题」「进度」「掌握度」「复习」）；priority 14；roles 双端（学生端写工具在 handler 内拒）；`input_schema` 轻量（subject/grade/count，source both，读不阻塞——注意：读操作轮预检不追问，只有写意图轮追问。实现方式：预检层怎么知道是写意图？——由 manifest input_schema 的 required 声明 + 本轮是否命中写触发器决定。简化方案：tasks 的 input_schema 全部 optional（读不阻塞），create_draft 的必填槽由 handler 校验并以 ToolArgumentError 回灌，模型转问用户。**这是确定性的边界**：槽位追问发生在 handler-模型回路里，不是预检层。验收写清）。

## Blocked by

02（shared）。

## 验收

- 「我有哪些任务」「今天有什么作业」「小明错题多吗」「小明的掌握度」路由 tasks 且工具数据有据（requires_tool_data 硬失败守编造）。
- 「创建任务」路由 tasks（priority 14 压过 question 12）；缺目标学生 → handler 报错 → 模型转问；create_draft 成功 → `task_draft_card` 帧 + 草稿落库（draft 态）。
- 学生端：读工具只返回自己数据；create_draft 被拒。
- guide 词表迁入后，「创建一个任务，包含四年级数学题」不再落到固定话术。
