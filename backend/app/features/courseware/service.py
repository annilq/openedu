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
from app.db.models.courseware import COURSEWARE_STATUS_DRAFT
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

# 起草时喂给模型的资料片段条数与单条截断长度（prompt 预算，不是检索参数）。
_SNIPPET_TOP_K = 5
_SNIPPET_CHARS = 300
_PROMPT_TEXT_LIMIT = 2000

_DRAFT_SYSTEM = (
    "你是 K12 教研助手，为教师备一份「按知识点讲解」的课件。\n"
    "产出 3-4 个**有序**环节，每个环节是统一的内容块容器，形如 "
    '{"id": "", "title": "...", "script": "...", "payload": {...}, '
    '"materials": [...], "scene": ..., "practice": {...}}。\n'
    "**不再有 kind 字段**——每个环节渲染 / 演示都「按填了什么」，不要输出 kind。\n"
    "各内容块（可同时有、可都空）：\n"
    '- "materials"：素材。**只能引用下面「可用素材」清单里给出的真实 asset_id**'
    "（教师已上传的图），不要编造 id；每个元素 {asset_id, caption}。没有合适素材就给空数组。\n"
    '- "scene"：交互演示（图形、对称轴等）。**只能引用下面「可用场景模板」里给出的真实'
    "模板**（教师已在知识点里配置好的交互讲解），把整份模板原样放进来；不要凭空造 SceneSpec。"
    "没有就给 null。\n"
    '- "practice"：课堂练习（可选）。形如 {"qtype": "choice", "count": 3, '
    '"hints": "给学生的提示"}；qtype 取 choice / fill / calc / open 之一。\n'
    "script 是**投给学生看的提问卡话术**（一句可直接念出来的提问，如"
    "「这些图形有什么共同点？」），不要写成流程说明或教师备注。\n"
    "title 是环节标题，12 字以内。id 留空字符串，由后端生成。\n"
    "只输出 JSON。"
)


class _DraftSection(SQLModel):
    """模型产出的单个环节（输出契约，字段宽松——校验与收敛在 service 层）。

    courseware-round-3 T03（去 kind·expand）：环节不再带 kind，统一为内容块容器；
    materials / scene / practice 都是可选顶层字段（T05 起允许引用真实素材 / 场景 id）。

    ``kind`` 保留为可选只读兼容字段：旧草稿仍可能带 kind，解析后透传到落库环节
    （渲染按内容、不依赖它）；新起草 prompt 已声明不再输出 kind，但模型偶发带出
    也不该抛 AttributeError。
    """

    id: str = ""
    kind: str | None = None
    title: str = ""
    script: str = ""
    payload: dict = Field(default_factory=dict)
    # 内容块统一化：起草产物也可选填顶层素材 / 场景 / 练习（旧起草只走 payload 内嵌）。
    materials: list[dict] = Field(default_factory=list)
    scene: dict | None = Field(default=None)
    practice: dict | None = Field(default=None)


class _CoursewareDraft(SQLModel):
    """模型产出的整份草稿。"""

    sections: list[_DraftSection] = Field(default_factory=list)


# ── 环节校验 ────────────────────────────────────────────────────────────


def validate_section_kinds(sections: list[CoursewareSection]) -> None:
    """环节 kind 校验（courseware-round-3 T03·去 kind·expand 后**不再拦截**）。

    旧设计里 kind 是必填注册表字段，未知 / 空 kind 直接 422（ADR-0067 §3.3）。去
    kind 后环节是统一的「内容块容器」，kind 退化为可选只读的旧数据兼容字段——空 /
    未知 kind 一律放行，仅在遇到旧数据里的未知 kind 时打 warning 便于排查，绝不 422
    （删 kind 字段与枚举归 T07 contract）。渲染 / 编辑都「按填了什么」，不依赖 kind。
    """
    for s in sections:
        if s.kind and s.kind not in SECTION_KINDS:
            warnings.warn(
                f"课件环节含未登记 kind（兼容只读，不拦截）：{s.kind}", stacklevel=2
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
        # courseware-round-3 T06：练习是第四可选内容块（与 materials / scene 并列），
        # 顶层字段，旧数据走 payload['qtype'] 由前端回退读取。
        "practice": s.practice,
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


def _candidate_assets(
    session: Session, *, teacher_id: uuid.UUID, knowledge_point_id: uuid.UUID | None
) -> list[dict]:
    """该知识点下教师已上传的素材候选 (id, name)，喂给 LLM 作为真实 asset_id 来源。

    候选只是起草的**可选依据**：查不到 / 知识点不可见一律降级为空列表，不阻塞起草
    （与 ``_recall_snippets`` 同纪律——把检索失败抛成 500 会让「没传素材」和「服务
    坏了」混为一谈，正是 ADR-0038 要分开的）。
    """
    if knowledge_point_id is None:
        return []
    try:
        from app.features.courseware import asset_service

        resp = asset_service.search_assets(
            session, teacher_id=teacher_id, knowledge_point_id=knowledge_point_id
        )
    except Exception as e:  # noqa: BLE001 — 候选缺失只降级
        warnings.warn(f"课件起草跳过素材候选：{e}", stacklevel=2)
        return []
    return [{"id": a.id, "name": a.name} for a in resp.items]


def _candidate_scenes(
    session: Session, *, teacher_id: uuid.UUID, knowledge_point_id: uuid.UUID | None
) -> list[dict]:
    """该知识点已配置的交互讲解模板（kp.scenes，ADR-0073 单一事实源），喂给 LLM 作为
    真实 scene 模板来源。

    每个元素是 kp.scenes 里的一份场景 dict（含 kind）；候选缺失只降级为空列表。
    """
    if knowledge_point_id is None:
        return []
    try:
        kp = require_owned(
            session=session,
            owner_id=teacher_id,
            model=KnowledgePoint,
            obj_id=knowledge_point_id,
            code=ErrCode.FORBIDDEN,
            message="知识点不存在或无权限",
        )
    except Exception:  # noqa: BLE001 — 候选缺失只降级
        return []
    scenes = getattr(kp, "scenes", None)
    if not isinstance(scenes, list):
        return []
    return [s for s in scenes if isinstance(s, dict)]


def draft_sections(
    *,
    session: Session,
    teacher_id: uuid.UUID,
    kp_name: str,
    subject: str | None = None,
    grade: int | None = None,
    semester: str | None = None,
    snippets: list[str] | None = None,
    knowledge_point_id: uuid.UUID | None = None,
    objective: str | None = None,
) -> list[CoursewareSection]:
    """为一个知识点起草环节序列（ADR-0067 §3.4：AI 起草 + 教师调）。

    引擎与失败分类照 ``materials`` 的 AI 路径（同一条 ``build_ai_provider`` 链）：
    未配模型 → ``LLM_UNAVAILABLE``；厂商拒绝 → ``LLM_REQUEST_FAILED``（带
    ``user_hint``）；产出不可用 → ``LLM_REQUEST_FAILED``（带实际原因）。

    单独成函数、只吃普通参数：测试 monkeypatch 它就完全不打模型。

    courseware-round-3 T05（AI 补充讲解·三项数据回填）：起草前先查该知识点的真实
    素材候选（asset_id）与已配置场景模板（kp.scenes），连同教师填的 ``objective``
    一起喂给 LLM；产出只许引用这些真实 id（编造的在服务端直接剥掉，见
    ``_sections_from_draft``），实现「引用真实素材 / 场景」而非留空 / 编造。

    ⚠️ 起草结果里没有任何环节时抛错，不返回空列表——空课件是「把没有内容伪装成
    有内容」（ADR-0066）。
    """
    provider = build_ai_provider(teacher_id=teacher_id, session=session)
    if not getattr(provider, "configured", True):
        raise AppErrorException(
            ErrCode.LLM_UNAVAILABLE,
            "未配置模型，无法起草课件（请在「模型管理」中添加模型并设为默认）",
        )

    asset_candidates = _candidate_assets(
        session, teacher_id=teacher_id, knowledge_point_id=knowledge_point_id
    )
    scene_candidates = _candidate_scenes(
        session, teacher_id=teacher_id, knowledge_point_id=knowledge_point_id
    )

    prompt = (
        f"知识点：{kp_name}\n"
        f"学科：{subject or '未指定'}\n"
        f"年级：{grade or '未指定'}\n"
        f"学期：{semester or '未指定'}\n"
    )
    if objective:
        prompt += (
            "教学目标（备课依据，起草的讲解与练习应围绕它展开）："
            f"{objective}\n"
        )
    if snippets:
        prompt += "该知识点下的教材片段（唯一的内容依据，不要超出它的范围编造）：\n"
        prompt += "\n".join(f"- {s}" for s in snippets)
    if asset_candidates or scene_candidates:
        prompt += (
            "\n教师已配置、你**只能引用**的真实依据（不要编造 id，没有合适的就给"
            "空数组 / null）：\n"
        )
        if asset_candidates:
            prompt += "可用素材（asset_id）：\n"
            prompt += "\n".join(
                f"- {a['id']}（{a['name']}）" for a in asset_candidates
            )
            prompt += "\n"
        if scene_candidates:
            prompt += (
                "可用场景模板（把整份模板原样放入 scene，kind 取自下面的 kind）：\n"
            )
            prompt += "\n".join(
                f"- {s.get('kind')}（{s.get('title', '')}）" for s in scene_candidates
            )
            prompt += "\n"
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

    return _sections_from_draft(
        data,
        allowed_asset_ids={str(a["id"]) for a in asset_candidates},
        allowed_scene_kinds={s.get("kind") for s in scene_candidates},
    )


async def _collect_draft(provider, prompt: str):
    """跑一次结构化调用，取 ``StructuredDone`` 的载荷（拿不到则为 ``None``）。"""
    async for ev in provider.stream(_DRAFT_SYSTEM, prompt, schema=_CoursewareDraft):
        if isinstance(ev, StructuredDone):
            return ev.data
    return None


def _sections_from_draft(
    data: object,
    *,
    allowed_asset_ids: set[str] | None = None,
    allowed_scene_kinds: set[str | None] | None = None,
) -> list[CoursewareSection]:
    """模型载荷 → 环节序列；不可用则抛 ``LLM_REQUEST_FAILED``（带实际原因）。

    courseware-round-3 T05（三项数据回填）：模型引用的素材 / 场景必须落在教师真实
    配置的候选集里——**不在候选集的一律剥掉**（不信任模型输出，杜绝编造 asset_id
    / 凭空造 SceneSpec）。候选集为空时，任何 materials / scene 引用都被清掉（模型
    只能给空数组 / null）。
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
        # courseware-round-3 T03（去 kind·expand）：环节不再按 kind 过滤 / 丢弃——
        # 只要是模型给出的环节都接受（空课件不伪造的判定改由「完全没有环节」兜底）。
        # T05：素材 / 场景引用只保留真实候选，编造的剥掉（id 统一按 str 比较，
        # 兼容模型把 UUID 输出成字符串）。
        materials = [
            m
            for m in (raw.materials if isinstance(raw.materials, list) else [])
            if isinstance(m, dict)
            and (allowed_asset_ids is None or str(m.get("asset_id")) in allowed_asset_ids)
        ]
        scene = (
            raw.scene
            if (
                isinstance(raw.scene, dict)
                and (
                    allowed_scene_kinds is None
                    or raw.scene.get("kind") in allowed_scene_kinds
                )
            )
            else None
        )
        sections.append(
            CoursewareSection(
                id=raw.id or uuid.uuid4().hex[:8],
                kind=raw.kind if isinstance(raw.kind, str) and raw.kind else None,
                title=(raw.title or "")[:128],
                script=(raw.script or "")[:2000],
                payload=raw.payload if isinstance(raw.payload, dict) else {},
                # 内容块统一化：透传顶层素材 / 场景 / 练习（LLM 引用真实 asset_id /
                # 场景模板，T05 起在服务端收敛为真实候选）。
                materials=materials,
                scene=scene,
                practice=raw.practice if isinstance(raw.practice, dict) else None,
            )
        )
    if not sections:
        raise AppErrorException(
            ErrCode.LLM_REQUEST_FAILED,
            "AI 起草课件失败：模型没有返回任何环节",
        )
    return sections


def _section_match_key(s: "CoursewareSection") -> tuple[str, ...]:
    """匹配键 = (title,)。

    courseware-round-3 T03（去 kind·expand）：环节不再按 kind 区分——同名环节即视为
    「同一环节」去对照，避免去 kind 后所有环节都判成新增。同名多段仍按出现顺序消费
    （compute_section_diff 内用 used 标记逐个消费）。
    """
    return (s.title,)


def _segment_signature(s: "CoursewareSection") -> str:
    """话术段的可比较指纹（文本 + 重点），忽略顺序差异之外的内容。"""
    return json.dumps(
        [(seg.text, seg.emphasis) for seg in (s.script_segments or [])],
        ensure_ascii=False,
        sort_keys=True,
    )


def _same_section_content(a: "CoursewareSection", b: "CoursewareSection") -> bool:
    """两段字面上的内容是否一致（标题 / 话术 / 多段话术 / payload 都相同才算 unchanged）。

    courseware-round-3 T06：练习内容块（practice）也纳入比较，避免「只改了练习配置」
    被误判为 unchanged。
    """
    return (
        a.title == b.title
        and a.script == b.script
        and _segment_signature(a) == _segment_signature(b)
        and a.payload == b.payload
        and a.materials == b.materials
        and a.scene == b.scene
        and a.practice == b.practice
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
        knowledge_point_id=row.knowledge_point_id,
        objective=row.objective,
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


def create_courseware(
    session: Session, *, teacher_id: uuid.UUID, req: CoursewareCreate
) -> CoursewareResp:
    """新建课件。

    - 知识点行经 ``core.guard`` 取（不存在 / 非本人 → ``COURSEWARE_KP_NOT_FOUND``）；
    - ``kp_name`` / ``subject`` / ``grade`` / ``semester`` **快照**到课件行，展示
      不依赖 join（§3.2）；
    - ``draft=True``（默认）：取知识点 → AI 起草 → 落库；起草失败**不落库**（抛错在
      写库之前），教师看到的是原因，不是一份空课件。
    - ``draft=False``（courseware-round-3 T01）：**跳过 AI 起草**，直接按知识点快照
      建一份**零环节空壳**课件（不调模型、不抛 LLM 错误），``objective`` 落到课件行
      备用。教师随后手动填环节、或用「AI 补充讲解」补——此刻内容完全自己掌控。
    """
    kp: KnowledgePoint = require_owned(
        session=session,
        owner_id=teacher_id,
        model=KnowledgePoint,
        obj_id=req.knowledge_point_id,
        code=ErrCode.COURSEWARE_KP_NOT_FOUND,
        message="知识点不存在或无权访问",
    )
    if not req.draft:
        # 空壳：不调 AI、不抛 LLM 错误。零环节写成真 SQL NULL（同 _store_sections）。
        courseware = Courseware(
            teacher_id=teacher_id,
            subject=kp.subject,
            grade=kp.grade,
            semester=kp.semester,
            knowledge_point_id=kp.id,
            kp_name=kp.name,
            title=req.title or kp.name,
            status=COURSEWARE_STATUS_DRAFT,
            objective=req.objective,
            sections=None,
        )
        row = repo.add_courseware(session, courseware=courseware)
        return _resp(session, teacher_id=teacher_id, courseware=row)

    sections = draft_sections(
        session=session,
        teacher_id=teacher_id,
        kp_name=kp.name,
        subject=kp.subject,
        grade=kp.grade,
        semester=kp.semester,
        knowledge_point_id=kp.id,
        objective=req.objective,
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
        objective=req.objective,
        sections=_store_sections(sections),
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
