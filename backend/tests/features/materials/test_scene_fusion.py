"""场景融合（ADR-0061 决策 3 / 4）单元测试。

覆盖两条主路径：
- ``fuse_scene_spec``：纯函数，覆盖题面输入 → 题目实例；
- ``resolve_scene_spec_for_question``：按题目知识点查家长私有知识点模板 + 分页缓存。

DB 查询用轻量 stub session，不依赖真实数据库，保证单测快且稳定。
"""
from app.features.materials.scene_fusion import (
    fuse_scene_spec,
    resolve_scene_spec_for_question,
)


def test_fuse_empty_returns_none():
    assert fuse_scene_spec(None) is None
    assert fuse_scene_spec([]) is None
    assert fuse_scene_spec("not-a-list") is None
    # 模板不是 dict
    assert fuse_scene_spec([123]) is None


def test_fuse_no_override_copies_template_deeply():
    template = {
        "kind": "reflection",
        "inputs": [{"key": "axisAngle", "value": 90}],
        "controls": {"play": True},
        "narrative": "n",
        "locked_answer": {"x": 1},
    }
    out = fuse_scene_spec([template])
    assert out["kind"] == "reflection"
    assert out["inputs"][0]["value"] == 90
    assert out["locked_answer"] == {"x": 1}
    # 深拷贝：改原模板不影响产物
    template["inputs"][0]["value"] = 0
    assert out["inputs"][0]["value"] == 90


def test_fuse_override_inputs():
    template = {
        "kind": "reflection",
        "inputs": [
            {"key": "axisAngle", "value": 90},
            {"key": "figure", "value": "house"},
        ],
    }
    out = fuse_scene_spec(
        [template], overrides={"axisAngle": 45, "figure": "kite"}
    )
    vals = {i["key"]: i["value"] for i in out["inputs"]}
    assert vals == {"axisAngle": 45, "figure": "kite"}


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
    kp = _KP([{"kind": "reflection", "inputs": []}])
    session = FakeSession(kp)
    cache: dict = {}
    out1 = resolve_scene_spec_for_question(
        session,
        parent_id="p",
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
        parent_id="p",
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
            parent_id="p",
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
            parent_id="p",
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
    exact = _KP([{"kind": "reflection", "tag": "上学期"}])
    session = _SequenceSession([exact])
    out = resolve_scene_spec_for_question(
        session,
        parent_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        semester="上学期",
    )
    assert out["tag"] == "上学期"
    assert session.exec_calls == 1  # 精确命中，未触发回落


def test_resolve_falls_back_to_year_wide_when_no_exact():
    """同学期无模板 → 第二次查询命中整学年（semester=''）模板。"""
    year_wide = _KP([{"kind": "reflection", "tag": "整学年"}])
    session = _SequenceSession([None, year_wide])  # 第一次（精确）无果
    out = resolve_scene_spec_for_question(
        session,
        parent_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        semester="下学期",
    )
    assert out["tag"] == "整学年"
    assert session.exec_calls == 2  # 精确未中 → 回落整学年


def test_resolve_no_semester_queries_once():
    """题目未指定学期（''）→ 只查整学年一次，不做多余的精确查询。"""
    year_wide = _KP([{"kind": "reflection", "tag": "整学年"}])
    session = _SequenceSession([year_wide])
    out = resolve_scene_spec_for_question(
        session,
        parent_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        semester="",
    )
    assert out["tag"] == "整学年"
    assert session.exec_calls == 1


def test_resolve_semester_aware_cache_key():
    """缓存键含学期：同学期不同学期是两个独立条目，不互相污染。"""
    session = _SequenceSession([_KP([{"kind": "reflection", "tag": "A"}])])
    cache: dict = {}
    kw = dict(
        session=session,
        parent_id="p",
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
