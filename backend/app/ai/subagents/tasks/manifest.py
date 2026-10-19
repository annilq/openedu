"""任务学情与出题域 SubAgent 清单（ADR-0097 / ADR-0098）。

ADR-0098：``question``（题库与出题）与 ``students``（人群）两个业务键并入本域，
执行体收敛为 tasks / tutor 两个。triggers 是三段并集：

1. **写意图词表**（自 guide 迁入）：「创建 / 布置 / 派发 / 添加任务」类完整短语。
2. **学情与名单词**（自 query / students 迁入）：「任务 / 错题 / 进度 / 复习」+
   「有哪些学生 / 我班 / 班里」等纯人群短语。
3. **出题与题库词**（自 question 迁入）：「出题 / 出几道 / 判断题 / 题库」等。

**词表纪律**（沿袭三方针）：路由是「词是否被包含」的匹配，泛词（``创建`` /
``建`` / ``任务``）会把「查一下我创建过的任务」也拽过来；写意图只收
「动作 + 对象」的完整短语。``hints`` 收查询语境词——启发式兜底只给查询
意图，写意图不兜底（宁可漏给下游也不误抢）。

**词序即子意图**（ADR-0098 §2.3）：``_rule_match`` 返回首个命中的触发词，
预检据此分子意图。故「任务题目」必须排在「题目」之前（学情查询报学情词、
不落进出题槽位组），出题的多个具体短语必须排在裸词「题目」「练」之前。
该不变量由契约测试守护（见 tests/ai/test_intent_routing_contract.py）。
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
    "triggers": [
        # 写意图（自 guide 迁入）：完整短语，防泛词误抢查询
        "创建任务", "创建一个任务", "创建个任务", "创建一份任务", "创建新的任务",
        "新建任务", "新建一个任务", "新建个任务",
        "建个任务", "建一个任务",
        "创建作业", "新建作业", "建个作业", "建一个作业",
        "布置任务", "布置作业", "布置一下",
        "派发任务", "派发作业", "帮我派发",
        "添加任务", "加个任务", "加一个任务",
        # 学情查询（自 query 迁入；main 侧错题短语并入）。
        # 「任务题目」须早于下方「题目」命中——学情查询报学情词，不进出题槽位组
        # （intent_schemas 的词序依赖）。具体短语排在裸词「错题」前，与出题段同理。
        "任务", "作业",
        "哪些错题", "错题有哪些", "错题情况", "错题",
        "错了哪些", "错过的题", "哪些题错",
        "进度", "掌握度", "复习", "待复习", "薄弱", "打卡",
        "学得怎么样", "学习情况", "学情", "今日任务", "我的任务", "任务题目",
        # 学生名单（自 students 域吸收，ADR-0098）：纯人群短语
        "哪些学生", "有哪些学生", "我的学生", "几个娃", "哪些娃", "有哪些娃",
        "我的娃", "我班", "班里", "名下", "孩子们", "娃们",
        "学生名单", "多少个学生",
        # 出题与题库（自 question 迁入）。出题具体短语在前、裸词「题目」在后，
        # 同上学情词序理由；「我有哪些题 / 题库 / 归档 / 删除题目」是题库管理
        # 意图，**不在** intent_schemas.generate 组（否则题库查询会被必填槽阻塞）。
        "出题", "出几道", "出道", "出题目", "来几道", "生成题",
        "测验", "考考", "练", "给我出", "帮我出",
        # ADR-0089：判断题闭环由出题自主驱动，「判断题」是出题意图（文本路由）。
        "判断题",
        "题目",
        # ADR-0097：题库管理词（查询 + 归档/删除两步模式）。
        "题库", "我有哪些题", "收起来", "归档", "删掉这几道", "删除题目",
    ],
    # 启发式兜底词（规则未命中时用，ADR-0030）：只收查询语境，写意图不兜底。
    # 两域并集；「学生」类泛词不进本表（触发层已精确覆盖）。
    "hints": [
        "任务", "作业", "练习册", "错题", "复习", "掌握", "进度",
        "查看", "列出", "查询",
        "出题", "出几道", "出道", "出道题目", "出题目", "测验",
        "考考", "生成题", "来几道", "给我题", "题库",
    ],
    # 正则触发词（ADR-0101）：表达「出 N 道 / 来 M 题」这一**族**，而非逐词旁举。
    #
    # 字面 ``triggers`` 是子串匹配，「出几道」命不中「出 2 道」——数字一变就漏，
    # 而实测「出一道选择题 / 出一题 / 出五道数学题 / 出2道数学题」全部落给 tutor
    # （fallback），出题请求被当成文本问答。量词旁举会随数字与量词组合指数膨胀，
    # 故用正则。
    #
    # 回传的 ``trigger`` 必须是 ``triggers`` 里已有的**规范词**，且该词必须在
    # ``intent_schemas.generate.triggers`` 里——否则子意图分组落不进去，出题必填槽
    # 预检会静默失效（契约测试 ``test_trigger_patterns_canonical`` 守）。
    "trigger_patterns": [
        # 「出/来/给/帮」+ 可选第一人称 + 数词/量词混合 + 道/题（「出一道」「出2道」
        # 「出五道数学题」「来三题」「给我出十道」）。数词取数字与中文一二三…十。
        {
            "pattern": (
                r"(?:再?给我?|帮我)?(?:再)?(?:出|来|生成|布置)"
                r"[0-9一二三四五六七八九十两几]+\s*(?:道|题|个题|道题)"
            ),
            "trigger": "出道",
        },
        # 「出一道选择题」这类「出 + 数词 + 量词」写法（量词在题型前）已由上一条覆盖；
        # 这里补「出一题 / 出个题」这类无显式量词的紧凑写法。
        {"pattern": r"(?:再)?(?:出|来)(?:一|个|些)\s*题", "trigger": "出题"},
    ],
    # 路由优先级：question 时代的 12 已无对手——现拓扑下只需高于 tutor(-10)
    # 的泛词 triggers（「怎么用你」含「怎么」由 capability(16) 挡）。
    "priority": 14,
    # 结构化动作：「按规格出题」（自 question 移入，等值匹配、不参与触发词
    # 优先级竞争）。判断题闭环（出题-判定-讲解）已整体下沉到子代理（ADR-0089）：
    # 出题助手从自由文本/知识点上下文自主决定出 judge 规格题卡（含答案落历史），
    # 伴学答疑从历史读答案判定，不再经服务端 quiz_generate / quiz_judge 动作键。
    "actions": ["task_generate"],
    # 出题 SOP（自 question 域迁入）：适龄 / 对齐教材 / 题型约定 / 儿童安全闸门。
    "skills": ["question_sop"],
    # 输入 schema（ADR-0095）：本域**默认意图**（学情 / 名单 / 题库管理）的槽位。
    # 读操作不阻塞（全部 optional）；create_draft 的目标学生必填性由 handler
    # 校验（ToolArgumentError 回灌，模型转问用户）。
    "input_schema": [
        {"name": "subject", "type": "enum", "required": False, "default": "",
         "enum_ref": "app.domain.subjects.SUBJECTS", "source": "both"},
        {"name": "grade", "type": "int", "required": False, "min": 1, "max": 9, "source": "both"},
        {"name": "count", "type": "int", "required": False, "default": 3,
         "min": 1, "max": 10, "source": "text"},
    ],
    # 子意图 schema（ADR-0098 §2.3）：question 并入后，出题的必填槽不能进默认
    # schema（会把「今天有什么作业」也拽进澄清），也不能丢（多轮出题澄清与
    # 跨轮槽位记忆是 ADR-0095 的既定行为）。按「路由命中的触发词落在哪个组」
    # 选 schema：generate 组管出题（必填 subject/grade/qtype + specs 注入），
    # 其余全部走默认 schema。triggers 必须是顶层 triggers 的子集（契约测试守护）。
    "intent_schemas": {
        "generate": {
            "triggers": [
                "出题", "出几道", "出道", "出题目", "来几道", "生成题",
                "测验", "考考", "练", "给我出", "帮我出", "判断题", "题目",
            ],
            "schema": [
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
        },
    },
}
