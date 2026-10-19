"""题库与出题 SubAgent 清单（ADR-0024 / ADR-0097）。

business 即路由键；triggers 为意图路由规则匹配词；roles 限定可见角色
（师生均可出题：学生自练出题见 ADR-0081 §2.2；题库管理仅教师——工具 handler
按角色拒绝，与 REST 同源）。

ADR-0097 起本业务的语义从「出题」扩大为「题库与出题」：执行模型由约束解码
改为 tool loop（出题降级为流式 tool），priority 从 0 提到 12——原 query(12)
解散后由 tasks(14) 接学情查询，本业务接出题与题库管理。
"""
from __future__ import annotations

MANIFEST = {
    "business": "question",
    "name": "题库与出题助手",
    "description": (
        "按科目、年级、题型与数量生成题目题卡（含选项与解析）；"
        "教师还可查询 / 归档 / 删除自己的题库。"
    ),
    "roles": ["teacher", "student"],
    "triggers": [
        "出题", "出几道", "出道", "出题目", "来几道", "生成题",
        "测验", "考考", "给我出", "帮我出",
        # ADR-0089：判断题闭环改由出题子代理自主驱动，「判断题」是出题意图（文本路由），
        # 不再经 quiz_generate 动作键。
        "判断题",
        # ADR-0097：题库管理词（查询 + 归档/删除两步模式）。
        "题库", "我有哪些题", "收起来", "归档", "删掉这几道", "删除题目",
    ],
    # 启发式兜底词（规则未命中时用，ADR-0030）
    "hints": [
        "出题", "出几道", "出道", "出道题目", "出题目", "测验",
        "考考", "生成题", "来几道", "来几道题", "练习题", "给我题", "判断题", "题库",
    ],
    # 路由优先级：低于 tasks(14，学情查询与写意图)，高于 students(10)。
    "priority": 12,
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
