"""知识点聚焦解析（ADR-0080 / ai-prompts-hardening ticket 02）。

把会话传入的 ``knowledge_point_id`` 经归属校验解析为结构化四元组
``(subject, grade, semester, name)``，供 tutor / query 两个 subagent 在系统提示里拼
一段**独立**的【知识点聚焦】段（与 ``tutor_system_prompt`` 安全锁物理分离）。

越权 / 缺失 → ``None``（调用方据此不注入，无越权数据泄漏）。解析只经
``core.guard.find_owned``（分层不变量 9），与 ``build_actions`` 同源但走软判定：
取不到就当没配（不抛错、不阻断主链路）。
"""
from __future__ import annotations

from uuid import UUID

from app.core.guard import find_owned
from app.db.models.material import KnowledgePoint


def resolve_kp_focus(*, session, owner_id: UUID, kp_id: UUID | None) -> dict | None:
    """经 ``find_owned`` 归属校验取知识点四元组；非己方 / 缺失 → ``None``。

    归属口径即 ``KnowledgePoint.teacher_id``（与资料库一致）。越权或不存在时
    ``find_owned`` 返回 ``None``，调用方据此不注入聚焦段。
    """
    if not kp_id:
        return None
    kp = find_owned(session=session, owner_id=owner_id, model=KnowledgePoint, obj_id=kp_id)
    if kp is None:
        return None
    return {
        "subject": kp.subject,
        "grade": kp.grade,
        "semester": kp.semester or "",
        "name": kp.name,
    }


def format_kp_focus(focus: dict | None, *, query_mode: bool = False) -> str:
    """拼【知识点聚焦】段。``query_mode`` 给 query subagent 额外加一句「查询须依托工具数据」。

    无聚焦（``None`` 或空 name）→ 空串，调用方据此不追加任何段（无回归）。
    """
    if not focus or not focus.get("name"):
        return ""
    seg = (
        f"【知识点聚焦】本会话聚焦：「{focus['name']}」（{focus['subject']} · "
        f"{focus['grade']}年级 · {focus['semester'] or '整学年'}）。\n"
        "回答请围绕该知识点展开；若用户明显偏向其它知识点，先简要回答再询问是否切换焦点。"
    )
    if query_mode:
        seg += "\n查询仍须依托工具数据，不要凭空作答。"
    return seg
