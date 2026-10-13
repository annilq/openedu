"""场景融合（ADR-0061 决策 3 / 4 / ADR-0083 / ADR-0091）单元测试。

覆盖两条主路径：
- ``fuse_scene_spec``：纯函数，知识点模板 → SceneSpec；题面图形**替换主图形**
  （ADR-0091：原「覆盖顶层 points/edges」语义废止）；
- ``resolve_scene_spec_for_question``：按题目知识点查教师私有知识点模板 + 分页缓存。

ADR-0091 起**不做双读**：旧形模板（顶层 points/edges、optionGroup、inputs）
经校验入口一律拒绝——本文件钉住拒绝语义，存量旧数据归迁移脚本
（``scripts/migrate_scene_specs.py``）。

``resolve`` 只用轻量 stub session（只走知识点查询）；``build_scene_spec_for_question``
会额外查图库 DB 取几何，故那部分用真实 ``db`` fixture。
"""
import uuid

from app.domain.figures import Figure
from app.features.materials.scene_fusion import (
    build_scene_spec_for_question,
    fuse_scene_spec,
    resolve_scene_spec_for_question,
)

_POINTS_A = [[0.3, 0.7], [0.7, 0.7], [0.5, 0.3]]
_POINTS_B = [[0.1, 0.9], [0.9, 0.9], [0.5, 0.1]]
_EDGES = [[0, 1], [1, 2], [2, 0]]


def _figure(key: str = "house", points: list | None = None) -> Figure:
    return Figure(
        key=key,
        label=key,
        points=[list(p) for p in (points or _POINTS_A)],
        edges=[list(e) for e in _EDGES],
    )


def _template(points=None, *, figure_key: str = "house") -> dict:
    """新形模板（ADR-0091）：kind + 一个主图形，顶点在 figure 里。"""
    return {
        "kind": "reflection",
        "figure": {
            "key": figure_key,
            "label": figure_key,
            "points": [list(p) for p in (points or _POINTS_A)],
            "edges": [list(e) for e in _EDGES],
        },
    }


def test_fuse_empty_returns_none():
    assert fuse_scene_spec(None) is None
    assert fuse_scene_spec([]) is None
    assert fuse_scene_spec("not-a-list") is None
    # 模板不是 dict
    assert fuse_scene_spec([123]) is None


def test_fuse_no_figure_copies_template_deeply():
    out = fuse_scene_spec([_template()])
    assert out is not None
    assert out.kind == "reflection"
    assert out.figure is not None
    assert out.figure.points == _POINTS_A
    # 深拷贝：改原模板不影响产物（快照铁律）
    template = _template()
    out = fuse_scene_spec([template])
    template["figure"]["points"][0][0] = 0.999
    assert out.figure.points[0][0] == 0.3


def test_fuse_replaces_main_figure():
    """题面命中的图形**替换主图形**（ADR-0091：不再是「覆盖顶层字段」）。"""
    out = fuse_scene_spec([_template(_POINTS_A)], figure=_figure("kite", _POINTS_B))
    assert out is not None
    assert out.figure.key == "kite"
    assert out.figure.points == _POINTS_B


def test_fuse_replace_keeps_options_and_curated():
    """替换只动主图形：options / curated 原样保留（课件编排语境不丢）。"""
    template = {
        "kind": "reflection",
        "figure": {
            "key": "house",
            "points": [list(p) for p in _POINTS_A],
            "edges": [list(e) for e in _EDGES],
        },
        "options": [
            {
                "key": "square",
                "label": "正方形",
                "points": [list(p) for p in _POINTS_B],
                "edges": [list(e) for e in _EDGES],
            }
        ],
        "curated": True,
    }
    out = fuse_scene_spec([template], figure=_figure("kite", _POINTS_B))
    assert out is not None
    assert out.figure.key == "kite"
    assert out.options is not None and out.options[0].key == "square"
    assert out.curated is True


def test_fuse_rejects_legacy_template():
    """旧形模板一律拒绝（ADR-0091 不做双读）——不静默包成 figure。"""
    legacy_top = {"kind": "reflection", "points": _POINTS_A, "edges": _EDGES}
    assert fuse_scene_spec([legacy_top]) is None
    legacy_inputs = {"kind": "reflection", "inputs": [{"key": "points", "value": _POINTS_A}]}
    assert fuse_scene_spec([legacy_inputs]) is None
    legacy_group = {
        "kind": "reflection",
        "optionGroup": {"items": [{"caption": "房子", "points": _POINTS_A, "edges": _EDGES}]},
    }
    assert fuse_scene_spec([legacy_group]) is None


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
    assert out1 is not None
    assert out1.kind == "reflection"
    assert out1.figure.key == "house"
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
    exact = _KP([_template(figure_key="exact")])
    session = _SequenceSession([exact])
    out = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        semester="上学期",
    )
    assert out is not None
    assert out.figure.key == "exact"
    assert session.exec_calls == 1  # 精确命中，未触发回落


def test_resolve_falls_back_to_year_wide_when_no_exact():
    """同学期无模板 → 第二次查询命中整学年（semester=''）模板。"""
    year_wide = _KP([_template(figure_key="year_wide")])
    session = _SequenceSession([None, year_wide])  # 第一次（精确）无果
    out = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        semester="下学期",
    )
    assert out is not None
    assert out.figure.key == "year_wide"
    assert session.exec_calls == 2  # 精确未中 → 回落整学年


def test_resolve_no_semester_queries_once():
    """题目未指定学期（''）→ 只查整学年一次，不做多余的精确查询。"""
    year_wide = _KP([_template(figure_key="year_wide")])
    session = _SequenceSession([year_wide])
    out = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        semester="",
    )
    assert out is not None
    assert out.figure.key == "year_wide"
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


# ── 题面图形替换主图形（ADR-0061 §M / ADR-0083 / ADR-0091）────────────────


def test_figure_replaces_template_main_figure():
    """题面命中的图形必须**替换**模板主图形（否则场景与题目无关）。"""
    out = fuse_scene_spec([_template(_POINTS_A)], figure=_figure("kite", _POINTS_B))
    assert out is not None
    assert out.figure.key == "kite"
    assert out.figure.points == _POINTS_B


def test_figure_is_applied_on_read_path():
    """读路径带题面图形时也要生效（生成时/回退解析共用同一条逻辑）。"""
    session = FakeSession(_KP([_template(_POINTS_A)]))
    out = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        figure=_figure("kite", _POINTS_B),
    )
    assert out is not None
    assert out.figure.key == "kite"


def test_figure_bypasses_cache():
    """带题面图形时不走缓存：同一知识点的不同题目结果不同，混用会串味。"""
    session = FakeSession(_KP([_template(_POINTS_A)]))
    cache: dict = {}
    a = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="KP",
        figure=_figure("kite", _POINTS_A),
        cache=cache,
    )
    b = resolve_scene_spec_for_question(
        session,
        teacher_id="p",
        subject="数学",
        grade=4,
        knowledge_point="KP",
        figure=_figure("para", _POINTS_B),
        cache=cache,
    )
    assert a.figure.key == "kite"
    assert b.figure.key == "para"
    assert cache == {}, "带题面图形时不得写入跨题复用缓存"


def test_build_scene_spec_end_to_end(db):
    """build_scene_spec_for_question = 找知识点模板 → 融合主图形（ADR-0089：不猜题面）。"""
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
        )
        # 主图形只来自知识点模板（ADR-0089：不再扫题面/选项反猜）。
        assert out is not None
        assert out.figure.key == "house"
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


def test_build_unknown_knowledge_point_returns_none(db):
    """ADR-0089：没有匹配的知识点（无模板）即返回 None，绝不臆造图形。"""
    out = build_scene_spec_for_question(
        db,
        teacher_id=uuid.uuid4(),
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
    )
    assert out is None


def test_build_template_figure_without_option_group(db):
    """教师配了模板 → 用模板主图形；选项文字反猜路径已删（ADR-0089 ticket 02）。"""
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
        )
        assert out is not None
        # 主图形来自模板；选项组不再挂载（逐选项图形由 AI 链路接回）。
        assert out.figure.key == "house"
        assert out.options is None
    finally:
        db.delete(kp)
        db.commit()
