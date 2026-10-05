"""交互讲解场景融合（ADR-0061 决策 3 / 4）：知识点模板 → 题目实例。

融合 = 取知识点 ``scenes`` 模板，用题面输入覆盖默认 ``inputs``，附 ``locked_answer``。
纯函数 :func:`fuse_scene_spec` 与带 DB 查找的 :func:`resolve_scene_spec_for_question`
共用同一套覆盖逻辑；读取路径（错题本 / 题卡）按 ``(parent_id, subject, grade,
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
    inputs = spec.get("inputs")
    if isinstance(inputs, list) and overrides:
        merged: list[Any] = [
            {
                **inp,
                "value": (
                    overrides.get(inp["key"], inp.get("value"))
                    if isinstance(inp, dict) and "key" in inp
                    else inp.get("value") if isinstance(inp, dict) else inp
                ),
            }
            if isinstance(inp, dict)
            else inp
            for inp in inputs
        ]
        # 模板里没有、但 override 提供了的 key → 补进去（否则被静默忽略）。
        # 标注 generated=True 便于区分「教师配的」与「按本题算出来的」，
        # 将来若做「模板编辑器只展示教师配的项」之类的功能时不必再猜。
        present = {
            inp.get("key")
            for inp in inputs
            if isinstance(inp, dict) and inp.get("key") is not None
        }
        for key, value in overrides.items():
            if key not in present:
                merged.append({"key": key, "value": value, "generated": True})
        spec["inputs"] = merged
    return spec


def resolve_scene_spec_for_question(
    session: Session,
    *,
    parent_id: Any,
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

    ``cache``（可选）按 ``(parent_id, subject, grade, knowledge_point, semester)`` 缓存，
    避免一页错题对同一「知识点 + 学期」反复查库。
    """
    if not knowledge_point:
        return None
    if overrides:
        # 带题面值时不走缓存：同一知识点的不同题目结果不同。
        return _resolve_uncached(
            session,
            parent_id=parent_id,
            subject=subject,
            grade=grade,
            knowledge_point=knowledge_point,
            semester=semester,
            overrides=overrides,
        )
    key = (str(parent_id), subject, grade, knowledge_point, semester)
    if cache is not None and key in cache:
        return cache[key]
    result = _resolve_uncached(
        session,
        parent_id=parent_id,
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
    parent_id: Any,
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
                KnowledgePoint.parent_id == parent_id,
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
    parent_id: Any,
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
        parent_id=parent_id,
        subject=subject,
        grade=grade,
        knowledge_point=knowledge_point,
        semester=semester,
        overrides=overrides,
        cache=cache,
    )
    if spec is None:
        return None
    group = extract_option_group(options)
    if group is not None:
        # 顶层挂optionGroup（不放进 inputs）——它不是可调输入项，而是「同一模板
        # 派生多份实例」的指令；放inputs 里会被 fromSpec 当成单图输入解析。
        spec["optionGroup"] = group
    return spec
