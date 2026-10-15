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
        # ADR-0089：判断题闭环改由出题子代理自主驱动，「判断题」是出题意图（文本路由），
        # 不再经 quiz_generate 动作键。
        "判断题",
    ],
    # 启发式兜底词（规则未命中时用，ADR-0030）
    "hints": [
        "出题", "出几道", "出道", "出道题目", "出题目", "题目", "测验",
        "考考", "练", "生成题", "来几道", "给我题", "判断题",
    ],
    # 路由优先级：低于 query（"任务题目" 归 query，ADR-0033 决策 6），高于 tutor（兜底）
    "priority": 0,
    # 结构化动作：「哪个业务拥有哪个动作」的唯一声明处（ADR-0081 落地前置）。
    # 出题助手仅声明「按规格出题」动作（等值匹配、不参与触发词优先级竞争）。
    # 判断题闭环（出题-判定-讲解）已整体下沉到子代理（ADR-0089）：出题助手从自由文本/
    # 知识点上下文自主决定出 judge 规格题卡（含答案落历史），伴学答疑从历史读答案判定，
    # 不再经服务端 quiz_generate / quiz_judge 动作键与待判定态。
    "actions": ["task_generate"],
    "skills": ["question_sop"],
    # 输入 schema（ADR-0095）：出题所需槽位唯一事实源。required=True 的槽缺失时阻塞追问；
    # enum_ref 引用 app.domain.subjects.SUBJECTS（ADR-0055 §11 收敛为数学/语文/英语），
    # 由 slot_filling 载入时解析，避免选项重复漂移。
    "input_schema": [
        {"name": "subject", "type": "enum", "required": True,
         "prompt": "请问要出哪个科目？", "enum_ref": "app.domain.subjects.SUBJECTS", "source": "both"},
        {"name": "grade", "type": "int", "required": True,
         "prompt": "几年级？（1-9）", "min": 1, "max": 9, "source": "both"},
        {"name": "qtype", "type": "enum", "required": True,
         "prompt": "要什么题型（选择/填空/计算/解答）？",
         "enum": ["choice", "fill", "calc", "open"], "source": "text"},
        {"name": "count", "type": "int", "required": False, "default": 1,
         "min": 1, "max": 5, "source": "text"},
        {"name": "knowledge_point", "type": "string", "required": False, "default": "",
         "prompt": "有指定的知识点吗？（可留空按教材随机）", "source": "both"},
        {"name": "difficulty", "type": "enum", "required": False, "default": "medium",
         "enum": ["easy", "medium", "hard"], "source": "text"},
        {"name": "semester", "type": "enum", "required": False, "default": "",
         "enum": ["", "上", "下"], "source": "text"},
        {"name": "multi", "type": "bool", "required": False, "default": False, "source": "text"},
        {"name": "judge", "type": "bool", "required": False, "default": False, "source": "text"},
        {"name": "multi_subject", "type": "bool", "required": False, "default": False,
         "prompt": "是否需要多学科组卷？（是则按科目分别出题）", "source": "text"},
    ],
}
