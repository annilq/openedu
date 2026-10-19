# 02 · question 模块搬迁

Blocked by: 01

## 内容

- `question/tools/{generate_questions,list_bank_questions,archive_questions,delete_questions}.py`
  git mv 至 `tasks/tools/`；tools 的 import 从 `question.pipeline/specs/translate` 改指
  `tasks.generation.*`。
- `question/{specs,pipeline,translate,parsers}.py` git mv 至 `tasks/generation/`（新建
  `__init__.py` 再导出原公开名，保持 `from ... import X` 面不变）。
- `question/skills/question_sop.md` git mv 至 `tasks/skills/`。
- `app/ai/__init__.py` 的公共导出（`generate_question` / `QuestionSchema`）改从
  `tasks.generation` 再导出，外部 import 面零迁移。
- `app/domain/spec_keywords.py`、`app/domain/prompts.py`、`app/ai/subagents/question/
  pipeline.py` 文档串里的路径引用同步改。
- 本票**不删** `question/`（agent/manifest 还在），question agent 改为从新路径 import，
  保持全绿。

## 验收

- 全量 pytest 与基线等价（零新增红）；`python -c "from app.ai import generate_question"` 通。
