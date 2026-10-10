"""场景融合（ADR-0061 决策 3 / 4 / ADR-0083）单元测试。

覆盖两条主路径：
- ``fuse_scene_spec``：纯函数，用题面命中的几何覆盖模板顶层 ``points``/``edges``；
- ``resolve_scene_spec_for_question``：按题目知识点查教师私有知识点模板 + 分页缓存。

``resolve`` 只用轻量 stub session（只走知识点查询）；``build_scene_spec_for_question``
会额外查图库 DB 取几何，故那部分用真实 ``db`` fixture。
"""
import uuid

from app.features.materials.scene_figures import FIGURES
from app.features.materials.scene_fusion import (
    build_scene_spec_for_question,
    fuse_scene_spec,
    resolve_scene_spec_for_question,
)

_POINTS_A = [[0.3, 0.7], [0.7, 0.7], [0.5, 0.3]]
_POINTS_B = [[0.1, 0.9], [0.9, 0.9], [0.5, 0.1]]
_EDGES = [[0, 1], [1, 2], [2, 0]]


def test_fuse_empty_returns_none():
    assert fuse_scene_spec(None) is None
    assert fuse_scene_spec([]) is None
    assert fuse_scene_spec("not-a-list") is None
    # 模板不是 dict
    assert fuse_scene_spec([123]) is None


def test_fuse_no_override_copies_template_deeply():
    template = {
        "kind": "reflection",
        "points": [list(p) for p in _POINTS_A],
        "edges": [list(e) for e in _EDGES],
    }
    out = fuse_scene_spec([template])
    assert out["kind"] == "reflection"
    assert out["points"] == _POINTS_A
    # 深拷贝：改原模板不影响产物
    template["points"][0][0] = 0.999
    assert out["points"][0][0] == 0.3


def test_fuse_override_geometry():
    template = {"kind": "reflection", "points": [list(p) for p in _POINTS_A], "edges": []}
    out = fuse_scene_spec([template], overrides={"points": _POINTS_B, "edges": _EDGES})
    assert out["points"] == _POINTS_B
    assert out["edges"] == _EDGES


class _KP:
    def __init__(self, scenes):
        self.scenes = scenes


class _ExecChain:
    """链式 stub：``exec(...).where(...).order_by(...).first()``。"""

    def __init__(self, kp):
        self._kp = kp

    def where(self, *a, **k):
        return self

    def order_by(self, *a, **k):
        return self

    def first(self):
        return self._kp


class FakeSession:
    def __init__(self, kp):
        self._kp = kp
        self.exec_calls = 0

    def exec(self, *a, **k):
        self.exec_calls += 1
        return _ExecChain(self._kp)


def _template(points=None):
    return {
        "kind": "reflection",
        "points": [list(p) for p in (points or _POINTS_A)],
        "edges": [list(e) for e in _EDGES],
    }


def test_resolve_hits_kp_and_caches():
    kp = _KP([_template()])
    session = FakeSession(kp)
    cache: dict = {}
    out1 = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        cache=cache,
    )
    assert out1["kind"] == "reflection"
    assert session.exec_calls == 1

    # 第二次命中缓存，不再访问 session
    session._kp = None  # 若再查会返回 None，可断言没查
    out2 = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        cache=cache,
    )
    assert out2 is out1
    assert session.exec_calls == 1  # 没增加


def test_resolve_no_kp_returns_none():
    session = FakeSession(None)
    assert (
        resolve_scene_spec_for_question(
            session,
            teacher_id="p",
            subject="数学",
            grade=4,
            knowledge_point="不存在的点",
        )
        is None
    )


def test_resolve_empty_kp_name_returns_none():
    session = FakeSession(None)
    assert (
        resolve_scene_spec_for_question(
            session,
            teacher_id="p",
            subject="数学",
            grade=4,
            knowledge_point="",
        )
        is None
    )


# ── 学期维度匹配（ADR-0061 发布任务对接资料库）────────────────────────────


class _SequenceSession:
    """按调用次序返回不同 KP 的 stub：验证「先精确学期、再整学年」的回落次序。

    真实实现会用同一where 查两次（精确 semester → ''）；这里让每次 ``exec`` 弹出
    序列里的下一个结果，从而能断言**命中第几次**与最终用哪个模板。
    """

    def __init__(self, results):
        self._results = list(results)
        self.exec_calls = 0

    def exec(self, *a, **k):
        self.exec_calls += 1
        idx = min(self.exec_calls - 1, len(self._results) - 1)
        kp = self._results[idx]
        return _ExecChain(kp)


def test_resolve_prefers_exact_semester_match():
    """题目学期 = 上学期 → 首次查询（精确上学期）即命中，不再回落。"""
    exact = _KP([{"kind": "reflection", "tag": "上学期", "points": [], "edges": []}])
    session = _SequenceSession([exact])
    out = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        semester="上学期",
    )
    assert out["tag"] == "上学期"
    assert session.exec_calls == 1  # 精确命中，未触发回落


def test_resolve_falls_back_to_year_wide_when_no_exact():
    """同学期无模板 → 第二次查询命中整学年（semester=''）模板。"""
    year_wide = _KP([{"kind": "reflection", "tag": "整学年", "points": [], "edges": []}])
    session = _SequenceSession([None, year_wide])  # 第一次（精确）无果
    out = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        semester="下学期",
    )
    assert out["tag"] == "整学年"
    assert session.exec_calls == 2  # 精确未中 → 回落整学年


def test_resolve_no_semester_queries_once():
    """题目未指定学期（''）→ 只查整学年一次，不做多余的精确查询。"""
    year_wide = _KP([{"kind": "reflection", "tag": "整学年", "points": [], "edges": []}])
    session = _SequenceSession([year_wide])
    out = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        semester="",
    )
    assert out["tag"] == "整学年"
    assert session.exec_calls == 1


def test_resolve_semester_aware_cache_key():
    """缓存键含学期：同学期不同学期是两个独立条目，不互相污染。"""
    session = _SequenceSession([_KP([_template()])])
    cache: dict = {}
    kw = dict(
        session=session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
    )
    resolve_scene_spec_for_question(**kw, semester="上学期", cache=cache)
    resolve_scene_spec_for_question(**kw, semester="下学期", cache=cache)
    # 两个不同学期 → 两个缓存键
    assert len(cache) == 2
    # 重复同学期 → 命中缓存，exec 不增加
    before = session.exec_calls
    resolve_scene_spec_for_question(**kw, semester="上学期", cache=cache)
    assert session.exec_calls == before


# ── 题面几何 overrides（ADR-0061 §M / ADR-0083）──────────────────────────


def test_overrides_replace_template_geometry():
    """题面命中的几何必须**覆盖**模板几何（否则场景与题目无关）。"""
    out = fuse_scene_spec([_template(_POINTS_A)], overrides={"points": _POINTS_B})
    assert out["points"] == _POINTS_B


def test_overrides_are_applied_on_read_path():
    """读路径带 overrides 时也要生效（生成时/回退解析共用同一条逻辑）。"""
    session = FakeSession(_KP([_template(_POINTS_A)]))
    out = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        overrides={"points": _POINTS_B},
    )
    assert out["points"] == _POINTS_B


def test_overrides_bypass_cache():
    """带题面几何时不走缓存：同一知识点的不同题目结果不同，混用会串味。"""
    session = FakeSession(_KP([_template(_POINTS_A)]))
    cache: dict = {}
    a = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="KP",
        overrides={"points": _POINTS_A},
        cache=cache,
    )
    b = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="KP",
        overrides={"points": _POINTS_B},
        cache=cache,
    )
    assert a["points"] == _POINTS_A
    assert b["points"] == _POINTS_B
    assert cache == {}, "带overrides 时不得写入跨题复用缓存"


def test_build_scene_spec_end_to_end(db):
    """build_scene_spec_for_question = 找模板 + 抽题面图形 + 查图库几何 + 融合。"""
    teacher_id = uuid.uuid4()
    from app.db.models import KnowledgePoint

    kp = KnowledgePoint(
        id=uuid.uuid4(),
        teacher_id=teacher_id,
        subject="数学",
        grade=4,
        semester="",
        name="图形的运动（轴对称）",
        scenes=[_template(_POINTS_A)],
    )
    db.add(kp)
    db.commit()
    try:
        out = build_scene_spec_for_question(
            db,
            teacher_id=teacher_id,
            subject="数学",
            grade=4,
            knowledge_point="图形的运动（轴对称）",
            semester="下学期",
            stem="下图是风筝，它是对称图形吗？",
        )
        kite = next(f for f in FIGURES if f.key == "kite")
        assert out["points"] == [[x, y] for x, y in kite.vertices]
    finally:
        db.delete(kp)
        db.commit()


def test_build_scene_spec_no_knowledge_point_returns_none(db):
    assert (
        build_scene_spec_for_question(
            db,
            teacher_id="p",
            subject="数学",
            grade=4,
            knowledge_point="",
        )
        is None
    )
