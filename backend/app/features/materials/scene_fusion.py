"""交互讲解场景融合（ADR-0061 决策 3 / 4 / ADR-0083 / ADR-0091）：知识点模板 → 题目实例。

ADR-0091 起，融合的产物是**有类型的** :class:`~app.domain.scene_spec.SceneSpec`：
``kind`` 外壳 + 一个主 :class:`~app.domain.figures.Figure` +（可选）一组选项图形
（原 ``optionGroup.items``——该嵌套层已删，选项组就是**图形数组**）。几何只此一种
写法：顶点不再摊平在规格顶层；题面命中的图形几何**替换主图形**（原「覆盖顶层
points/edges」的合并语义废止）。

三个生产函数：
- :func:`fuse_scene_spec`：纯函数，知识点模板 → SceneSpec（可选替换主图形）；
- :func:`scene_spec_from_figure`：盖章原语，图库 key → SceneSpec（图库兜底）；
- :func:`build_scene_spec_for_question`：生成时构建本题快照（抽题面图形 + 融合）。

**不做双读**（ADR-0091）：模板 / 快照只认新形，旧形（顶层 ``points``/``edges``、
``optionGroup``、``derivedFrom``、``inputs``）经 :func:`normalize_scene_spec`
一律拒绝——存量旧数据由 ``scripts/migrate_scene_specs.py`` 一次性迁移，代码不留
适配分支。

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
from app.features.materials.scene_extract import extract_scene_inputs
from app.features.materials.scene_figures import figure_geometry

# reflection 的 kind 字面量（唯一实现的 kind，ADR-0073/0083）。图库兜底只出这一种。
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
    """盖章原语（ADR-0091）：图库 key → SceneSpec{kind=reflection, figure=Figure}。

    为什么必须有兜底：讲解的**几何**权威来源是图库（``figure_library`` 表）。题面
    明写「正方形」时，图库里本来就有权威顶点——「没配模板就不出图」会让「正方形有
    几条对称轴」这类**最典型**的题裸奔，教师看到的就是「功能没做」。

    边界（防臆造，与 :func:`extract_scene_inputs` 同一纪律）：**只有题面确实
    命中了图库图形才生成**。命中不了（纯计算题「图书馆有 86 本书」）返回 ``None``
    ——那种题本来也没有图形可讲，硬给一个图形就是编。

    产物带图库 ``key``：身份 / 溯源 / 校验用，渲染不消费（ADR-0091 决策 2 反转
    ADR-0083 决策 6：「规格不含 key」收窄为「渲染不消费 key」）。交互参数（对称轴
    初值 / controls / 引导文案）由前端按 kind 从外壳取，不进 spec（ADR-0083 决策 5）。
    """
    figure = figure_geometry(session, figure_key)
    if figure is None:
        return None
    return _stamp(figure)


def _stamp(figure: Figure) -> SceneSpec:
    """盖章：Figure → SceneSpec（reflection 外壳 + 该图形）。图库兜底与题面替换共用。"""
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
    stem: str | None = None,
    options: list[str] | None = None,
    cache: dict[tuple, SceneSpec | None] | None = None,
) -> SceneSpec | None:
    """读取路径的统一口径（ADR-0061 §U）：**快照优先 → 实时解析（含图库兜底）**。

    三处消费方（题库详情 / 错题本 / 任务详情）必须走**同一个函数**。此前各自内联
    ``q.scene_spec or build_...``，题库 REST 端点甚至整段漏写——于是同一道题
    「在任务详情有图、在题库详情没图」，排查时极易误判成前端渲染问题。

    - 有快照（出题时算好、贴合本题图形）→ 经 :func:`normalize_scene_spec` 校验后
      返回，知识点模板后续改动不影响已生成的题；**旧形 / 畸形快照一律拒绝**
      （ADR-0091 不做双读），回退实时解析；
    - 无快照（老数据 / 模板是后来才配的）→ 实时解析，仍无则**图库兜底**。

    ``options`` 暂不参与生产（ADR-0091 ticket 02：扫选项文字反猜图形的路径已删，
    逐选项图形由 AI 链路「模型引用身份键 + 盖章」接回）；保留形参是为呼叫方零
    改动，AI 链路票接回时它重新生效。
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
        stem=stem,
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
) -> KnowledgePoint | None:
    """按 (学期精确 → 整学年回落) 找知识点，**唯一匹配口径**（ADR-0061）。

    供目录投影（``figure_stamp.available_figures``）等调用方复用——避免第二处
    各自实现「怎么算匹配上」，那正是「同一知识点换个地方就没图」的复生点。
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
    return kp


def build_scene_spec_for_question(
    session: Session,
    *,
    teacher_id: Any,
    subject: str,
    grade: int,
    knowledge_point: str,
    semester: str = "",
    stem: str | None = None,
    options: list[str] | None = None,
    cache: dict[tuple, SceneSpec | None] | None = None,
) -> SceneSpec | None:
    """生成时构建本题的场景快照（ADR-0061 §M/N/O / ADR-0083 / ADR-0091）。

    =「按学期找知识点模板」+「从题面抽命中的图形，查图库取几何**替换主图形**」+
    「融合」，与读取路径共用同一套逻辑，区别只在于**结果会被落库**
    （``Question/TaskQuestion.scene_spec``）。落库后讲解走快照（模板再改也不影响
    已生成的题）；老数据没有快照时才回退本函数。

    **选项组不再在这里挂载**（ADR-0091 ticket 02）：扫选项文字反猜图形的路径已删，
    逐选项图形改由 AI 链路「模型引用身份键 + 盖章」接回——届时每个选项带的是图库
    身份键，不再是展示名反猜。``options`` 形参为此保留（呼叫方零改动），接回时生效。

    ``stem`` 缺省（不传）时退化为「纯模板拷贝」——等价于旧行为。
    ``cache`` 透传给 :func:`resolve_scene_spec_for_question`（仅在抽不到题面图形、
    即无主图形替换时生效——带题面图形的不能跨题复用）。
    """
    if not knowledge_point:
        return None
    figure_key = extract_scene_inputs(stem=stem).get("figure")
    figure = figure_geometry(session, figure_key)
    spec = resolve_scene_spec_for_question(
        session,
        teacher_id=teacher_id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        semester=semester,
        figure=figure,
        cache=cache,
    )
    if spec is None:
        # 图库兜底（ADR-0061 §U）：没有模板时，只要题面点名了图形就照样出图。
        if figure is None:
            return None
        return _stamp(figure)
    return spec
