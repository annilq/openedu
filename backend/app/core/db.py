from sqlalchemy import text
from sqlalchemy.exc import OperationalError
from sqlmodel import SQLModel, create_engine

from app.core.config import settings

_connect_args = (
    {"check_same_thread": False}
    if str(settings.DATABASE_URL).startswith("sqlite")
    else {}
)

engine = create_engine(str(settings.DATABASE_URL), connect_args=_connect_args)


def run_migrations() -> None:
    """无 Alembic：启动期轻量迁移。

    - question 表补 teacher_id 列（owner 隔离，题库复用闭环）。
    - 回填：通过 task_question -> task 找到原题归属家长；孤儿行保持 NULL
      （作用域查询会排除，dev 期可 rm app.db 重置）。
    """
    with engine.begin() as conn:
        is_sqlite = engine.dialect.name == "sqlite"

        # —— ADR-0065：归属列 parent_id→teacher_id、child_id→student_id 改名 ——
        # 旧库物理列仍是 parent_id/child_id，此处一次性改名使其与模型层对齐；新库由
        # create_all 直接建 teacher_id/student_id，本步 no-op。角色枚举同步映射。
        _rename_ownership_columns(conn, is_sqlite)

        # —— question.teacher_id ——（既有迁移，保留）
        if is_sqlite:
            cols = [
                r[1]
                for r in conn.execute(text("PRAGMA table_info(question)")).fetchall()
            ]
            if "teacher_id" not in cols:
                conn.execute(
                    text("ALTER TABLE question ADD COLUMN teacher_id VARCHAR(36)")
                )
        else:  # postgres
            conn.execute(
                text("ALTER TABLE question ADD COLUMN IF NOT EXISTS teacher_id UUID")
            )

        # —— question.origin（题目来源：ai / parent，ADR-0060）——
        # 存量行无 origin：默认 "ai"（历史题目皆为 AI 生成）。新增行由创建点显式赋值。
        if is_sqlite:
            q_cols = [
                r[1]
                for r in conn.execute(text("PRAGMA table_info(question)")).fetchall()
            ]
            if "origin" not in q_cols:
                conn.execute(
                    text(
                        "ALTER TABLE question ADD COLUMN origin VARCHAR(16) DEFAULT 'ai'"
                    )
                )
        else:
            conn.execute(
                text(
                    "ALTER TABLE question ADD COLUMN IF NOT EXISTS origin VARCHAR(16) DEFAULT 'ai'"
                )
            )

        # —— question.source_refs（资料溯源快照 JSON，ADR-0055 §10）——
        if is_sqlite:
            q_cols = [
                r[1]
                for r in conn.execute(text("PRAGMA table_info(question)")).fetchall()
            ]
            if "source_refs" not in q_cols:
                conn.execute(text("ALTER TABLE question ADD COLUMN source_refs TEXT"))
            # question.multi（ADR-0004 D5）：多选题标记，默认 False。
            if "multi" not in q_cols:
                conn.execute(
                    text("ALTER TABLE question ADD COLUMN multi BOOLEAN NOT NULL DEFAULT 0")
                )
        else:
            conn.execute(
                text("ALTER TABLE question ADD COLUMN IF NOT EXISTS source_refs JSON")
            )
            conn.execute(
                text(
                    "ALTER TABLE question ADD COLUMN IF NOT EXISTS "
                    "multi BOOLEAN NOT NULL DEFAULT FALSE"
                )
            )
        # 回填：通过 task_question -> task 找到原题归属家长；孤儿行保持 NULL。
        # 旧库若尚未建 task_question 表（偏序迁移），跳过回填（owner 隔离降级，dev 可重置）。
        try:
            conn.execute(
                text(
                    """
                    UPDATE question SET teacher_id = (
                        SELECT t.teacher_id FROM task_question tq
                        JOIN task t ON t.id = tq.task_id
                        WHERE tq.question_id = question.id LIMIT 1
                    ) WHERE teacher_id IS NULL
                    """
                )
            )
        except OperationalError:
            pass  # 偏序迁移：task_question 不存在，回填降级

        # —— task.model（出题所选模型引用，ADR-0015/票据 08）——
        if is_sqlite:
            task_cols = [
                r[1] for r in conn.execute(text("PRAGMA table_info(task)")).fetchall()
            ]
            if "model" not in task_cols:
                conn.execute(text("ALTER TABLE task ADD COLUMN model VARCHAR(255)"))
        else:
            conn.execute(
                text("ALTER TABLE task ADD COLUMN IF NOT EXISTS model VARCHAR(255)")
            )

        # —— 归档 / 毕业时间戳（ADR-0053 P2）——
        # 三个模块共用一套 archived 字段的诱惑在这里被拒绝了：题库是「家长主动弃用」、
        # 错题是「系统判定已掌握」，同名字段会让「这行为什么归档了」无法回答。
        for table, column in (
            ("question", "archived_at"),
            ("wrongquestion", "graduated_at"),
        ):
            try:
                if is_sqlite:
                    cols = [
                        r[1]
                        for r in conn.execute(
                            text(f"PRAGMA table_info({table})")
                        ).fetchall()
                    ]
                    if column not in cols:
                        conn.execute(
                            text(f"ALTER TABLE {table} ADD COLUMN {column} TIMESTAMP")
                        )
                else:
                    conn.execute(
                        text(
                            f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS "
                            f"{column} TIMESTAMP WITH TIME ZONE"
                        )
                    )
            except OperationalError:
                # 偏序迁移：表还没建（首次启动由 init_db 建表并带新列），跳过即可。
                pass

        # —— 列表游标分页的排序索引（ADR-0053）——
        # 三个长列表都按 (owner, 时间戳倒序) 取页，缺复合索引时深翻会全表排序。
        # CREATE INDEX IF NOT EXISTS 在 SQLite / Postgres 下都幂等，旧库启动期自动补齐。
        for ddl in (
            "CREATE INDEX IF NOT EXISTS ix_question_parent_created "
            "ON question (teacher_id, created_at DESC)",
            "CREATE INDEX IF NOT EXISTS ix_task_parent_created "
            "ON task (teacher_id, created_at DESC)",
            "CREATE INDEX IF NOT EXISTS ix_wrongquestion_child_firstwrong "
            "ON wrongquestion (student_id, first_wrong_at DESC)",
        ):
            try:
                conn.execute(text(ddl))
            except OperationalError:
                # 偏序迁移：表还没建（首次启动由 init_db 建表并带索引），跳过即可。
                pass

        # —— 知识点学期维度（ADR-0055 §4 补）——
        # 学期是第四维范围（'' = 整学年/不限；'上学期' / '下学期'），旧库无此列时补齐。
        # ⚠️ 表名必须匹配 KnowledgePoint 模型默认生成的 `knowledgepoint`（无下划线），
        # 否则 PRAGMA 查错表被下方 except 静默吞掉、列永远加不上。
        try:
            if is_sqlite:
                cols = [
                    r[1]
                    for r in conn.execute(
                        text("PRAGMA table_info(knowledgepoint)")
                    ).fetchall()
                ]
                if "semester" not in cols:
                    conn.execute(
                        text(
                            "ALTER TABLE knowledgepoint ADD COLUMN semester VARCHAR(8) DEFAULT ''"
                        )
                    )
            else:
                conn.execute(
                    text(
                        "ALTER TABLE knowledgepoint ADD COLUMN IF NOT EXISTS "
                        "semester VARCHAR(8) NOT NULL DEFAULT ''"
                    )
                )
        except OperationalError:
            # 偏序迁移：表还没建（首次启动由 init_db 建表并带新列），跳过即可。
            pass

        # —— 课件素材知识点关联（T04 素材库检索）——
        # 素材可被某知识点筛选（素材库「按知识点过滤」）；为空 = 通用素材。
        # 跨教师访问该知识点经 service 的 require_owned 返回 403。
        # 仅补列（不加索引 / FK）：索引对老库是性能细节，FK 在 SQLite ALTER 下无法补。
        try:
            if is_sqlite:
                cols = [
                    r[1]
                    for r in conn.execute(
                        text("PRAGMA table_info(coursewareasset)")
                    ).fetchall()
                ]
                if "knowledge_point_id" not in cols:
                    conn.execute(
                        text(
                            "ALTER TABLE coursewareasset ADD COLUMN knowledge_point_id VARCHAR(36)"
                        )
                    )
            else:
                conn.execute(
                    text(
                        "ALTER TABLE coursewareasset ADD COLUMN IF NOT EXISTS "
                        "knowledge_point_id UUID"
                    )
                )
        except OperationalError:
            # 偏序迁移：表还没建（首次启动由 init_db 建表并带新列），跳过即可。
            pass

        # —— 班级实体（ADR-0068 / teacher-scale-up 地基）——
        # 新表走 CREATE TABLE IF NOT EXISTS：既有库启动期自动补齐；新库由 create_all 已建好，no-op。
        # ``class_id`` 列补到 ``user`` 表供学生归属班级（删班后仅置空、不删学生）。
        _add_classes(conn, is_sqlite)

        # —— 课件教学目标（courseware-round-3 T01）——
        # 空壳课件建出时存教师填的教学目标，供后续「AI 补充讲解」（T05）读取。
        # 仅补列（无索引 / 无 FK）；表未建（偏序迁移，首次启动走 init_db 建表并带新列）时跳过。
        try:
            if is_sqlite:
                cw_cols = [
                    r[1]
                    for r in conn.execute(
                        text("PRAGMA table_info(courseware)")
                    ).fetchall()
                ]
                if "objective" not in cw_cols:
                    conn.execute(
                        text("ALTER TABLE courseware ADD COLUMN objective TEXT")
                    )
            else:
                conn.execute(
                    text(
                        "ALTER TABLE courseware ADD COLUMN IF NOT EXISTS objective TEXT"
                    )
                )
        except OperationalError:
            # 偏序迁移：courseware 表还没建（首次启动由 init_db 建表并带新列），跳过即可。
            pass

        # —— 作业派发关系表（ADR-0069）——
        # 新表用 CREATE TABLE IF NOT EXISTS；唯一约束 (task_id, student_id) 必须写进
        # CREATE TABLE（SQLite ALTER 静默忽略 UNIQUE，ADR-0061 §R）。旧单列 task.student_id
        # 幂等回填为关系行（仅当该 (task,student) 尚不存在）。
        _add_task_assignments(conn, is_sqlite)

        # —— 清理 JSON 列里的文本 'null'（ADR-0061 §T）——
        _nullify_text_json_nulls(conn)

        # —— 清理孤儿错题（学生管理列表 vs 详情计数不一致根因，2026-10-08）——
        # wrongquestion.question_id 的 FK 无 ON DELETE CASCADE，且 SQLite 默认不强制外键；
        # 源 question 被硬删（删任务 / 再生成 / 批量删题）后 wrongquestion 行被遗留成
        # dangling。列表统计(改后)与详情页均 INNER JOIN question，孤儿既数不到也点不开，
        # 故此处幂等删除：question_id 为 NULL 或指向不存在的 question 的行一律清掉。
        # 表未建（偏序迁移）时跳过。
        _purge_orphan_wrong_questions(conn)

        # —— 知识点唯一约束补 semester（ADR-0061 §R）——
        # ⚠️ 上一段只补了**列**，但 SQLite **无法 ALTER 已存在表上的 UNIQUE 约束**
        # （没有 `ALTER TABLE ... ADD CONSTRAINT`）。于是所有在加学期维度**之前**
        # 建库的库（含本机开发库）里，唯一约束仍是旧的 4 列
        # `UNIQUE(teacher_id, subject, grade, name)` —— **少了 semester**。
        #
        # 后果不是「报错」而是**静默废掉 §J 承诺的核心能力**：同一知识点无法按学期
        # 各存一份（上/下学期模板），因为名字一撞就撞唯一约束。实测报错
        # `UNIQUE constraint failed: knowledgepoint.teacher_id, .subject, .grade, .name`。
        #
        # 修法：SQLite 改约束只能**重建表**（建新表 → 拷数据 → 删旧 → 改名 → 重建索引）。
        # 幂等：只在检测到约束确实缺 semester 时才做。
        if is_sqlite:
            _rebuild_kp_unique_with_semester(conn)

        # —— 知识点彻底去掉空学期（用户决策 2026-10-05）——
        # semester='' 原表示「整学年/不限」，会与具体学期行（上/下学期）并存，
        # 造成同一概念（如「图形的运动」）在管理页出现「待审 + 已转正」两条重名数据。
        # 现在学期必须是具体值。此迁移删掉有具体学期兄弟的 '' 行、把纯整学年 ''
        # 行改归上学期。幂等：重跑为 no-op。方言无关。
        _migrate_kp_no_empty_semester(conn)

        # —— 交互式讲解场景（ADR-0061）：知识点默认模板 + 题目实例 ——
        # knowledgepoint.scenes：[{kind, inputs, controls, ...}] 教师编写的默认讲解模板。
        # question.scene_spec：出题时由知识点模板 + 本题数值融合得到的实例。
        # 均 JSON 可空、不建外键（快照式），沿用 semester 的 SQLite/Postgres 双分支。
        try:
            if is_sqlite:
                kp_cols = [
                    r[1]
                    for r in conn.execute(
                        text("PRAGMA table_info(knowledgepoint)")
                    ).fetchall()
                ]
                if "scenes" not in kp_cols:
                    conn.execute(
                        text("ALTER TABLE knowledgepoint ADD COLUMN scenes TEXT")
                    )
                q_cols = [
                    r[1]
                    for r in conn.execute(
                        text("PRAGMA table_info(question)")
                    ).fetchall()
                ]
                if "scene_spec" not in q_cols:
                    conn.execute(
                        text("ALTER TABLE question ADD COLUMN scene_spec TEXT")
                    )
                if "semester" not in q_cols:
                    conn.execute(
                        text(
                            "ALTER TABLE question ADD COLUMN semester VARCHAR(8) DEFAULT ''"
                        )
                    )
                tq_cols = [
                    r[1]
                    for r in conn.execute(
                        text("PRAGMA table_info(taskquestion)")
                    ).fetchall()
                ]
                if "semester" not in tq_cols:
                    conn.execute(
                        text(
                            "ALTER TABLE taskquestion ADD COLUMN semester VARCHAR(8) DEFAULT ''"
                        )
                    )
                # taskquestion.scene_spec：草稿期就要带场景，否则「确认前预览 /
                # 草稿审核」拿不到快照（question 要等 promote 才有行）。
                if "scene_spec" not in tq_cols:
                    conn.execute(
                        text("ALTER TABLE taskquestion ADD COLUMN scene_spec TEXT")
                    )
                # taskquestion.multi（ADR-0004 D5）：多选题标记，默认 False。
                if "multi" not in tq_cols:
                    conn.execute(
                        text(
                            "ALTER TABLE taskquestion ADD COLUMN multi "
                            "BOOLEAN NOT NULL DEFAULT 0"
                        )
                    )
            else:
                conn.execute(
                    text(
                        "ALTER TABLE knowledgepoint ADD COLUMN IF NOT EXISTS "
                        "scenes JSON"
                    )
                )
                conn.execute(
                    text(
                        "ALTER TABLE question ADD COLUMN IF NOT EXISTS "
                        "scene_spec JSON"
                    )
                )
                conn.execute(
                    text(
                        "ALTER TABLE question ADD COLUMN IF NOT EXISTS "
                        "semester VARCHAR(8) NOT NULL DEFAULT ''"
                    )
                )
                conn.execute(
                    text(
                        "ALTER TABLE taskquestion ADD COLUMN IF NOT EXISTS "
                        "semester VARCHAR(8) NOT NULL DEFAULT ''"
                    )
                )
                conn.execute(
                    text(
                        "ALTER TABLE taskquestion ADD COLUMN IF NOT EXISTS "
                        "scene_spec JSON"
                    )
                )
                conn.execute(
                    text(
                        "ALTER TABLE taskquestion ADD COLUMN IF NOT EXISTS "
                        "multi BOOLEAN NOT NULL DEFAULT FALSE"
                    )
                )
        except OperationalError:
            # 偏序迁移：表还没建（首次启动由 init_db 建表并带新列），跳过即可。
            pass

        # —— 目录 / 资料学期维度（ADR-0055 §2 补）——
        # 学期是目录的继承元数据（''/上学期/下学期），随资料上传继承到 Material，
        # 再在抽取知识点时带入 KnowledgePoint.semester。旧库无此列时补齐。
        # ⚠️ 表名必须匹配模型默认生成名：MaterialFolder → `materialfolder`、Material → `material`（均小写无下划线）。
        try:
            for tbl in ("materialfolder", "material"):
                if is_sqlite:
                    cols = [
                        r[1]
                        for r in conn.execute(
                            text(f"PRAGMA table_info({tbl})")
                        ).fetchall()
                    ]
                    if "semester" not in cols:
                        conn.execute(
                            text(f"ALTER TABLE {tbl} ADD COLUMN semester VARCHAR(8)")
                        )
                else:
                    conn.execute(
                        text(
                            f"ALTER TABLE {tbl} ADD COLUMN IF NOT EXISTS "
                            "semester VARCHAR(8)"
                        )
                    )
        except OperationalError:
            # 偏序迁移：表还没建（首次启动由 init_db 建表并带新列），跳过即可。
            pass

        # —— modelconfig（家长自定义模型，ADR-0015）——
        # ⚠️ 表名必须用模型默认生成的 `modelconfig`（ModelConfig → 小写无下划线，
        # 与 materialfolder/wrongquestion/answerrecord 同款约定），不能用 `model_config`。
        # 旧迁移曾误建成带下划线的 `model_config` 孤儿空表，此处先清掉再建正确表名。
        conn.execute(text("DROP TABLE IF EXISTS model_config"))  # 清理误建孤儿表
        conn.execute(
            text(
                "CREATE TABLE IF NOT EXISTS modelconfig ("
                " id VARCHAR(36) PRIMARY KEY,"
                " teacher_id VARCHAR(36),"
                " label VARCHAR(64),"
                " provider VARCHAR(32),"
                " base_url VARCHAR(512),"
                " model_name VARCHAR(128),"
                " api_key_enc VARCHAR(1024),"
                " is_default BOOLEAN"
                ")"
            )
        )

        # —— conversation / message（AI 运行可观测调试库，ADR-0022）——
        # 新表走 CREATE TABLE IF NOT EXISTS：既有库启动期自动补齐，无需手写 ALTER。
        # SQLite 用 TEXT 存 JSON，postgres 用 JSON（与项目其余 JSON 列约定一致）。
        conn.execute(
            text(
                "CREATE TABLE IF NOT EXISTS conversation ("
                " id VARCHAR(36) PRIMARY KEY,"
                " kind VARCHAR(32),"
                " teacher_id VARCHAR(36),"
                " student_id VARCHAR(36),"
                " model VARCHAR(255),"
                " title VARCHAR(255),"
                " ref_task_id VARCHAR(36),"
                " status VARCHAR(16),"
                " created_at TIMESTAMP WITH TIME ZONE,"
                " updated_at TIMESTAMP WITH TIME ZONE"
                ")"
            )
        )
        conn.execute(
            text(
                "CREATE TABLE IF NOT EXISTS message ("
                " id VARCHAR(36) PRIMARY KEY,"
                " conversation_id VARCHAR(36),"
                " turn INTEGER,"
                " role VARCHAR(16),"
                " step VARCHAR(16),"
                " content TEXT,"
                " payload TEXT,"
                " model VARCHAR(255),"
                " input_safe BOOLEAN,"
                " output_safe BOOLEAN,"
                " blocked BOOLEAN,"
                " block_reason VARCHAR(255),"
                " latency_ms INTEGER,"
                " usage TEXT,"
                " created_at TIMESTAMP WITH TIME ZONE"
                ")"
            )
        )

        # —— conversation.pending_quiz（ADR-0072 出题-判断-引导闭环的跨轮状态）——
        # 仅补列：无索引 / 无 FK（快照式，与 ADR-0061 同纪律）。SQLite 用 TEXT 存 JSON，
        # postgres 用 JSON（与项目其余 JSON 列约定一致）。ADD COLUMN 在 SQLite 下被静默
        # 忽略约束（ADR-0061 §R），本列无需约束，故直接补即可，无需重建表。
        if is_sqlite:
            conv_cols = [
                r[1]
                for r in conn.execute(text("PRAGMA table_info(conversation)")).fetchall()
            ]
            if "pending_quiz" not in conv_cols:
                conn.execute(
                    text("ALTER TABLE conversation ADD COLUMN pending_quiz TEXT")
                )
        else:  # postgres
            conn.execute(
                text(
                    "ALTER TABLE conversation ADD COLUMN IF NOT EXISTS pending_quiz JSON"
                )
            )

        # —— 场景 kind 级默认图形（ADR-0074 v4）——
        # 新表走 CREATE TABLE IF NOT EXISTS：既有库启动期自动补齐；新库由 create_all
        # 已建好，no-op。kind = 注册表 key，不做外键（注册表非 DB 实体）。
        # 单一语句双方言兼容：SQLite 接受 TIMESTAMP WITH TIME ZONE 作类型名、VARCHAR 通用。
        conn.execute(
            text(
                "CREATE TABLE IF NOT EXISTS scene_template_config ("
                " kind VARCHAR(64) PRIMARY KEY,"
                " default_figure_key VARCHAR(64)"
                ")"
            )
        )


def _purge_orphan_wrong_questions(conn) -> None:
    """删除指向不存在 / 为 NULL 的源题目的孤儿错题（2026-10-08）。

    **为什么会有**：``wrongquestion.question_id`` 的外键无 ``ON DELETE CASCADE``，
    且 SQLite 默认不强制外键。源 ``question`` 被硬删（删任务 / 题目再生成 / 批量删题）
    后，``wrongquestion`` 行被遗留成 dangling。这种行既进不了列表统计（改后的
    ``wrong-question-counts`` 与详情页都 INNER JOIN question），也无法在详情页点开，
    只会造成「数得到点不到」的困惑。

    **清理语义**：删除所有 ``question_id IS NULL`` 或 ``question_id`` 不在 ``question``
    表的行。这与列表/详情两侧的 INNER JOIN 口径完全一致——被删的正好是永远无法展示的行。

    **幂等 + 方言无关**：纯 DELETE + 子查询，重跑为 no-op；NULL 与 NOT IN 写法在
    SQLite / Postgres 都正确（``question.id`` 是主键永不为 NULL，NOT IN 不会整体失配）。
    表未建（偏序迁移）时 ``OperationalError`` 跳过。
    """
    try:
        conn.execute(
            text(
                "DELETE FROM wrongquestion "
                "WHERE question_id IS NULL "
                "OR question_id NOT IN (SELECT id FROM question)"
            )
        )
    except OperationalError:
        # 偏序迁移：wrongquestion / question 表还没建，跳过即可。
        pass


def _nullify_text_json_nulls(conn) -> None:
    """把 JSON 列里「文本 ``'null'``」改回真正的 SQL NULL（ADR-0061 §T）。

    **为什么会有**：SQLAlchemy 的 ``JSON`` 列默认 ``none_as_null=False`` —— 写
    Python ``None`` 时它会序列化成**文本 ``'null'``** 存进 TEXT 列，而不是 SQL NULL。
    于是 ``WHERE col IS NOT NULL`` 为真（行「有值」），而实际内容是空。任何按
    「非空」计数的逻辑都会失真（实测 ``question.options`` 有 5 行是文本 'null'，
    读出来是字符串 ``'null'``，``.get('options')`` 之类判断全部走偏）。

    **现在模型层已统一用 ``JSON(none_as_null=True)``**（新写入不再产生文本 'null'），
    本迁移只负责收拾存量。幂等：只 UPDATE 当前值**恰为**文本 'null' 的行；
    表不存在则跳过（偏序迁移纪律）。
    """
    for table, column in (
        ("question", "options"),
        ("question", "source_refs"),
        ("taskquestion", "options"),
        ("task", "specs"),
        ("material", "knowledge_points"),
        ("conversation", "payload"),
        ("conversation", "usage"),
    ):
        try:
            conn.execute(
                text(f"UPDATE {table} SET {column} = NULL WHERE {column} = 'null'")
            )
        except OperationalError:
            # 表/列还没建 → 跳过。SQL 的标识符来自上面的常量白名单，非外部输入。
            continue


def _rebuild_kp_unique_with_semester(conn) -> None:
    """把 knowledgepoint 的 UNIQUE 约束补上 ``semester``（ADR-0061 §R）。

    **为什么必须重建表**：SQLite 没有 ``ALTER TABLE ... ADD CONSTRAINT``，
    改已存在表的唯一约束只有「建新表 → 拷数据 → 删旧 → 改名 → 重建索引」一条路。

    为什么需要：加学期维度那次迁移只补了**列**（``ADD COLUMN semester``），
    约束没动。SQLite 会忽略 ``ADD COLUMN`` 里带的 ``UNIQUE(...)`` 子句，于是老库里
    仍是 ``UNIQUE(teacher_id, subject, grade, name)``——**同一知识点按学期各存一份
    根本存不进去**（名字一撞就撞约束），§J 承诺的核心能力静默失效。

    幂等：先读 ``sqlite_master`` 判约束现状，缺 semester 才动手；已正确的库直接返回。
    重建后重新建``ix_knowledgepoint_scope``（含 semester 的4 列版本）。

    数据安全：拷贝只搬**行**，不改值。旧 4 列约束比新 5 列更严（同一名字在旧库
    根本不可能有多行），所以新约束下必然仍成立——不会出现迁移后立刻违约。
    """
    row = conn.execute(
        text(
            "SELECT sql FROM sqlite_master "
            "WHERE type = 'table' AND name = 'knowledgepoint'"
        )
    ).fetchone()
    if row is None or not row[0]:
        return  # 表还没建（首次启动走 init_db 建表，天然带 semester 约束）
    ddl = row[0]
    # 已经含 semester 约束 → 无需重建（幂等短路）
    if "UNIQUE" in ddl.upper() and "semester" in ddl.split("UNIQUE", 1)[1]:
        return

    cols = [r[1] for r in conn.execute(text("PRAGMA table_info(knowledgepoint)"))]
    if "semester" not in cols:
        # 列都还没有 → 上面的 ADD COLUMN 迁移会先补；本轮跳过（下次启动再收尾）
        return

    # 列清单与顺序照搬现有表（semester/scenes 已在其中），只改 UNIQUE 定义。
    conn.execute(text("DROP TABLE IF EXISTS _kp_migrate_tmp"))
    conn.execute(
        text(
            "CREATE TABLE _kp_migrate_tmp ("
            " id CHAR(32) NOT NULL, "
            " teacher_id CHAR(32) NOT NULL, "
            " subject VARCHAR(16) NOT NULL, "
            " grade INTEGER NOT NULL, "
            " name VARCHAR(128) NOT NULL, "
            " status VARCHAR(16) NOT NULL, "
            " source VARCHAR(16) NOT NULL, "
            " created_at DATETIME, "
            " semester VARCHAR(8) DEFAULT '', "
            " scenes TEXT, "
            " PRIMARY KEY (id), "
            # ★ 关键差异：唯一约束含 semester → 同一知识点可按学期各存一份
            " UNIQUE (teacher_id, subject, grade, name, semester), "
            " FOREIGN KEY(teacher_id) REFERENCES user (id))"
        )
    )
    conn.execute(
        text(
            "INSERT INTO _kp_migrate_tmp "
            "(id, teacher_id, subject, grade, name, status, source, created_at, "
            " semester, scenes) "
            "SELECT id, teacher_id, subject, grade, name, status, source, created_at, "
            " COALESCE(semester, ''), scenes FROM knowledgepoint"
        )
    )
    conn.execute(text("DROP TABLE knowledgepoint"))
    conn.execute(text("ALTER TABLE _kp_migrate_tmp RENAME TO knowledgepoint"))
    # 重建 scope 索引（含 semester 的 4 列版本；旧库那条只有 3 列）
    conn.execute(text("DROP INDEX IF EXISTS ix_knowledgepoint_scope"))
    conn.execute(
        text(
            "CREATE INDEX ix_knowledgepoint_scope "
            "ON knowledgepoint (teacher_id, subject, grade, semester)"
        )
    )


def _migrate_kp_no_empty_semester(conn) -> None:
    """彻底去掉知识点空学期（用户决策 2026-10-05）。

    ``semester=''`` 原表示「整学年/不限」，会与具体学期行（上/下学期）并存，造成同一
    概念（如「图形的运动」）在管理页出现「待审 + 已转正」两条重名数据。决定：知识点
    的学期必须是具体值，不再允许空。

    - 同一 (teacher_id, subject, grade, name) 同时有 ``''`` 行与具体学期行的 → 删 ``''`` 行
      （具体学期胜出，消除重名）。
    - 其余 ``''`` 行（纯整学年、无具体学期兄弟）→ 改为 ``上学期``（讲解页可再改）。

    幂等：执行后 knowledgepoint 表不再有 ``semester=''`` 行，重跑为 no-op。方言无关
    （DELETE/UPDATE 均为标准 SQL，EXISTS 关联子查询兼容 sqlite/postgres）。
    """
    try:
        # 1) 删掉「有具体学期兄弟」的 '' 行：具体学期优先，消除重名。
        conn.execute(
            text(
                "DELETE FROM knowledgepoint "
                "WHERE semester = '' "
                "  AND EXISTS ("
                "    SELECT 1 FROM knowledgepoint k2"
                "    WHERE k2.semester <> ''"
                "      AND k2.teacher_id = knowledgepoint.teacher_id"
                "      AND k2.subject = knowledgepoint.subject"
                "      AND k2.grade = knowledgepoint.grade"
                "      AND k2.name = knowledgepoint.name"
                "  )"
            )
        )
        # 2) 剩余 '' 行（纯整学年，无具体学期兄弟）→ 上学期。
        conn.execute(
            text("UPDATE knowledgepoint SET semester = '上学期' WHERE semester = ''")
        )
    except OperationalError:
        # 表还没建 → 跳过（首次启动由 create_all 建表，本迁移后续启动再收尾）
        return


def _rename_ownership_columns(conn, is_sqlite: bool) -> None:
    """把历史库的归属列 parent_id→teacher_id、child_id→student_id 改名（ADR-0065）。

    新库由 ``create_all`` 直接建 ``teacher_id``/``student_id``，本函数 no-op。
    旧库（仍 ``parent_id``/``child_id``）在此一次性改名，使模型层与物理列对齐。

    幂等：仅当旧列存在、新列不存在时才 ``RENAME``；表不存在则跳过（偏序迁移纪律）。
    角色枚举值同步映射：``parent``→``teacher``、``child``→``student``。
    """
    renames = [
        ("modelconfig", "parent_id", "teacher_id"),
        ("question", "parent_id", "teacher_id"),
        ("conversation", "parent_id", "teacher_id"),
        ("conversation", "child_id", "student_id"),
        ("task", "parent_id", "teacher_id"),
        ("task", "child_id", "student_id"),
        ("user", "parent_id", "teacher_id"),
        ("materialfolder", "parent_id", "teacher_id"),
        # 目录自引用父目录：parent_folder_id → teacher_folder_id（网盘式目录树）
        ("materialfolder", "parent_folder_id", "teacher_folder_id"),
        ("material", "parent_id", "teacher_id"),
        ("materialchunk", "parent_id", "teacher_id"),
        ("knowledgepoint", "parent_id", "teacher_id"),
        ("wrongquestion", "child_id", "student_id"),
        ("answerrecord", "child_id", "student_id"),
        ("checkin", "child_id", "student_id"),
        # ⚠️ 表名必须是 TutorLog 默认派生的 `tutorlog`（小写无下划线），
        # 不能用 `tutor`（旧迁移 typo，会静默跳过导致 child_id 不改名）。
        ("tutorlog", "child_id", "student_id"),
    ]
    for table, old, new in renames:
        try:
            if is_sqlite:
                cols = [
                    r[1]
                    for r in conn.execute(
                        text(f"PRAGMA table_info({table})")
                    ).fetchall()
                ]
                old_exists = old in cols
                new_exists = new in cols
            else:
                row = conn.execute(
                    text(
                        "SELECT 1 FROM information_schema.columns "
                        "WHERE table_name = :t AND column_name = :c"
                    ),
                    {"t": table, "c": old},
                ).fetchone()
                old_exists = row is not None
                row2 = conn.execute(
                    text(
                        "SELECT 1 FROM information_schema.columns "
                        "WHERE table_name = :t AND column_name = :c"
                    ),
                    {"t": table, "c": new},
                ).fetchone()
                new_exists = row2 is not None
        except OperationalError:
            # 表不存在（首次启动偏序迁移），跳过
            continue
        if old_exists and not new_exists:
            conn.execute(
                text(f"ALTER TABLE {table} RENAME COLUMN {old} TO {new}")
            )
    # 角色枚举值映射（ADR-0065）：parent→teacher、child→student。幂等（无匹配行即 no-op）。
    conn.execute(
        text("UPDATE \"user\" SET role = 'teacher' WHERE role = 'parent'")
    )
    conn.execute(
        text("UPDATE \"user\" SET role = 'student' WHERE role = 'child'")
    )


def _seed_figure_library() -> None:
    """图形几何库内置种子（ADR-0083）：11 个内置图形以 points+edges 入库，无 axis 字段。

    用 ORM Session 写入，JSON 列（points/edges）由 SQLAlchemy 正确处理（跨 SQLite /
    Postgres）。幂等：key 为主键，已存在则跳过，重跑 no-op。
    """
    from sqlmodel import Session, select

    from app.db.models import FigureLibrary
    from app.features.materials.scene_figures import BUILTIN_FIGURE_SEED

    with Session(engine) as session:
        # `select(FigureLibrary.key)` 在 SQLModel 下返回**标量**（字符串），不是行对象。
        existing = set(session.exec(select(FigureLibrary.key)).all())
        for shape in BUILTIN_FIGURE_SEED:
            if shape.key in existing:
                continue
            n = len(shape.vertices)
            edges = [[i, (i + 1) % n] for i in range(n)]
            session.add(
                FigureLibrary(
                    key=shape.key,
                    label=shape.label,
                    points=[[x, y] for x, y in shape.vertices],
                    edges=edges,
                    note=shape.note or None,
                    is_builtin=True,
                )
            )
        session.commit()


def init_db() -> None:
    # 确保模型已注册后再建表（详见 SQLModel 关系初始化注意事项）
    import app.db.models  # noqa: F401  (feature-first: ORM 集中在 app.db.models)

    SQLModel.metadata.create_all(engine)
    run_migrations()
    _seed_figure_library()


def _add_classes(conn, is_sqlite: bool) -> None:
    """班级实体表 + user.class_id 列（ADR-0068）。

    新表用 ``CREATE TABLE IF NOT EXISTS``（既有库启动期补齐，新库由 create_all 已建，no-op）。
    ``user.class_id`` 用 PRAGMA 探测后 ``ALTER TABLE ADD COLUMN``（SQLite 不可补 FK，故只补列），
    Postgres 用 ``ADD COLUMN IF NOT EXISTS``。类名定为 ``classes``（避开 SQL 关键字 ``class``）。
    """
    conn.execute(
        text(
            "CREATE TABLE IF NOT EXISTS classes ("
            " id VARCHAR(36) PRIMARY KEY,"
            " teacher_id VARCHAR(36) NOT NULL,"
            " name VARCHAR(64) NOT NULL,"
            " grade INTEGER NOT NULL,"
            " created_at TIMESTAMP WITH TIME ZONE,"
            " FOREIGN KEY(teacher_id) REFERENCES \"user\" (id))"
        )
    )
    try:
        if is_sqlite:
            user_cols = [
                r[1]
                for r in conn.execute(text('PRAGMA table_info("user")')).fetchall()
            ]
            if "class_id" not in user_cols:
                conn.execute(
                    text('ALTER TABLE "user" ADD COLUMN class_id VARCHAR(36)')
                )
        else:
            conn.execute(
                text('ALTER TABLE "user" ADD COLUMN IF NOT EXISTS class_id UUID')
            )
    except OperationalError:
        # 偏序迁移：user 表还没建（首次启动由 init_db 建表并带新列），跳过即可。
        pass


def _add_task_assignments(conn, is_sqlite: bool) -> None:
    """作业派发关系表（ADR-0069）+ 旧单列回填。

    新表用 ``CREATE TABLE IF NOT EXISTS``：唯一约束 ``(task_id, student_id)`` 必须写进
    ``CREATE TABLE``（SQLite 的 ``ALTER TABLE ADD CONSTRAINT`` 被静默忽略，ADR-0061 §R）。
    回填：旧库里 ``task.student_id`` 非空的行 → 生成一条 assignment（已存在则跳过，幂等）。
    ``completed_at`` 仅当任务已 ``done`` 时回填（无精确完成时间，用任务创建时间近似）。
    """
    conn.execute(
        text(
            "CREATE TABLE IF NOT EXISTS taskassignment ("
            " id VARCHAR(36) PRIMARY KEY,"
            " task_id VARCHAR(36) NOT NULL,"
            " student_id VARCHAR(36) NOT NULL,"
            " assigned_at TIMESTAMP WITH TIME ZONE,"
            " completed_at TIMESTAMP WITH TIME ZONE,"
            " FOREIGN KEY(task_id) REFERENCES task (id),"
            " FOREIGN KEY(student_id) REFERENCES \"user\" (id),"
            " UNIQUE(task_id, student_id))"
        )
    )
    try:
        if is_sqlite:
            # INSERT OR IGNORE：靠 UNIQUE 约束去重，重跑为 no-op。
            conn.execute(
                text(
                    "INSERT OR IGNORE INTO taskassignment "
                    "(id, task_id, student_id, assigned_at, completed_at) "
                    "SELECT lower(hex(randomblob(16))), t.id, t.student_id, t.created_at, "
                    "  CASE WHEN t.status = 'done' THEN t.created_at ELSE NULL END "
                    "FROM task t WHERE t.student_id IS NOT NULL"
                )
            )
        else:
            conn.execute(
                text(
                    "INSERT INTO taskassignment "
                    "(id, task_id, student_id, assigned_at, completed_at) "
                    "SELECT gen_random_uuid(), t.id, t.student_id, t.created_at, "
                    "  CASE WHEN t.status = 'done' THEN t.created_at ELSE NULL END "
                    "FROM task t WHERE t.student_id IS NOT NULL "
                    "  AND NOT EXISTS ("
                    "    SELECT 1 FROM taskassignment ta"
                    "    WHERE ta.task_id = t.id AND ta.student_id = t.student_id)"
                )
            )
    except OperationalError:
        # 偏序迁移：task 表还没建（首次启动由 init_db 建表并带新列），跳过即可。
        pass
