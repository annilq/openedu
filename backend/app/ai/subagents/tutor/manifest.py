"""伴学 SubAgent 清单（ADR-0024 / ADR-0104 / ADR-0105）。

双端通用（roles: teacher + student，ADR-0026）：学生端只暴露伴学答疑，不暴露出题/答案。
ADR-0104：规则（关键词 / 启发式）路由移除后，业务选择由 LLM / 决策模型按上下文 +
能力清单决定，``triggers`` / ``hints`` 词表删除。ADR-0105：本业务**不再作兜底**——
必须被模型显式路由到；``priority=-10`` 仅表示能力清单里排在末位。
"""
from __future__ import annotations

MANIFEST = {
    "business": "tutor",
    "name": "伴学答疑",
    "description": "针对学生的提问给出适龄、纯学习相关的讲解。",
    # 路由专用描述（ADR-0106 / ticket 12 实测调优）：原 description 里的「提问」是万能
    # 吸引子——实测把「我班有哪些学生 / 学习进度怎么样」这类查数据请求也吸到伴学；
    # 换成「讲题与答疑：讲清某道题怎么做、为什么是这个答案」后，讲解类用例回归。
    # 实测过的教训：加「解释知识点」会多错两条（T13/T14）、加「怎么算」会换来
    # 高置信错误减少但讲解续接变坏；当前这句是 34 条用例上的最优（74% / 有效 71%）。
    "routing_criteria": "讲题与答疑：讲清某道题怎么做、为什么是这个答案。",
    "roles": ["teacher", "student"],
    # 清单呈现顺序：排在 tasks(14) 之后。ADR-0105 起不再有「兜底助手」语义——
    # 都没有命中时回落的是声明了 fallback_guide 的 capability（能力引导）。
    "priority": -10,
    # 结构化动作：伴学答疑不再声明任何动作键（ADR-0089）。课件提示由 courseware 上下文
    # 触发、判断题判定由对话历史里的题卡驱动，均不经服务端动作键与待判定态。
    "actions": [],
    "skills": ["tutor_sop"],
    # 输入 schema（ADR-0095）：伴学答疑的核心输入就是用户消息本身（question_text）。
    # subject/grade/knowledge_point 为 optional，命中上下文（课件/知识点下钻）即补全，不追问。
    "input_schema": [
        # question_text 刻意**非必填**：用户消息本身就是这个问题（自由问答不该被追问
        # 打断），且引擎按设计不回填 string 的自由文本槽——若标 required，任何伴学
        # 提问都会恒被追问「你想问什么？」，与 ADR-0095 §2.4「tutor 不阻塞」冲突。
        {"name": "question_text", "type": "string", "required": False,
         "prompt": "你想问什么？（把问题发给我）", "source": "text"},
        {"name": "subject", "type": "enum", "required": False,
         "enum_ref": "app.domain.subjects.SUBJECTS", "source": "both"},
        {"name": "grade", "type": "int", "required": False, "min": 1, "max": 9, "source": "both"},
        {"name": "knowledge_point", "type": "string", "required": False, "source": "both"},
    ],
}
