"""Pydantic schemas for the tasks feature."""

import uuid
from datetime import date, datetime

from pydantic import field_validator
from sqlmodel import Field, SQLModel

from app.domain.subjects import is_supported_subject, qtypes_for


class TaskSpec(SQLModel):
    """多学科一卷批量生成的一条规格（ADR-0004 D4）。

    学科 / 题型校验（ADR-0055 §11/§12）：后端开始校验——学科必须是收敛后的
    3 科之一；题型必须在学科白名单内（英语不再接受 calc）。存量其他学科的
    任务 / 题目冻结展示，不受影响。
    """

    subject: str = Field(max_length=32)
    grade: int
    knowledge_point: str = Field(max_length=128)
    qtype: str = Field(max_length=16)  # choice|fill|calc|open
    difficulty: str = Field(max_length=16, default="medium")
    # 是否多选题（ADR-0004 D5）：仅 choice 题型有意义；fill/calc/open 置 True 会被校验拒绝。
    multi: bool = False
    # 学期维度（ADR-0061 发布任务对接资料库）：'' = 不限/整学年；'上学期' / '下学期'。
    # 随规格持久化到 Task.specs 以便整卷重生成沿用，并透传到每道题 → Question/TaskQuestion。
    semester: str = Field(default="", max_length=8)
    count: int = Field(default=1, ge=1)

    @field_validator("subject")
    @classmethod
    def _subject_supported(cls, v: str) -> str:
        if not is_supported_subject(v):
            allowed = " / ".join(["数学", "语文", "英语"])
            raise ValueError(f"暂不支持学科「{v}」，请从 {allowed} 中选择")
        return v

    @field_validator("qtype")
    @classmethod
    def _qtype_in_whitelist(cls, v: str, info) -> str:
        subject = info.data.get("subject")
        if subject and v not in qtypes_for(subject):
            raise ValueError(f"学科「{subject}」不支持题型「{v}」")
        return v

    @field_validator("multi")
    @classmethod
    def _multi_only_for_choice(cls, v: bool, info) -> bool:
        # 多选题只在 choice 题型有意义；fill/calc/open 标多选属调用方错误，直接拒绝。
        if v and info.data.get("qtype") != "choice":
            raise ValueError("多选题（multi=true）仅支持选择题（choice）题型")
        return v


class TaskGenerateReq(SQLModel):
    """POST /tasks/generate 请求体（结构化出题，ADR-0034 Phase 1）。

    直接接收结构化规格，服务端据此构造出题 prompt（绝不过自然语言往返），经
    AgentRuntime 的 question subagent 流式返回题卡。前端收卡后走 /tasks/from-generated 落库。
    """

    specs: list[TaskSpec]
    model: str | None = None
    student_id: uuid.UUID | None = None
    focus_interest: list[str] | None = None
    # 反馈边（ADR-0060 D4）：随掌握度看板下发的代表错题 Question.id，服务端按
    # teacher_id + origin="ai" 解析为题干样例，注入出题 prompt 做同类题仿写。
    weak_example_ids: list[uuid.UUID] | None = None


class TaskFromGenerated(SQLModel):
    """POST /tasks/from-generated 请求体。

    流式出题（/ai/tasks/generate）逐题返回的题卡已在前端渲染；本端点把这些
    「已生成且经安全闸门」的题卡一次性落库为 draft 任务，避免二次生成与超时。
    `questions` 形态与 QuestionOut 对齐（snake_case：knowledge_point 等）。
    """

    title: str = Field(max_length=255)
    student_id: uuid.UUID | None = None  # 可空，支持"先成卷晚点派"
    specs: list[TaskSpec]  # 原始规格，持久化到 Task.specs 以便整卷重生成
    # 兴趣题模式（WF-4）：显式聚焦的兴趣主题列表；与生成时保持一致。
    focus_interest: list[str] | None = None
    # 可选模型引用：内置 id / ModelConfig id；落库以便重生成沿用。
    model: str | None = None
    # 已流式生成、待落库的题卡（QuestionPreview.toJson 形态）。
    questions: list[dict]


class TaskResp(SQLModel):
    id: uuid.UUID
    title: str
    status: str
    # 原始生成规格（整卷重生成可用；前端展示方便）
    specs: list[dict] | None = None
    questions: list["QuestionResp"] = []  # noqa: F821
    # 派发对象（列表/详情展示“对应学生”用）
    student_id: uuid.UUID | None = None
    # 创建时间（列表排序/展示用）
    created_at: datetime | None = None


class QuestionResp(SQLModel):
    id: uuid.UUID  # TaskQuestion.id（学生端读快照）
    question_id: uuid.UUID | None = None  # 源 Question.id，作答提交与错题归集用
    subject: str = ""
    grade: int = 0
    stem: str
    options: list[str] | None = None
    qtype: str
    knowledge_point: str
    explanation: str = ""
    # 学期维度（ADR-0061）：随题下发，前端展示/讲解场景匹配用。
    semester: str = ""
    # 是否多选题（ADR-0004 D5）：choice 题且多选项时 True，前端渲染复选、批改按集合比对。
    multi: bool = False
    # 学生端接口恒为 None，防作弊
    answer: str | None = None


class TaskSummaryResp(SQLModel):
    """任务列表项（ADR-0053）：**不内嵌题目**。

    列表只需要「这是哪个任务、多少题、什么学科、派给谁」，完整题目走
    ``GET /tasks/{task_id}``。此前列表直接复用 ``TaskResp``，导致一次列表请求把
    每个任务的全部题目（含题干/选项/答案/解析）都拉了下来——载荷是 O(任务数 × 题数)，
    而卡片上只显示「10 题」。
    """

    id: uuid.UUID
    title: str
    status: str
    student_id: uuid.UUID | None = None
    created_at: datetime | None = None
    question_count: int = 0
    # 本卷涉及的学科（按题数降序），供卡片显示学科色条/标签；不内嵌题目本身。
    subjects: list[str] = []


class TaskCounts(SQLModel):
    """各状态任务数（教师任务页三个 Tab 的徽标）。

    必须由服务端在分页响应里带出：徽标若靠客户端统计已加载页，就只有第一页的数，
    分页省下的流量又被徽标吃回去。
    """

    draft: int = 0
    ready: int = 0
    assigned: int = 0
    done: int = 0


class TaskListResp(SQLModel):
    """任务列表响应：游标分页信封（ADR-0053）。"""

    items: list[TaskSummaryResp]
    total: int
    page_size: int
    next_cursor: str | None = None
    counts: TaskCounts = TaskCounts()


class TaskFromBankCreate(SQLModel):
    """选项 A：从题库新建任务。"""

    title: str = Field(max_length=255)
    student_id: uuid.UUID | None = None
    question_ids: list[uuid.UUID]


class BankQuestionsAdd(SQLModel):
    """选项 B：加入已有草稿任务。"""

    question_ids: list[uuid.UUID]


class AnswerSubmit(SQLModel):
    question_id: uuid.UUID
    student_answer: str


class AnswerResult(SQLModel):
    correct: bool
    score: float
    explanation: str = ""


class CheckinResult(SQLModel):
    ok: bool
    checkin_date: date


class ProgressResp(SQLModel):
    student_id: uuid.UUID
    total: int
    correct: int
    accuracy: float
    streak_days: int
    checkin_days: int


class WrongQuestionResp(SQLModel):
    """错题列表项：含题干与答案/解析，供复习使用。"""

    id: uuid.UUID
    question_id: uuid.UUID
    subject: str
    grade: int
    knowledge_point: str
    qtype: str
    stem: str
    options: list[str] | None = None
    answer: str | None = None
    explanation: str = ""
    wrong_count: int
    first_wrong_at: datetime | None = None
    review_stage: int = 0
    due_at: datetime | None = None
    # 是否多选题（ADR-0004 D5）：随题下发，便于错题本复用闭环时渲染。
    multi: bool = False
    # 毕业（已掌握）时间；None = 仍在复习队列里（ADR-0053 P2）。
    graduated_at: datetime | None = None
    # 交互式讲解实例（ADR-0061）：题目知识点命中教师私有知识点模板时附上，
    # 前端在错题卡内联渲染。可空 = 该知识点暂无图形化讲解（维持原纯文本行为）。
    scene_spec: dict | None = None


class WrongQuestionListResp(SQLModel):
    """错题本响应：游标分页信封（ADR-0053）。

    教师端与学生端共用；``include_answer`` 由服务端按角色裁剪，不进查询参数。

    ``graduated_total``（ADR-0053 P2）：该学生「已掌握」的错题数。只在 ``scope=active``
    时随页下发——教师端要在列表底部显示「已掌握（N）」入口，而它是全量计数，
    不能靠已加载的页统计（那是 P0 刚修掉的老问题）。
    """

    items: list[WrongQuestionResp]
    total: int
    page_size: int
    next_cursor: str | None = None
    graduated_total: int = 0


class TaskQuestionEdit(SQLModel):
    """PUT /tasks/{task_id}/questions/{tq_id} 编辑请求体（仅 draft 态）。

    可改：题干/选项/答案/解析/知识点（ADR-0004 D6）。
    禁改：qtype（防学生端 UI 渲染崩），不在本 schema 暴露。
    """

    stem: str | None = None
    options: list[str] | None = None
    answer: str | None = None
    explanation: str | None = None


class TaskMetaEdit(SQLModel):
    """PUT /tasks/{task_id} 元信息编辑请求体（仅 draft 态）。

    可改：title（教师在草稿审核页改卷名）。
    禁改：status / student_id / specs —— 状态流转走 confirm/assign/discard 专属
    端点，specs 变更等价于重新生成（生成产物必须与规格一致），不在本端点放开。
    """

    title: str = Field(max_length=255)
    knowledge_point: str | None = None
