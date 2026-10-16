# 03 · questions agent（题库 CRUD + 出题 tool）

## What to build

`app/ai/subagents/question/` 从约束解码 agent 改造为 tool loop agent（business 键保持 `question`，manifest name 改「题库与出题助手」）：

- **tools**：`list_bank_questions`（从 query 迁入，import 改 shared）、`create_question`、`update_question`、`delete_questions`、`archive_questions`（handler 调 `questions_service` + `core.guard`）、`generate_questions`（**流式 tool**，内部搬 `pipeline.py` 的 build_question_prompts + stream_question + translate_stream + 安全闸门 + 题卡 DATA 帧；specs 优先读 `ctx.extra["specs"]`）。
- **agent.py**：删约束解码 `run()` 主体，改 `initial_system` / `initial_user`（题库管理 SOP + 角色提示）；`tools` 装配 6 个；`requires_tool_data = True`；`render_tool_result` 保留卡片投影（list_bank → 题库卡；create/update → 题卡）。
- **manifest.py**：name 改「题库与出题助手」；description 反映题库管理；triggers 保留出题词表 + 加题库管理词（「题库」「我的题目」「删掉这几道题」…）；`input_schema` 不变（slot filling 分组键 `question` 不变）；`actions` 保持 `["task_generate"]`。
- **删除约束**：delete / archive 走确认卡模式（render_tool_result 发 `question_delete_confirm` DATA 帧？——否，删除确认沿用「先列后删」两步：模型先调 list_bank 展示，用户消息里明确「删掉第 1、3 道」再调 delete。SPEC §2.4 的起草-确认模式只用于 create_draft；题库删除靠两步 + 服务端 guard。验收里写清这条边界）。

## Blocked by

01（流式 tool）、02（shared）。

## 验收

- 出题流式体验不丢：THINKING 逐 token、题卡 DATA 帧、STEP 锚点照旧（widget/集成测试断言帧序列）。
- `ctx.extra["specs"]` 直达 handler：结构化规格路径（task_generate 动作直配）出题正常。
- 题库 CRUD：教师增/改/删/归档成功；学生端全部写工具 + list_bank 被拒（caller_role）。
- 契约测试 `task_generate → question` 绿；question 的 slot filling 集成测试绿。
