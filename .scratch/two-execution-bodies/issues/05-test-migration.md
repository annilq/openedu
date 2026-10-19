# 05 · 测试迁移

Blocked by: 03, 04

## 内容

- **路径迁移**：import `app.ai.subagents.question.*` 的测试改 `tasks.generation.*` /
  `tasks.tools.*`（test_generate_question / test_question_figure_options /
  test_generate_question_stream / test_translate / test_question_semester /
  test_quiz_loop / test_subagents_seam / test_runtime_abstractions /
  test_business_tools_contract）。
- **business 键迁移**：路由回归表 / capability 清单 / assistant API 打桩里的
  `question` → `tasks`；`tests/features/tasks/test_service.py` 的
  `business="question"` 断言 → `"tasks"`。
- **改名**：`test_question_subagent_stream.py` → `test_tasks_generation_stream.py`
  （流式出题契约，断言不变，仅 import 与命名）。
- **slot filling 测试**：`_question_schema()` 改为从 tasks manifest 的
  `intent_schemas.generate` 取；`test_non_question_businesses_never_clarify` 参数表
  改 business；多轮澄清 / 汇总帧 / 回放气泡断言不变。
- **契约测试**：`test_business_tools_contract` 期望工具集 = 12（tasks 域全集）；
  parent-only 豁免集不变（题库三件 + create_draft 拒学生）。
- **students 测试**：`test_students_subagent.py` 已随 01 票并入 tasks 测试。

## 验收

全量 pytest 与基线等价（976 passed + materials 环境性红，零新增红）。
