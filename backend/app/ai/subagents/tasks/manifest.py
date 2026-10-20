"""任务学情与出题域 SubAgent 清单（ADR-0097 / ADR-0098 / ADR-0104）。

ADR-0098：``question``（题库与出题）与 ``students``（人群）两个业务键并入本域，
执行体收敛为 tasks / tutor 两个。ADR-0104：规则（关键词 / 启发式）路由移除后，
业务选择由 LLM / 决策模型按「对话上下文 + 本清单的 name/description/actions」
决定，``triggers`` / ``hints`` / ``trigger_patterns`` / ``intent_schemas`` 整套
词表机器随之删除——不再有手写关键词分支，也没有「词序即子意图」的纪律。

``priority`` 现仅两处语义（ADR-0104）：策略原语均不决策时数值最小者作兜底助手
（tutor=-10 接住）；能力清单呈现顺序。故 14 只需高于 tutor，无需再压谁。

聊天链路的出题走**纯 LLM 自由文本生成**（ADR-0104：子意图选择随规则路由一并
移除）：``input_schema`` 全 optional，缺槽预检恒放行、不澄清、不发汇总帧；按规格
的结构化出题仍由 ``POST /tasks/generate``（``ctx.extra["specs"]``）承载。
"""
from __future__ import annotations

MANIFEST = {
    "business": "tasks",
    "name": "任务学情与出题助手",
    "description": (
        "查询任务 / 错题 / 进度 / 掌握度 / 待复习与学生名单（学生查自己）；"
        "按科目、年级、题型与数量生成题目题卡（含选项与解析）；"
        "教师还可管理题库（查询 / 归档 / 删除）并从题库组建草稿任务（确认后发布）。"
    ),
    "roles": ["teacher", "student"],
    # 路由优先级：规则移除后只需高于兜底助手 tutor(-10)；能力清单中排在 tutor 前。
    "priority": 14,
    # 结构化动作：「按规格出题」（等值匹配、不参与优先级竞争）。
    # 判断题闭环（出题-判定-讲解）已整体下沉到子代理（ADR-0089）：
    # 出题助手从自由文本/知识点上下文自主决定出 judge 规格题卡（含答案落历史），
    # 伴学答疑从历史读答案判定，不再经服务端 quiz_generate / quiz_judge 动作键。
    "actions": ["task_generate"],
    # 出题 SOP（自 question 域迁入）：适龄 / 对齐教材 / 题型约定 / 儿童安全闸门。
    "skills": ["question_sop"],
    # 输入 schema（ADR-0095）：本域槽位声明，全部 optional——聊天链路纯 LLM 生成
    # 不阻塞（ADR-0104）；必填性校验在工具层（create_draft 的目标学生由 handler
    # 校验，ToolArgumentError 回灌，模型转问用户）。
    "input_schema": [
        {"name": "subject", "type": "enum", "required": False, "default": "",
         "enum_ref": "app.domain.subjects.SUBJECTS", "source": "both"},
        {"name": "grade", "type": "int", "required": False, "min": 1, "max": 9, "source": "both"},
        {"name": "count", "type": "int", "required": False, "default": 3,
         "min": 1, "max": 10, "source": "text"},
    ],
}
