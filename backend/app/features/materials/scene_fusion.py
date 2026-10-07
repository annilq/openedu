"""交互讲解场景融合（ADR-0061 决策 3 / 4）：知识点模板 → 题目实例。

融合 = 取知识点 ``scenes`` 模板，用题面输入覆盖默认 ``inputs``，附 ``locked_answer``。
纯函数 :func:`fuse_scene_spec` 与带 DB 查找的 :func:`resolve_scene_spec_for_question`
共用同一套覆盖逻辑；读取路径（错题本 / 题卡）按 ``(teacher_id, subject, grade,
knowledge_point, semester)`` 解析知识点模板。

匹配策略（学期维度，ADR-0061 发布任务对接资料库）：
- 优先精确命中 ``(subject, grade, name, semester)``（同知识点同学期的专属讲解）。
- 否则回落 ``semester=''``（整学年模板），让未指定学期的题也能复用整学年讲解。
- 任一命中即用，绝不抛错；无任何命中返回 ``None``，上层降级为纯文本讲解。

健壮性：任何环节缺失（无模板 / 模板非 list / 抽取失败）一律返回 ``None``，上层据此
降级为纯文本讲解，绝不抛错或下发畸形 payload（契合 ADR-0039 离线纪律）。
"""
from __future__ import annotations

import copy
from typing import Any

from sqlmodel import Session, select

from app.db.models import KnowledgePoint
from app.features.materials.scene_extract import (
    extract_option_group,
    extract_scene_inputs,
)
from app.features.materials.scene_figures import figure_by_key
from app.features.materials.scene_templates import (
    apply_overrides,
    instantiate_builtin,
)


def resolve_kp_scene(kp: KnowledgePoint | None) -> list[dict] | None:
    """知识点场景的**唯一读取入口**（ADR-0073 v3）：薄读取器，返回 ``kp.scenes``。

    薄到近乎多余，但必须存在：此前 ``kp.scenes`` 的直读散落多处，每处各自判空、
    各自认定什么叫「配了场景」——这正是 ADR-0061 §U.4「同一个知识点换个地方就没
    图」的根因。统一走这里之后，「有没有配场景」才有唯一答案。

    刻意**不做**「注册表 base + per-kp override 合并」：v3 模型里 ``scenes`` 已经
    是完整自包含的真相；再叠一层合并只会造出第二个事实源，并把「改注册表影响
    已存数据」重新变成可能（那正是 ADR-0061 §U 快照铁律要排除的东西）。

    返回值是行上的**引用**而非深拷贝：本函数只用于「有没有」的判定与读取，
    需要落库 / 改写的调用方走 :func:`fuse_scene_spec`（它负责 deepcopy）。
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
    overrides: dict[str, Any] | None = None,
) -> dict | None:
    """把知识点场景模板融合成题目实例。

    - ``kp_scenes`` 为空 / 非 list → 返回 ``None``（该知识点暂无图形化讲解）。
    - 取第一个场景模板（首版每知识点单模板；多模板时按索引，后续可加选择器）。
    - 深拷贝模板，用 ``overrides``（题面抽取的输入值，``{input_key: value}``）覆盖
      同名 ``inputs[].value``；其余字段（kind / controls / timeline / narrative /
      outputs / locked_answer）原样保留。
    - **override 可以新增模板里没有的 input**（ADR-0061 §Q）：``points``（顶点）
      就是这么来的——教师早期配的模板里没有它，若只允许覆盖同名key，这些覆盖
      会被**静默丢弃**，场景就退回教师配的默认图形（等于改动没生效且无任何报错）。
    - ``overrides`` 为 ``None`` 或空 → 仅拷贝模板（出题时尚未抽取输入的常见情形）。
    """
    if not isinstance(kp_scenes, list) or not kp_scenes:
        return None
    template = kp_scenes[0]
    if not isinstance(template, dict):
        return None
    spec: dict[str, Any] = copy.deepcopy(template)
    # 合并语义下沉到 scene_templates.apply_overrides：注册表实例化与模板融合是
    # 同一套「按 key 覆盖 + 补新项」逻辑，两份实现迟早漂移。
    return apply_overrides(spec, overrides)


def default_scene_from_figure(figure_key: str | None) -> dict | None:
    """图库兜底场景（ADR-0061 §U）：没配模板、但题面点名了图形时的默认演示。

    为什么必须有兜底：讲解的**几何**权威来源是图库（``scene_figures``），教师模板
    只提供默认参数（默认哪个图形、轴多少度）。题面明写「正方形」时，图库里本来
    就有权威顶点——「没配模板就不出图」会让「正方形有几条对称轴」这类**最典型**
    的题裸奔，教师看到的就是「功能没做」。

    边界（防臆造，与 :func:`extract_scene_inputs` 同一纪律）：**只有题面/选项确实
    命中了图库图形才生成**。命中不了（纯计算题「图书馆有 86 本书」）返回 ``None``
    ——那种题本来也没有图形可讲，硬给一个图形就是编。

    ``outputs.isAxisymmetric`` **如实取** ``axis_count > 0``（平行四边形 = False），
    不写死 True——写死等于替学生答了「它是不是轴对称图形」。
    """
    shape = figure_by_key(figure_key)
    if shape is None:
        return None
    # 结构（inputs 骨架 / controls / editable）一律向注册表取——这样「默认位置
    # 0.5」「axisAngle 的取值范围与单位」只有一处定义。此前这里是手写整份 dict，
    # 与前端 ReflectionSceneData、编辑器 _buildSpec 三份互为镜像，改一处漏两处。
    spec = instantiate_builtin(
        "reflection",
        overrides={
            "axisAngle": shape.default_axis_angle,
            "figure": shape.key,
            "points": [[x, y] for x, y in shape.vertices],
        },
    )
    if spec is None:
        # 注册表里没有 reflection 属部署异常；此时宁可降级纯文本，也不按旧的
        # 手写副本就地重造一份——那样等于把刚收拢的默认值重新抄回去。
        return None
    # 这三项只有知道具体图形才写得出，由实例化方补齐（注册表刻意保持中性：
    # 见 scene_templates 模块 docstring 边界 3 / 4）。
    spec["title"] = f"{shape.label}·轴对称"
    spec["narrative"] = (
        f"这是{shape.label}。点播放看沿对称轴对折后两侧能否完全重合；"
        "也可以自己旋转、平移对称轴，找出所有能重合的角度。"
    )
    spec["outputs"] = {"isAxisymmetric": shape.axis_count > 0}
    # 来源标记：教师配了模板后会被模板覆盖，便于排查「这图是谁给的」。
    spec["derivedFrom"] = "figure_library"
    return spec


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
    cache: dict[tuple, dict | None] | None = None,
) -> dict | None:
    """读取路径的统一口径（ADR-0061 §U）：**快照优先 → 实时解析（含图库兜底）**。

    三处消费方（题库详情 / 错题本 / 任务详情）必须走**同一个函数**。此前各自内联
    ``q.scene_spec or build_...``，题库 REST 端点甚至整段漏写——于是同一道题
    「在任务详情有图、在题库详情没图」，排查时极易误判成前端渲染问题。

    - 有快照（出题时算好、贴合本题图形与角度）→ 直接返回，知识点模板后续改动
      不影响已生成的题；
    - 无快照（老数据 / 模板是后来才配的）→ 实时解析，仍无则**图库兜底**。
    """
    if isinstance(snapshot, dict) and snapshot:
        return snapshot
    return build_scene_spec_for_question(
        session,
        teacher_id=teacher_id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        semester=semester,
        stem=stem,
        options=options,
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
    overrides: dict[str, Any] | None = None,
    cache: dict[tuple, dict | None] | None = None,
) -> dict | None:
    """按题目归属的知识点解析其交互讲解实例。

    学期维度匹配（ADR-0061 发布任务对接资料库）：
    - 优先精确命中 ``(subject, grade, name, semester)``（同学期专属讲解）。
    - 否则回落 ``semester=''``（整学年模板）——未指定学期的题复用整学年讲解。
    命中多个时取最新一条；均无命中返回 ``None``，上层降级为纯文本讲解。

    ``overrides``（ADR-0061 §M）：题面抽出的输入值（图形/角度），覆盖模板默认值
    使场景贴合本题。**``cache`` 只在 ``overrides`` 为空时可用**——缓存键只含
    (知识点, 学期)，带 overrides 时同一知识点不同题目的结果不同，混用会串味。

    ``cache``（可选）按 ``(teacher_id, subject, grade, knowledge_point, semester)`` 缓存，
    避免一页错题对同一「知识点 + 学期」反复查库。
    """
    if not knowledge_point:
        return None
    if overrides:
        # 带题面值时不走缓存：同一知识点的不同题目结果不同。
        return _resolve_uncached(
            session,
            teacher_id=teacher_id,
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            semester=semester,
            overrides=overrides,
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
        overrides=overrides,
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
    overrides: dict[str, Any] | None,
) -> dict | None:
    """按 (学期精确 → 整学年回落) 找模板，叠加题面 overrides 后融合。"""

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
    return fuse_scene_spec(
        kp.scenes if kp is not None else None,
        overrides=overrides,
    )


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
    cache: dict[tuple, dict | None] | None = None,
) -> dict | None:
    """生成时构建本题的场景快照（ADR-0061 §M/N/O）。

    =「按学期找知识点模板」+「从题面抽数值」+「融合」，与读取路径共用同一套逻辑，
    区别只在于**结果会被落库**（``Question/TaskQuestion.scene_spec``）。落库后
    讲解走快照（模板再改也不影响已生成的题）；老数据没有快照时才回退本函数。

    **选项组**（ADR-0061 §O）：选择题里每个选项自带一个图形时，把
    ``optionGroup`` 一并挂上（每个选项带自己的顶点），前端渲染成多个独立可交互的
    场景——学生逐个亲手试，而不是看程序报答案。任一选项识别不出则不挂（见
    :func:`extract_option_group`的「全-or-无」）。

    ``stem``/``options`` 缺省（不传）时退化为「纯模板拷贝」——等价于旧行为。
    ``cache`` 透传给 :func:`resolve_scene_spec_for_question`（仅在抽不到题面值、
    即overrides 为空时生效——带题面值的不能跨题复用）。
    """
    if not knowledge_point:
        return None
    overrides = extract_scene_inputs(stem=stem, options=options)
    spec = resolve_scene_spec_for_question(
        session,
        teacher_id=teacher_id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        semester=semester,
        overrides=overrides,
        cache=cache,
    )
    if spec is None:
        # 图库兜底（ADR-0061 §U）：没有模板时，只要题面点名了图形就照样出图。
        # 再走一遍 fuse 是为了让题面角度（如「沿 45° 对折」）也覆盖到兜底场景上。
        fallback = default_scene_from_figure(overrides.get("figure"))
        if fallback is None:
            return None
        spec = fuse_scene_spec([fallback], overrides=overrides) or fallback
    group = extract_option_group(options)
    if group is not None:
        # 顶层挂optionGroup（不放进 inputs）——它不是可调输入项，而是「同一模板
        # 派生多份实例」的指令；放inputs 里会被 fromSpec 当成单图输入解析。
        spec["optionGroup"] = group
        # 选项组里**每个选项的判定各不相同**（房子对称、平行四边形不对称），父级
        # 不该给一个统一结论——兜底场景的结论来自「题面第一个命中的图形」，
        # 与其余选项无关，留着就是给错答案。教师模板的 outputs 不动（那是他配的）。
        if spec.get("derivedFrom") == "figure_library":
            spec.pop("outputs", None)
    return spec
