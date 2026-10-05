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
        spec["inputs"] = [
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
    return spec


def resolve_scene_spec_for_question(
    session: Session,
    *,
    parent_id: Any,
    subject: str,
    grade: int,
    knowledge_point: str,
    semester: str = "",
    cache: dict[tuple, dict | None] | None = None,
) -> dict | None:
    """按题目归属的知识点解析其交互讲解实例（读取路径用）。

    学期维度匹配（ADR-0061 发布任务对接资料库）：
    - 优先精确命中 ``(subject, grade, name, semester)``（同学期专属讲解）。
    - 否则回落 ``semester=''``（整学年模板）——未指定学期的题复用整学年讲解。
    命中多个时取最新一条；均无命中返回 ``None``，上层降级为纯文本讲解。

    ``cache``（可选）按 ``(parent_id, subject, grade, knowledge_point, semester)`` 缓存，
    避免一页错题对同一「知识点 + 学期」反复查库。
    """
    if not knowledge_point:
        return None
    key = (str(parent_id), subject, grade, knowledge_point, semester)
    if cache is not None and key in cache:
        return cache[key]

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
    result = fuse_scene_spec(kp.scenes if kp is not None else None)
    if cache is not None:
        cache[key] = result
    return result
