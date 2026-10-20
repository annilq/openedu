"""交互讲解场景融合（ADR-0061 决策 3 / 4 / ADR-0083 / ADR-0091）：知识点模板 → 题目实例。

ADR-0091 起，融合的产物是**有类型的** :class:`~app.domain.scene_spec.SceneSpec`：
``kind`` 外壳 + 一个主 :class:`~app.domain.figures.Figure` +（可选）一组选项图形
（原 ``optionGroup.items``——该嵌套层已删，选项组就是**图形数组**）。几何只此一种
写法：顶点不再摊平在规格顶层；题面命中的图形几何**替换主图形**（原「覆盖顶层
points/edges」的合并语义废止）。

三个生产函数：
- :func:`fuse_scene_spec`：纯函数，知识点模板 → SceneSpec（可选替换主图形）；
- :func:`scene_spec_from_figure`：盖章原语，身份键 → SceneSpec（key → 权威几何）；
- :func:`build_scene_spec_for_question`：生成 / 读取时构建本题快照（知识点模板）。

**不做双读**（ADR-0091）：模板 / 快照只认新形，旧形（顶层 ``points``/``edges``、
``optionGroup``、``derivedFrom``、``inputs``）经 :func:`normalize_scene_spec`
一律拒绝——存量旧数据由 ``scripts/migrate_scene_specs.py`` 一次性迁移，代码不留
适配分支。

**不猜图形**（ADR-0089）：本模块**不接收 ``stem`` / ``options``**——「扫题面 / 扫选项
文字反猜图形」的正则整族已随 ``scene_extract.py`` 一起删除。主图形替换的入口是
:func:`resolve_scene_spec_for_question` 的 ``figure`` 形参，由 AI 显式给出的身份键
经盖章取权威几何驱动（出题侧选项内嵌图形见 ``features/tasks``；答疑侧三层识别见
``ai/subagents/tutor/scene_intent.py``）。

匹配策略（学期维度，ADR-0061 发布任务对接资料库）：
- 优先精确命中 ``(subject, grade, name, semester)``（同知识点同学期的专属讲解）。
- 否则回落 ``semester=''``（整学年模板），让未指定学期的题也能复用整学年讲解。
- 任一命中即用，绝不抛错；无任何命中返回 ``None``，上层降级为纯文本讲解。

健壮性：任何环节缺失（无模板 / 模板非 list / 抽取失败）一律返回 ``None``，上层据此
降级为纯文本讲解，绝不抛错或下发畸形 payload（契合 ADR-0039 离线纪律）。

几何来源（ADR-0083）：模板自带的 ``figure`` 是**创作期内联**进去的权威几何；题面
点名了别的图形时，按 key 查 ``figure_library`` 表取其几何**替换主图形**——运行时
**不查代码常量** ``FIGURES``。
"""
from __future__ import annotations

from typing import Any

from sqlmodel import Session, select

from app.db.models import KnowledgePoint
from app.domain.figures import Figure
from app.domain.scene_spec import SceneSpec, normalize_scene_spec
from app.features.materials.scene_figures import figure_geometry

# reflection 的 kind 字面量（唯一实现的 kind，ADR-0073/0083）。盖章原语恒给这一种。
_REFLECTION_KIND = "reflection"


def resolve_kp_scene(kp: KnowledgePoint | None) -> list[dict] | None:
    """知识点场景的**唯一读取入口**（ADR-0073 v3）：薄读取器，返回 ``kp.scenes``。

    薄到近乎多余，但必须存在：此前 ``kp.scenes`` 的直读散落多处，每处各自判空、
    各自认定什么叫「配了场景」——这正是 ADR-0061 §U.4「同一个知识点换个地方就没
    图」的根因。统一走这里之后，「有没有配场景」才有唯一答案。

    刻意**不做**「外壳 base + per-kp override 合并」：v3 模型里 ``scenes`` 已经
    是完整自包含的真相；再叠一层合并只会造出第二个事实源，并把「改注册表影响
    已存数据」重新变成可能（那正是 ADR-0061 §U 快照铁律要排除的东西）。

    返回值是行上的**引用**而非深拷贝：本函数只用于「有没有」的判定与读取，
    需要落库 / 改写的调用方走 :func:`fuse_scene_spec`（它经校验入口产出全新对象）。
    """
    if kp is None:
        return None
    scenes = kp.scenes
    if not isinstance(scenes, list) or not scenes:
        # none_as_null=True 已让「清空」落为 SQL NULL；这里再挡一次非 list 的脏数据。
        return None
    return scenes


def fuse_scene_spec(
    kp_scenes: list[dict] | None,
    *,
    figure: Figure | None = None,
) -> SceneSpec | None:
    """把知识点场景模板融合成题目实例（ADR-0091：产 SceneSpec，几何收进 Figure）。

    - ``kp_scenes`` 为空 / 非 list → 返回 ``None``（该知识点暂无图形化讲解）。
    - 取第一个场景模板（首版每知识点单模板；多模板时按索引，后续可加选择器）。
    - 模板经 :func:`normalize_scene_spec` 校验：**只认新形**，旧形 / 畸形 →
      ``None``（不做双读；存量旧模板由迁移脚本改写，见模块 docstring）。
    - ``figure``（题面命中的图形，查图库得来）→ **替换主图形**；其余字段
     （``options`` / ``curated``）原样保留。``None`` → 仅用模板自身几何。
    """
    if not isinstance(kp_scenes, list) or not kp_scenes:
        return None
    spec = normalize_scene_spec(kp_scenes[0])
    if spec is None:
        return None
    if figure is not None:
        # 替换主图形（ADR-0091）：原「覆盖顶层 points/edges」语义已废止。
        # 显式重建而非 model_copy：替换只动 figure，kind/options/curated 原样带过去。
        spec = SceneSpec(
            kind=spec.kind, figure=figure, options=spec.options, curated=spec.curated
        )
    return spec


def scene_spec_from_figure(session: Session, figure_key: str | None) -> SceneSpec | None:
    """盖章原语（ADR-0089 §1 改名的产物）：身份键 → SceneSpec{kind=reflection, figure}。

    名字里**不再有「兜底 / 默认」**：那是旧链路的说法，会让人误以为这是一种降级路径。
    它其实是新链路的主路径——AI 给出图形身份键之后，「按该键取权威几何并产出纯几何
    场景」正是必须走的一步。

    几何的**唯一权威**是图形几何库（``figure_library`` 表）：本函数按 ``key`` 查它，
    拿不到该行 → ``None``（调用方据此不发射，绝不臆造一个图形）。产物带 ``key``：
    身份 / 溯源 / 校验用，渲染不消费（ADR-0091 决策 2 把 ADR-0083 决策 6「规格不含
    key」收窄为「渲染不消费 key」）。交互参数（对称轴初值 / controls / 引导文案）由
    前端按 kind 从外壳取，不进 spec（ADR-0083 决策 5）。
    """
    figure = figure_geometry(session, figure_key)
    if figure is None:
        return None
    return _stamp(figure)


def _stamp(figure: Figure) -> SceneSpec:
    """盖章：Figure → SceneSpec（reflection 外壳 + 该图形）。一条路径，一种形状。"""
    return SceneSpec(kind=_REFLECTION_KIND, figure=figure)


def scene_spec_for_read(
    session: Session,
    *,
    snapshot: Any,
    teacher_id: Any,
    subject: str,
    grade: int,
    knowledge_point: str,
    semester: str = "",
    cache: dict[tuple, SceneSpec | None] | None = None,
) -> SceneSpec | None:
    """读取路径的统一口径（ADR-0061 §U）：**快照优先 → 实时解析**。

    三处消费方（题库详情 / 错题本 / 任务详情）必须走**同一个函数**。此前各自内联
    ``q.scene_spec or build_...``，题库 REST 端点甚至整段漏写——于是同一道题
    「在任务详情有图、在题库详情没图」，排查时极易误判成前端渲染问题。

    - 有快照（出题时算好、贴合本题图形）→ 经 :func:`normalize_scene_spec` 校验后
      返回，知识点模板后续改动不影响已生成的题；**旧形 / 畸形快照一律拒绝**
      （ADR-0091 不做双读），回退实时解析；
    - 无快照（老数据 / 模板是后来才配的）→ 实时解析（按知识点 + 学期找模板）。

    ADR-0089 起**不再有 ``stem`` / ``options`` 形参**：读路径曾经用它们去「反猜图形」，
    正则整族已删（无模板、题面又点名了图形的老数据不再出图——这是删除猜测逻辑的
    既定代价，新内容由 AI 显式身份键接住；见模块 docstring）。
    """
    if isinstance(snapshot, dict) and snapshot:
        spec = normalize_scene_spec(snapshot)
        if spec is not None:
            return spec
        # 旧形 / 畸形快照：拒绝而非适配（不做双读），继续走实时解析。
    return build_scene_spec_for_question(
        session,
        teacher_id=teacher_id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        semester=semester,
        cache=cache,
    )


def resolve_scene_spec_for_question(
    session: Session,
    *,
    teacher_id: Any,
    subject: str,
    grade: int,
    knowledge_point: str,
    semester: str = "",
    figure: Figure | None = None,
    cache: dict[tuple, SceneSpec | None] | None = None,
) -> SceneSpec | None:
    """按题目归属的知识点解析其交互讲解实例。

    学期维度匹配（ADR-0061 发布任务对接资料库）：
    - 优先精确命中 ``(subject, grade, name, semester)``（同学期专属讲解）。
    - 否则回落 ``semester=''``（整学年模板）——未指定学期的题复用整学年讲解。
    命中多个时取最新一条；均无命中返回 ``None``，上层降级为纯文本讲解。

    ``figure``（ADR-0061 §M / ADR-0083 / ADR-0091）：题面命中的图形（查图库得来），
    **替换**模板主图形使场景贴合本题。**``cache`` 只在 ``figure`` 为空时可用**——
    缓存键只含 (知识点, 学期)，带题面图形时同一知识点不同题目的结果不同，混用会串味。

    ``cache``（可选）按 ``(teacher_id, subject, grade, knowledge_point, semester)`` 缓存，
    避免一页错题对同一「知识点 + 学期」反复查库。
    """
    if not knowledge_point:
        return None
    if figure is not None:
        # 带题面图形时不走缓存：同一知识点的不同题目结果不同。
        return _resolve_uncached(
            session,
            teacher_id=teacher_id,
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            semester=semester,
            figure=figure,
        )
    key = (str(teacher_id), subject, grade, knowledge_point, semester)
    if cache is not None and key in cache:
        return cache[key]
    result = _resolve_uncached(
        session,
        teacher_id=teacher_id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        semester=semester,
        figure=figure,
    )
    if cache is not None:
        cache[key] = result
    return result


def _resolve_uncached(
    session: Session,
    *,
    teacher_id: Any,
    subject: str,
    grade: int,
    knowledge_point: str,
    semester: str,
    figure: Figure | None,
) -> SceneSpec | None:
    """按 (学期精确 → 整学年回落) 找模板，题面图形替换主图形后融合。"""
    kp = find_knowledge_point(
        session,
        teacher_id=teacher_id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        semester=semester,
    )
    return fuse_scene_spec(
        kp.scenes if kp is not None else None,
        figure=figure,
    )


def find_knowledge_point(
    session: Session,
    *,
    teacher_id: Any,
    subject: str,
    grade: int,
    knowledge_point: str,
    semester: str = "",
    allow_partial: bool = False,
) -> KnowledgePoint | None:
    """按 (学期精确 → 整学年回落) 找知识点，**唯一匹配口径**（ADR-0061）。

    供目录投影（``figure_stamp.available_figures``）等调用方复用——避免第二处
    各自实现「怎么算匹配上」，那正是「同一知识点换个地方就没图」的复生点。

    [allow_partial]（ADR-0102）：``subject`` / ``grade`` 缺一时是否允许**按名字**落下。
    默认关——出题侧总带完整四元组（规格里有科目年级），放开只会把别的年级的知识点
    误当命中。但**答疑侧的 L0 门控**只有一句话和一个知识点名：「请为「图形的运动
    （轴对称）」出一道选择题」里根本没写「数学」「四年级」，四元组必有两格为空 →
    严格匹配恒不命中 → 门控不放行 → 场景永远不出图。故由调用方显式选择放宽，
    而不是把「猜」写进默认路径。
    """

    def _match(semester_filter: str) -> KnowledgePoint | None:
        return session.exec(
            select(KnowledgePoint)
            .where(
                KnowledgePoint.teacher_id == teacher_id,
                KnowledgePoint.subject == subject,
                KnowledgePoint.grade == grade,
                KnowledgePoint.name == knowledge_point,
                KnowledgePoint.semester == semester_filter,
            )
            .order_by(KnowledgePoint.created_at)
        ).first()

    # 优先同学期精确命中，否则回落整学年模板。
    kp = _match(semester) if semester else None
    if kp is None:
        kp = _match("")
    if kp is not None or not allow_partial:
        return kp
    return _find_by_name_only(
        session,
        teacher_id=teacher_id,
        knowledge_point=knowledge_point,
        subject=subject,
        grade=grade,
        semester=semester,
    )


def _find_by_name_only(
    session: Session,
    *,
    teacher_id: Any,
    knowledge_point: str,
    subject: str,
    grade: int,
    semester: str,
) -> KnowledgePoint | None:
    """``allow_partial`` 的回落：已知知识点名、但四元组不全时按名找行（ADR-0102）。

    用途单一——答疑侧 L0 门控：用户原话给了唯一确定的知识点名，却没说学科年级。
    **name 本身就是强证据**（同一老师下重名极少），比「查不到就不出图」正确。

    过滤规则：只固定 ``teacher_id``（归属不可穿越）+ 名字**完全相等**（不做子串模糊，
    那才叫猜）；有值的 ``subject`` / ``grade`` 仍参与过滤。排序：**配了 ``scenes``
    的行优先**（问场景就要能找到场景），其次同学期者，然后按创建时间——结果确定，
    不依赖数据库返回顺序。
    """
    stmt = select(KnowledgePoint).where(
        KnowledgePoint.teacher_id == teacher_id,
        KnowledgePoint.name == knowledge_point,
    )
    if subject:
        stmt = stmt.where(KnowledgePoint.subject == subject)
    if grade:
        stmt = stmt.where(KnowledgePoint.grade == grade)
    rows = list(session.exec(stmt.order_by(KnowledgePoint.created_at)).all())
    if not rows:
        return None
    if len(rows) == 1:
        return rows[0]

    def _rank(row: KnowledgePoint) -> tuple:
        configured = 1 if isinstance(row.scenes, list) and row.scenes else 0
        semester_hit = 1 if semester and row.semester == semester else 0
        return (-configured, -semester_hit, row.created_at)

    return sorted(rows, key=_rank)[0]


def build_scene_spec_for_question(
    session: Session,
    *,
    teacher_id: Any,
    subject: str,
    grade: int,
    knowledge_point: str,
    semester: str = "",
    cache: dict[tuple, SceneSpec | None] | None = None,
) -> SceneSpec | None:
    """按题目归属的知识点构建本题的场景快照（ADR-0061 §M/N/O / ADR-0091）。

    与读取路径共用同一套解析逻辑（:func:`resolve_scene_spec_for_question`），区别只在
    调用语境：出题时算好并**落库**（``Question/TaskQuestion.scene_spec``），落库后讲解
    走快照（模板再改也不影响已生成的题）；老数据没有快照时读路径回退到本函数。

    主图形此刻**只来自知识点模板**——教师配的就是权威。ADR-0089 删掉了「扫题面 /
    扫选项文字反猜图形」的正则整族，故本函数不再收 ``stem`` / ``options``；
    「按 AI 显式给出的身份键替换主图形」的入口保留在
    :func:`resolve_scene_spec_for_question` 的 ``figure`` 形参上（几何仍由图库盖章）。

    ``cache`` 透传给 :func:`resolve_scene_spec_for_question`（无主图形替换时可跨题复用
    同「知识点 + 学期」的解析结果）。
    """
    if not knowledge_point:
        return None
    return resolve_scene_spec_for_question(
        session,
        teacher_id=teacher_id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        semester=semester,
        cache=cache,
    )
