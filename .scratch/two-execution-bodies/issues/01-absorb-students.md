# 01 · students → tasks 吸收

Blocked by: —

## 内容

- `students/tools/list_students.py` git mv 至 `tasks/tools/`；`TASKS_TOOLS` 追加该工具。
- tasks manifest triggers 追加名单精确短语（「有哪些学生」「我班」「班里」「多少个学生」等，
  自 students triggers 选不泛的）；hints 不加「学生」类泛词。
- 删 `students/` 目录；`subagents/__init__.py` 去导出。
- `tests/ai/test_students_subagent.py` 内容并入 tasks 域测试（形状断言保留：单工具清单、
  路由边界），原文件删。

## 验收

- discover 恰 4 manifest（capability/tasks/question/tutor）。
- 「有哪些学生」「我班里有几个娃」路由 tasks；「小明最近怎么样」仍 tasks（聚合问题不被
  名单词表抢走的行为在合并后自然成立，无竞争）。
