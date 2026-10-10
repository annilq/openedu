"""出题 SubAgent 清单（ADR-0024）。

business 即路由键；triggers 为意图路由规则匹配词；roles 限定可见角色
（师生均可出题：学生自练出题见 ADR-0081 §2.2，答案全量下发见 §2.8；
原题仅教师端的 ADR-0026 立场已被上述决策取代）。

与 ``query`` 的边界（ADR-0033 决策 6）：本业务触发器含泛词「题目」，凡带
「任务 / 作业 / 错题 / 复习」等查询语境的问句由 ``query``（priority=12）优先接住；
**「出题 / 来几道 / 生成题」才是本业务的意图**。
"""
from __future__ import annotations

MANIFEST = {
    "business": "question",
    "name": "出题助手",
    "description": "根据科目、年级、题型与数量生成题目题卡（含选项与解析）。",
    "roles": ["teacher", "student"],
    "triggers": [
        "出题", "出几道", "出道", "出题目", "来几道", "生成题", "题目",
        "测验", "考考", "练", "给我出", "帮我出",
    ],
    # 启发式兜底词（规则未命中时用，ADR-0030）
    "hints": [
        "出题", "出几道", "出道", "出道题目", "出题目", "题目", "测验",
        "考考", "练", "生成题", "来几道", "给我题",
    ],
    # 路由优先级：低于 query（"任务题目" 归 query，ADR-0033 决策 6），高于 tutor（兜底）
    "priority": 0,
    # 结构化动作：「哪个业务拥有哪个动作」的唯一声明处（ADR-0081 落地前置）。
    # 出题助手拥有「按规格出题」「换一题」「判断题出题」三个动作；等值匹配、不参与
    # 触发词优先级竞争。
    # - task_generate / task_question_regenerate：整卷出题 / 换一题。
    # - quiz_generate：判断题闭环的出题段（T07）——同走出题助手（拿检索/学科提示/溯源/
    #   工具信封），但由 assistant service 剥离答案、写待判定态。与课件练习出题的
    #   ``courseware_generate``（归 guide）是两个独立键，不得拍平。
    "actions": ["task_generate", "task_question_regenerate", "quiz_generate"],
    "skills": ["question_sop"],
}
