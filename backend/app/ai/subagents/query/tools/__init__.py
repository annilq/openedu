"""``query`` SubAgent 的查询工具集（ADR-0033）。

7 个**只读**工具，覆盖「家长查学情」与「娃娃查今天」的全部场景：

| 工具 | 作用 |
|---|---|
| ``list_children`` | 孩子列表（家长名下全部 / 娃娃自己） |
| ``list_parent_tasks`` | 任务清单（家长发布 / 娃娃今日） |
| ``list_today_tasks`` | 今日任务 |
| ``list_wrong_questions`` | 错题本（娃娃端自动去答案） |
| ``list_due_reviews`` | 遗忘曲线到期复习队列 |
| ``get_progress`` | 学习进度概况 |
| ``get_mastery`` | 知识点掌握度看板 |

工具一律**只读**（不写库）、复用 ``features/<x>/service.py`` 的业务口径
（不直连 repository，更不 import router——分层不变量守护），出参统一过
``_shared.project_for_role`` 裁剪。

本包 ``__init__`` 刻意不导入 ``registry``：工具模块本身是被汇总方，
在此处提前 import 会形成包级循环。
"""
