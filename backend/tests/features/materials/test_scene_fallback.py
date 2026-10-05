"""图库兜底场景（ADR-0061 §U）单元测试。

背景：教师**没配**知识点模板时，交互讲解此前一律返回 None —— 于是「正方形有
几条对称轴」这类最典型的题在题库详情 / 错题本里**永远不出图**，家长看到的就是
「功能没做」。几何的权威来源是图库（``scene_figures``），题面点名了图形就该出图。

本文件钉住三件事：
1. 命中图形 → 出图，顶点直接来自图库（与前端 `figures.dart` 逐点一致）；
2. 没命中图形 → **None**（绝不臆造一个图形给纯计算题）；
3. ``outputs.isAxisymmetric`` 如实（平行四边形 = False），不替学生答。
"""
from app.features.materials.scene_figures import figure_by_key
from app.features.materials.scene_fusion import (
    build_scene_spec_for_question,
    default_scene_from_figure,
    scene_spec_for_read,
)


class _KP:
    def __init__(self, scenes):
        self.scenes = scenes


class _ExecChain:
    def __init__(self, kp):
        self._kp = kp

    def where(self, *a, **k):
        return self

    def order_by(self, *a, **k):
        return self

    def first(self):
        return self._kp


class _NoTemplateSession:
    """模拟「知识点存在但没配模板 / 知识点压根不存在」。"""

    def __init__(self):
        self.exec_calls = 0

    def exec(self, *a, **k):
        self.exec_calls += 1
        return _ExecChain(None)


def _vals(spec):
    return {i["key"]: i["value"] for i in spec["inputs"]}


def test_default_scene_unknown_key_returns_none():
    assert default_scene_from_figure(None) is None
    assert default_scene_from_figure("不存在的图形") is None


def test_default_scene_square_geometry_from_library():
    """正方形顶点必须**逐点等于**图库里的那份（几何单一事实源）。"""
    spec = default_scene_from_figure("square")
    assert spec is not None
    assert spec["kind"] == "reflection"
    square = figure_by_key("square")
    assert _vals(spec)["points"] == [[x, y] for x, y in square.vertices]
    # 4 个顶点、轴对齐（决策 A：零微扰）
    pts = _vals(spec)["points"]
    assert len(pts) == 4
    assert sorted({p[0] for p in pts}) == [0.28, 0.72]
    assert sorted({p[1] for p in pts}) == [0.28, 0.72]


def test_default_scene_is_editable_and_truthful():
    """学生端要能自己拖轴（editable=True）；是否轴对称**如实**，不写死 True。"""
    assert default_scene_from_figure("square")["editable"] is True
    assert default_scene_from_figure("square")["outputs"]["isAxisymmetric"] is True
    # 平行四边形真的没有对称轴 → False（写死 True 等于替学生答「它是对称图形」）
    assert default_scene_from_figure("para")["outputs"]["isAxisymmetric"] is False


def test_default_scene_narrative_leaks_no_answer():
    """引导语不得出现「对称轴条数」——那是「有几条对称轴」的答案。

    只禁「数字 + 条」这类计数表述；「两侧」是正常的几何描述，不在禁列。
    """
    import re

    text = default_scene_from_figure("square")["narrative"]
    assert re.search(r"[0-9]+|[四三两一二]\s*条", text) is None


def test_build_falls_back_to_library_without_template():
    """无模板 + 题面点名正方形 → 照样出图（这是本次修复的核心）。"""
    session = _NoTemplateSession()
    spec = build_scene_spec_for_question(
        session,
        parent_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        semester="",
        stem="正方形有几条对称轴？",
    )
    assert spec is not None
    assert _vals(spec)["figure"] == "square"
    assert spec["derivedFrom"] == "figure_library"


def test_option_group_drops_library_verdict():
    """选项组里每个选项判定不同 → 兜底场景不得给统一结论（否则等于替学生答）。

    「下面哪个图形是轴对称图形？」的兜底图形取自题面首个命中项，它的
    「是不是轴对称」与其余选项无关，留着就是错的。
    """
    session = _NoTemplateSession()
    spec = build_scene_spec_for_question(
        session,
        parent_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        stem="下面哪个图形是轴对称图形？",
        options=["A. 平行四边形", "B. 房子", "C. 风筝", "D. 箭头"],
    )
    assert spec is not None
    assert len(spec["optionGroup"]["items"]) == 4
    assert "outputs" not in spec


def test_build_no_figure_word_returns_none():
    """纯计算题没有图形可讲 → None，绝不臆造图形。"""
    session = _NoTemplateSession()
    assert (
        build_scene_spec_for_question(
            session,
            parent_id="p",
            subject="数学",
            grade=4,
            knowledge_point="两位数加减法",
            semester="",
            stem="学校图书馆有故事书 86 本，借出 47 本，还剩多少本？",
        )
        is None
    )


def test_build_fallback_applies_stem_angle():
    """兜底场景也要吃到题面角度（「沿 45° 对折」）。"""
    session = _NoTemplateSession()
    spec = build_scene_spec_for_question(
        session,
        parent_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        stem="正方形沿 45° 的线对折能重合吗？",
    )
    assert _vals(spec)["axisAngle"] == 45.0


def test_template_still_wins_over_library():
    """教师配了模板 → 用模板（不能用图库兜底覆盖教师意图）。"""
    template = [{"kind": "reflection", "inputs": [{"key": "figure", "value": "house"}]}]

    class _Session:
        def exec(self, *a, **k):
            return _ExecChain(_KP(template))

    spec = build_scene_spec_for_question(
        _Session(),
        parent_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        stem="正方形有几条对称轴？",
    )
    assert _vals(spec)["figure"] == "square"  # 题面覆盖模板默认图形
    assert "derivedFrom" not in spec  # 走的是教师模板，不是图库兜底


def test_scene_spec_for_read_prefers_snapshot():
    """有快照就原样返回（模板后续改动不影响已生成的题），且**不查库**。"""
    snapshot = {"kind": "reflection", "inputs": []}

    class _BoomSession:
        def exec(self, *a, **k):  # pragma: no cover - 不应被调用
            raise AssertionError("有快照时不得回退实时解析")

    out = scene_spec_for_read(
        _BoomSession(),
        snapshot=snapshot,
        parent_id="p",
        subject="数学",
        grade=4,
        knowledge_point="KP",
    )
    assert out is snapshot


def test_scene_spec_for_read_empty_snapshot_falls_back():
    """空快照（JSON null 归一化后的 None / {}）等同没有 → 走回退。"""
    session = _NoTemplateSession()
    assert (
        scene_spec_for_read(
            session,
            snapshot=None,
            parent_id="p",
            subject="数学",
            grade=4,
            knowledge_point="两位数加减法",
            stem="86 - 47 = ?",
        )
        is None
    )
    out = scene_spec_for_read(
        session,
        snapshot={},
        parent_id="p",
        subject="数学",
        grade=4,
        knowledge_point="图形的运动（轴对称）",
        stem="长方形有几条对称轴？",
    )
    assert out is not None and _vals(out)["figure"] == "rectangle"
