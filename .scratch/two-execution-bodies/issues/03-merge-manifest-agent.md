# 03 · manifest/agent 合并 + 删 question/

Blocked by: 02

## 内容

- **tasks/manifest.py**：
  - name 改「任务学情与出题助手」；description 改双域表述（进 capability 清单，角色须准确）。
  - triggers = 两域并集（出题词原样并入；「题目」「题库」等与学情词无竞争的保留）。
  - `actions: ["task_generate"]`（自 question 移入）；`skills: ["question_sop"]`。
  - priority 保持 14；hints 并集。
  - `input_schema` 保持 tasks 全 optional 版；新增 `intent_schemas.generate`
    （triggers 子集 + question 原 schema）。
- **tasks/agent.py**：
  - tools = TASKS_TOOLS + questions_tools（12）；`_SYSTEM` 两套规则取并集去重
    （「只依据工具数据」「昵称直接查明细」各留一份），补出题规则（收尾话术据计数 /
    多学科列各科 / 题库两步模式）与创建草稿规则；role hints 合并（学生端：只能看自己 +
    可出题自练 + 不给答案解析）。
  - `render_tool_result` 保留 create_draft 确认卡特判 + render_cards 兜底。
  - 删除文件内指向 students 域的悬空注释（ADR-0097 遗留）。
- **删 `question/`**（agent/manifest/__init__）；`subagents/__init__.py` 去导出。
- **service.py**：`generate_task_stream` 的 `business="question"` → `"tasks"`；
  follow-up chips 的 `question` 组并入 `tasks` 组（保留「再出几道 / 降低难度 / 讲解这道题」
  中有价值的），删 `question` 键；注释口径更新。

## 验收

- discover 恰 3 manifest；`POST /tasks/generate` 测试转绿（business 断言已迁）。
- capability 双端清单：tasks 条目为双域描述；清单共 2 条（tasks / tutor）。
