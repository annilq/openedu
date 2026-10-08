"""课件服务编排（ADR-0067 切片 3）：列表 / 新建（AI 起草）/ 读 / 改 / 覆盖写环节 / 删。

三条纪律贯穿本模块：

1. **未配模型不可起草**（ADR-0039：无离线 mock、无内置模型目录）。起草拿不到
   引擎就直接 ``LLM_UNAVAILABLE``，**绝不落一份空环节课件**——那等于把「没有
   内容」伪装成「有内容」（ADR-0066 同款纪律）。
2. **失败分类不抹平**（ADR-0038 / docs/agents/ai.md §2）：
   - 未配模型 → ``LLM_UNAVAILABLE``（下一步是「模型管理」里加模型）；
   - 厂商拒绝（认证 / 限流 / 网络）→ ``LLM_REQUEST_FAILED`` 带 ``user_hint``；
   - 产出解析不出环节 → ``LLM_REQUEST_FAILED`` 带**实际原因**（不是「请添加模型」）。
   三者用户可采取的行动完全不同，合成一句等于让用户照着错的指引修。
3. **归属只经 ``core.guard``**：取课件 / 取知识点都走 ``require_owned``，本模块
   不内联比较 ``teacher_id``（分层不变量 9）。

``draft_sections`` 单独成一个函数且只吃普通参数：它是 AI 边界，测试要替换它
（不打真实模型）。
"""

from __future__ import annotations

import copy
import json
import uuid
import warnings
from collections import defaultdict

from sqlmodel import Field, Session, SQLModel

from agent_core.errors import ProviderRequestError
from agent_core.ports import StructuredDone
from app.core.ai_plumbing import build_ai_provider
from app.core.async_bridge import run_async
from app.core.errors import AppErrorException, ErrCode
from app.core.guard import require_owned
from app.db.models import (
    COURSEWARE_STATUSES,
    SECTION_KINDS,
    Courseware,
    KnowledgePoint,
    get_datetime_utc,
)
from app.features.courseware import repository as repo
from app.features.courseware.schemas import (
    CoursewareCreate,
    CoursewareRedraftDiff,
    CoursewareResp,
    CoursewareSection,
    CoursewareSectionsUpdate,
    CoursewareUpdate,
    SectionDiffItem,
)
from app.features.materials.scene_fusion import resolve_kp_scene

# 起草时喂给模型的资料片段条数与单条截断长度（prompt 预算，不是检索参数）。
_SNIPPET_TOP_K = 5
_SNIPPET_CHARS = 300
_PROMPT_TEXT_LIMIT = 2000

_DRAFT_SYSTEM = (
    "你是 K12 教研助手，为教师备一份「按知识点讲解」的课件。\n"
    "产出 3-4 个**有序**环节，每个环节形如 "
    '{"id": "", "kind": ..., "title": "...", "script": "...", "payload": {...}}。\n'
    "kind 只能是这三个之一，**不接受其它字符串**：\n"
    '- "media_gallery"：出示 / 欣赏素材（生活中的实例、建筑与艺术）。'
    'payload = {"items": [], "prompt": "给学生的观察提示"}；素材由教师随后上传，items 先留空数组。\n'
    '- "interactive_scene"：交互探究 / 判定。payload **直接嵌一份 SceneSpec**，形如 '
    '{"kind": "reflection", "title": "...", "inputs": [{"key": "axisAngle", "label": "对称轴角度", '
    '"value": 90, "min": 0, "max": 180, "step": 1, "unit": "度"}, {"key": "points", "label": "顶点", '
    '"value": [[0.3,0.7],[0.7,0.7],[0.7,0.45],[0.5,0.25],[0.3,0.45]]}], '
    '"controls": {"play": true, "pause": true, "scrub": true, "speed": true}, '
    '"narrative": "引导动手试的话", "outputs": {"isAxisymmetric": true}}。\n'
    '- "practice"：课堂练习。payload = {"qtype": "choice", "count": 3, "hints": ["..."]}。\n'
    "script 是**投给学生看的提问卡话术**（一句可直接念出来的提问，如"
    "「这些图形有什么共同点？」），不要写成流程说明或教师备注。\n"
    "title 是环节标题，12 字以内。id 留空字符串，由后端生成。\n"
    "只输出 JSON。"
)


class _DraftSection(SQLModel):
    """模型产出的单个环节（输出契约，字段宽松——校验与收敛在 service 层）。"""

    id: str = ""
    kind: str = ""
    title: str = ""
    script: str = ""
    payload: dict = Field(default_factory=dict)
    # 内容块统一化：起草产物也可选填顶层素材 / 场景（旧起草只走 payload 内嵌）。
    materials: list[dict] = Field(default_factory=list)
    scene: dict | None = Field(default=None)


class _CoursewareDraft(SQLModel):
    """模型产出的整份草稿。"""

    sections: list[_DraftSection] = Field(default_factory=list)


# ── 环节校验 ────────────────────────────────────────────────────────────


def validate_section_kinds(sections: list[CoursewareSection]) -> None:
    """环节 kind 必须在注册表内（ADR-0067 §3.3：不接受自由字符串）。

    前端提交与 AI 起草**共用这一道校验**——起草产物若藏着一个未登记的 kind，
    落库后演示页分派不到渲染器，教师只看到「点了没反应」。
    """
    for s in sections:
        if s.kind not in SECTION_KINDS:
            raise AppErrorException(
                ErrCode.COURSEWARE_BAD_KIND,
                f"未知的环节类型：{s.kind or '<空>'}（只能是 {' / '.join(SECTION_KINDS)}）",
            )


def _store_sections(sections: list[CoursewareSection]) -> list[dict] | None:
    """环节序列 → 落库形态。

    ⚠️ 空列表一律写成 ``None``（真 SQL NULL）：该列是 ``JSON(none_as_null=True)``，
    写 ``[]`` 会让「有环节吗」的判断退化成「列表是不是空」两种口径；写 NULL 后
    ``sections IS NULL`` 就是唯一的空语义（ADR-0061 §N / ADR-0067 §3.2）。
    """
    if not sections:
        return None
    return [_section_to_dict(s) for s in sections]


def _section_to_dict(s: CoursewareSection) -> dict:
    return {
        "id": s.id or uuid.uuid4().hex[:8],
        "kind": s.kind,
        "title": s.title,
        "script": s.script,
        # T02：话术多段化——整列覆盖写时把段列表一并落库（不丢字段）。
        "script_segments": [
            {"text": seg.text, "emphasis": seg.emphasis}
            for seg in (s.script_segments or [])
        ],
        "payload": s.payload or {},
        # 内容块统一化：素材 / 场景与 kind 解耦的顶层字段（旧数据这两键缺失，落库
        # 为缺省值，前端回退 payload 内嵌；新数据优先走顶层字段）。
        "materials": s.materials or [],
        "scene": s.scene,
    }


def _fill_ids(sections: list[CoursewareSection]) -> list[CoursewareSection]:
    """前端新建环节时不必预先发号——空的 id 由后端补（同份课件内唯一）。"""
    for s in sections:
        if not s.id:
            s.id = uuid.uuid4().hex[:8]
    return sections


# ── AI 起草 ─────────────────────────────────────────────────────────────


def _recall_snippets(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    kp_name: str,
    subject: str | None,
    grade: int | None,
) -> list[str]:
    """召回该知识点下的资料片段（走 ``materials.retrieval``，按 knowledge_point 过滤）。

    **召回不到就返回空列表，不报错**：没有资料只是让起草少一个依据，知识点元
    信息（名称 / 学科 / 年级 / 学期）仍足以起草（§3.4）。把检索失败抛成 500 会让
    「没传教材」与「服务坏了」混为一谈——那正是 ADR-0038 要分开的东西。
    """
    try:
        chunks = _retriever(session, teacher_id).retrieve(
            subject=subject or "",
            grade=grade or 0,
            knowledge_point=kp_name,
            query=kp_name,
        )
    except Exception as e:  # noqa: BLE001 — 检索是起草的可选依据，失败只降级不阻塞
        warnings.warn(f"课件起草跳过资料召回：{e}", stacklevel=2)
        return []
    return [(c.content or "")[:_SNIPPET_CHARS] for c in chunks[:_SNIPPET_TOP_K]]


def _retriever(session: Session, teacher_id: uuid.UUID):
    from app.features.materials.retrieval import VectorKnowledgeRetriever

    return VectorKnowledgeRetriever(session, teacher_id)


def draft_sections(
    *,
    session: Session,
    teacher_id: uuid.UUID,
    kp_name: str,
    subject: str | None = None,
    grade: int | None = None,
    semester: str | None = None,
    snippets: list[str] | None = None,
) -> list[CoursewareSection]:
    """为一个知识点起草环节序列（ADR-0067 §3.4：AI 起草 + 教师调）。

    引擎与失败分类照 ``materials`` 的 AI 路径（同一条 ``build_ai_provider`` 链）：
    未配模型 → ``LLM_UNAVAILABLE``；厂商拒绝 → ``LLM_REQUEST_FAILED``（带
    ``user_hint``）；产出不可用 → ``LLM_REQUEST_FAILED``（带实际原因）。

    单独成函数、只吃普通参数：测试 monkeypatch 它就完全不打模型。

    ⚠️ 起草结果里**没有**任何合法 kind 的环节时抛错，不返回空列表——空课件是
    「把没有内容伪装成有内容」。
    """
    provider = build_ai_provider(teacher_id=teacher_id, session=session)
    if not getattr(provider, "configured", True):
        raise AppErrorException(
            ErrCode.LLM_UNAVAILABLE,
            "未配置模型，无法起草课件（请在「模型管理」中添加模型并设为默认）",
        )

    prompt = (
        f"知识点：{kp_name}\n"
        f"学科：{subject or '未指定'}\n"
        f"年级：{grade or '未指定'}\n"
        f"学期：{semester or '未指定'}\n"
    )
    if snippets:
        prompt += "该知识点下的教材片段（唯一的内容依据，不要超出它的范围编造）：\n"
        prompt += "\n".join(f"- {s}" for s in snippets)
    prompt = prompt[:_PROMPT_TEXT_LIMIT]

    try:
        data = run_async(_collect_draft(provider, prompt))
    except ProviderRequestError as e:
        raise AppErrorException(
            ErrCode.LLM_REQUEST_FAILED, f"AI 起草课件失败：{e.user_hint}"
        ) from e
    except Exception as e:  # noqa: BLE001 — 归类后抛出，绝不抹成「请添加模型」
        raise AppErrorException(
            ErrCode.LLM_REQUEST_FAILED, f"AI 起草课件失败：{e}"
        ) from e

    return _sections_from_draft(data)


async def _collect_draft(provider, prompt: str):
    """跑一次结构化调用，取 ``StructuredDone`` 的载荷（拿不到则为 ``None``）。"""
    async for ev in provider.stream(_DRAFT_SYSTEM, prompt, schema=_CoursewareDraft):
        if isinstance(ev, StructuredDone):
            return ev.data
    return None


def _sections_from_draft(data: object) -> list[CoursewareSection]:
    """模型载荷 → 环节序列；不可用则抛 ``LLM_REQUEST_FAILED``（带实际原因）。

    未知 kind **直接丢弃**（§3.3：不接受自由字符串）——但全丢完等于没有内容，
    那就如实报错，不落空课件。
    """
    if not data:
        raise AppErrorException(
            ErrCode.LLM_REQUEST_FAILED, "AI 起草课件失败：模型没有返回任何内容"
        )
    try:
        draft = _CoursewareDraft.model_validate(data)
    except Exception as e:  # noqa: BLE001 — 原因要给人看，但不抹成「请添加模型」
        raise AppErrorException(
            ErrCode.LLM_REQUEST_FAILED, f"AI 起草课件失败：模型输出不是课件草稿格式（{e}）"
        ) from e

    sections: list[CoursewareSection] = []
    for raw in draft.sections:
        if raw.kind not in SECTION_KINDS:
            continue
        sections.append(
            CoursewareSection(
                id=raw.id or uuid.uuid4().hex[:8],
                kind=raw.kind,
                title=(raw.title or "")[:128],
                script=(raw.script or "")[:2000],
                payload=raw.payload if isinstance(raw.payload, dict) else {},
                # 内容块统一化：透传顶层素材 / 场景（LLM 当前不生成，留作前向兼容）。
                materials=raw.materials if isinstance(raw.materials, list) else [],
                scene=raw.scene if isinstance(raw.scene, dict) else None,
            )
        )
    if not sections:
        raise AppErrorException(
            ErrCode.LLM_REQUEST_FAILED,
            "AI 起草课件失败：模型给出的环节类型都不在注册表内"
            f"（只能是 {' / '.join(SECTION_KINDS)}）",
        )
    return sections


def _section_match_key(s: "CoursewareSection") -> tuple[str, str]:
    """匹配键 = (kind, title)：同名同类型的环节视为「同一环节」去对照。"""
    return (s.kind, s.title)


def _segment_signature(s: "CoursewareSection") -> str:
    """话术段的可比较指纹（文本 + 重点），忽略顺序差异之外的内容。"""
    return json.dumps(
        [(seg.text, seg.emphasis) for seg in (s.script_segments or [])],
        ensure_ascii=False,
        sort_keys=True,
    )


def _same_section_content(a: "CoursewareSection", b: "CoursewareSection") -> bool:
    """两段字面上的内容是否一致（标题 / 话术 / 多段话术 / payload 都相同才算 unchanged）。"""
    return (
        a.title == b.title
        and a.script == b.script
        and _segment_signature(a) == _segment_signature(b)
        and a.payload == b.payload
        and a.materials == b.materials
        and a.scene == b.scene
    )


def compute_section_diff(
    current: list["CoursewareSection"],
    drafted: list["CoursewareSection"],
) -> list[SectionDiffItem]:
    """对照当前稿与新草稿，产出逐段 diff（T07）。

    匹配以 (kind, title) 为键、按出现顺序消费（允许同名多段）：

    - 草稿有、当前有同键 → ``modified``（内容不同）/ ``unchanged``（内容相同）；
    - 草稿有、当前没有 → ``added``；
    - 当前有、草稿没有 → ``removed``（附在 diff 末尾，UI 默认保留）。

    顺序：先按草稿顺序铺 ``added`` / ``modified`` / ``unchanged``，再把余下未匹配的
    当前稿以 ``removed`` 收尾——合并时直接按 diff 顺序拼接被选段即可。
    """
    avail: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for s in current:
        avail[_section_match_key(s)].append({"sec": s, "used": False})

    items: list[SectionDiffItem] = []
    for d in drafted:
        bucket = avail[_section_match_key(d)]
        match = next((x for x in bucket if not x["used"]), None)
        if match is None:
            items.append(SectionDiffItem(status="added", drafted=d))
            continue
        match["used"] = True
        cur = match["sec"]
        status = "unchanged" if _same_section_content(cur, d) else "modified"
        items.append(SectionDiffItem(status=status, current=cur, drafted=d))

    for s in current:
        for x in avail[_section_match_key(s)]:
            if not x["used"]:
                items.append(SectionDiffItem(status="removed", current=x["sec"]))
    return items


def redraft_diff(
    *,
    session: Session,
    teacher_id: uuid.UUID,
    courseware_id: uuid.UUID,
) -> CoursewareRedraftDiff:
    """重起草：对**同一份**课件返回新草稿相对当前稿的逐段 diff（ADR-0067 第二轮 T07）。

    不新建课件副本：教师逐段选完后，把合并结果经 ``replace_sections`` 写回当前
    ``courseware_id``。沿用课件行快照的 kp 元信息（kp_name / subject / grade /
    semester），不回查知识点表（§3.2 展示不 join）。

    起草失败（未配模型 / 厂商拒绝 / 解析不出）一律透传，不落空课件。
    """
    row = repo.get_owned_courseware(
        session, teacher_id=teacher_id, courseware_id=courseware_id
    )
    current = _read_sections(row)
    drafted = draft_sections(
        session=session,
        teacher_id=teacher_id,
        kp_name=row.kp_name,
        subject=row.subject,
        grade=row.grade,
        semester=row.semester,
        snippets=_recall_snippets(
            session,
            teacher_id=teacher_id,
            kp_name=row.kp_name,
            subject=row.subject,
            grade=row.grade,
        ),
    )
    return CoursewareRedraftDiff(diff=compute_section_diff(current, drafted))


# ── 响应装配 ────────────────────────────────────────────────────────────


def _resp(
    session: Session, *, teacher_id: uuid.UUID, courseware: Courseware
) -> CoursewareResp:
    sections = _read_sections(courseware)
    return CoursewareResp(
        id=courseware.id,
        subject=courseware.subject,
        grade=courseware.grade,
        semester=courseware.semester,
        knowledge_point_id=courseware.knowledge_point_id,
        kp_name=courseware.kp_name,
        title=courseware.title,
        status=courseware.status,
        sections=sections,
        section_count=len(sections),
        kp_missing=_kp_missing(
            session, teacher_id=teacher_id, kp_id=courseware.knowledge_point_id
        ),
        created_at=courseware.created_at,
        updated_at=courseware.updated_at,
    )


def _read_sections(courseware: Courseware) -> list[CoursewareSection]:
    """库里的 JSON → 环节列表。``None`` / 非列表一律给 ``[]``（配合计数 0）。"""
    raw = courseware.sections
    if not isinstance(raw, list):
        return []
    out: list[CoursewareSection] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        try:
            out.append(CoursewareSection.model_validate(item))
        except Exception:  # noqa: BLE001 — 单个脏环节不该让整份课件读不出来
            continue
    return out


def _kp_missing(
    session: Session, *, teacher_id: uuid.UUID, kp_id: uuid.UUID | None
) -> bool:
    """该课件所属知识点是不是已经没了（ADR-0067 §4.1 孤儿课件标注）。

    课件**不级联删除**：它是教师调过的资产。知识点被清理后靠 ``kp_name`` 快照
    继续展示，列表行据此标注「所属知识点已移除」。
    """
    if kp_id is None:
        return True
    alive = repo.existing_knowledge_point_ids(session, teacher_id=teacher_id, ids=[kp_id])
    return kp_id not in alive


# ── 端点编排 ────────────────────────────────────────────────────────────


def list_coursewares(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    knowledge_point_id: uuid.UUID | None = None,
    subject: str | None = None,
    grade: int | None = None,
    semester: str | None = None,
) -> list[CoursewareResp]:
    rows = repo.list_courseware(
        session,
        teacher_id=teacher_id,
        knowledge_point_id=knowledge_point_id,
        subject=subject,
        grade=grade,
        semester=semester,
    )
    return [_resp(session, teacher_id=teacher_id, courseware=c) for c in rows]


def recent_courseware(
    session: Session, *, teacher_id: uuid.UUID
) -> CoursewareResp | None:
    """最近更新的那一份（ADR-0067 §3.8「最近课件」回执）；没有则 ``None``。"""
    row = repo.recent_courseware(session, teacher_id=teacher_id)
    return _resp(session, teacher_id=teacher_id, courseware=row) if row else None


def get_courseware(
    session: Session, *, teacher_id: uuid.UUID, courseware_id: uuid.UUID
) -> CoursewareResp:
    row = repo.get_owned_courseware(
        session, teacher_id=teacher_id, courseware_id=courseware_id
    )
    return _resp(session, teacher_id=teacher_id, courseware=row)


def _payload_has_scene(payload: dict) -> bool:
    """AI 起草的旧结构把整份 SceneSpec 内嵌在 ``payload`` 里（ADR-0067 首轮）。

    有它就不必再补顶层 ``scene``——AI 按题面定制的场景比知识点默认场景**更具体**，
    覆盖掉等于把「这道题讲什么」换回「这个知识点一般讲什么」。
    """
    if not isinstance(payload, dict):
        return False
    return isinstance(payload.get("kind"), str) and isinstance(
        payload.get("inputs"), list
    )


def _attach_kp_scene(
    sections: list[CoursewareSection], *, kp: KnowledgePoint
) -> list[CoursewareSection]:
    """给**缺场景**的交互环节补上知识点场景（ADR-0073：课件也走统一解析入口）。

    此前只有出题侧走 ``resolve_kp_scene``，课件环节的场景全靠 AI 起草时顺便写进
    ``payload``——AI 没写就是没图。这正是 ADR-0061 §U.4「换个地方就没图」在课件
    侧的同一个根因：解析入口分裂，一处有一处没有。

    三条边界，缺一条就会变成新的坑：
    - **只在新建（AI 起草）时补，不在教师改的时候补**。补在保存路径上，教师
      「清除场景」就会被立刻填回来（与 `CoursewareSectionModel.copyWith` 那个
      null 哨兵 bug 同款）。落库后它是快照，教师后续怎么改都不受影响。
    - **只补 ``interactive_scene``**。素材画廊 / 练习环节挂一份轴对称场景是噪音。
    - **AI 已经给了就不覆盖**（见 :func:`_payload_has_scene`）。

    落库的是**深拷贝**：环节各自持有一份，改知识点场景不会回溯改已生成的课件。
    """
    scenes = resolve_kp_scene(kp)
    if not scenes or not isinstance(scenes[0], dict):
        return sections
    scene = copy.deepcopy(scenes[0])
    out: list[CoursewareSection] = []
    for section in sections:
        if (
            section.kind == "interactive_scene"
            and section.scene is None
            and not _payload_has_scene(section.payload)
        ):
            out.append(section.model_copy(update={"scene": copy.deepcopy(scene)}))
        else:
            out.append(section)
    return out


def create_courseware(
    session: Session, *, teacher_id: uuid.UUID, req: CoursewareCreate
) -> CoursewareResp:
    """新建课件：取知识点 → AI 起草 → 快照落库。

    - 知识点行经 ``core.guard`` 取（不存在 / 非本人 → ``COURSEWARE_KP_NOT_FOUND``）；
    - ``kp_name`` / ``subject`` / ``grade`` / ``semester`` **快照**到课件行，展示
      不依赖 join（§3.2）；
    - 起草失败**不落库**（抛错在写库之前），教师看到的是原因，不是一份空课件。
    """
    kp: KnowledgePoint = require_owned(
        session=session,
        owner_id=teacher_id,
        model=KnowledgePoint,
        obj_id=req.knowledge_point_id,
        code=ErrCode.COURSEWARE_KP_NOT_FOUND,
        message="知识点不存在或无权访问",
    )
    sections = draft_sections(
        session=session,
        teacher_id=teacher_id,
        kp_name=kp.name,
        subject=kp.subject,
        grade=kp.grade,
        semester=kp.semester,
        snippets=_recall_snippets(
            session,
            teacher_id=teacher_id,
            kp_name=kp.name,
            subject=kp.subject,
            grade=kp.grade,
        ),
    )
    courseware = Courseware(
        teacher_id=teacher_id,
        subject=kp.subject,
        grade=kp.grade,
        semester=kp.semester,
        knowledge_point_id=kp.id,
        kp_name=kp.name,
        title=req.title or kp.name,
        sections=_store_sections(_attach_kp_scene(sections, kp=kp)),
    )
    row = repo.add_courseware(session, courseware=courseware)
    return _resp(session, teacher_id=teacher_id, courseware=row)


def update_courseware(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    courseware_id: uuid.UUID,
    req: CoursewareUpdate,
) -> CoursewareResp:
    """改标题 / 状态。只传要改的字段（``None`` = 不动）。"""
    row = repo.get_owned_courseware(
        session, teacher_id=teacher_id, courseware_id=courseware_id
    )
    if req.title is not None:
        row.title = req.title
    if req.status is not None:
        if req.status not in COURSEWARE_STATUSES:
            raise AppErrorException(
                ErrCode.VALIDATION,
                f"未知的课件状态：{req.status}（只能是 {' / '.join(COURSEWARE_STATUSES)}）",
            )
        row.status = req.status
    # 动过就要顶到「最近课件」第一位：回执的意义是「继续上次」（建库时列的
    # updated_at 只在插入时取一次，改动不写它的话回执会一直指向最早那份）。
    row.updated_at = get_datetime_utc()
    row = repo.save_courseware(session, courseware=row)
    return _resp(session, teacher_id=teacher_id, courseware=row)


def replace_sections(
    session: Session,
    *,
    teacher_id: uuid.UUID,
    courseware_id: uuid.UUID,
    req: CoursewareSectionsUpdate,
) -> CoursewareResp:
    """整体覆盖写环节序列（排序 / 增删改都在前端完成，后端只存结果）。

    kind 过注册表校验（§3.3），空列表落真 SQL NULL。
    """
    row = repo.get_owned_courseware(
        session, teacher_id=teacher_id, courseware_id=courseware_id
    )
    sections = _fill_ids(list(req.sections or []))
    validate_section_kinds(sections)
    row.sections = _store_sections(sections)
    row.updated_at = get_datetime_utc()
    row = repo.save_courseware(session, courseware=row)
    return _resp(session, teacher_id=teacher_id, courseware=row)


def delete_courseware(
    session: Session, *, teacher_id: uuid.UUID, courseware_id: uuid.UUID
) -> None:
    row = repo.get_owned_courseware(
        session, teacher_id=teacher_id, courseware_id=courseware_id
    )
    repo.delete_courseware(session, courseware=row)
