"""内置场景注册表（ADR-0073 v3）单元测试。

主线有四条，每条都对着一个**已经发生过或很容易发生**的坑：
1. 注册表是进程级共享常量 → 必须验证取出来的东西被改脏不会污染后续实例；
2. 种子必须中性（不预填 figure/points）→ 否则后台兜底会退化成「永远给个房子」；
3. 快照铁律 → 改注册表绝不能影响已落库的 ``Question.scene_spec``；
4. 浏览页的「内置实例」口径 → 只数引用了该 kind 的知识点，且不按知识点重复计数。
"""
from __future__ import annotations

import copy
import uuid

from app.features.materials.scene_figures import figure_by_key
from app.features.materials.scene_fusion import (
    default_scene_from_figure,
    fuse_scene_spec,
)
from app.features.materials.scene_templates import (
    SCENE_LIBRARY,
    get_builtin_scene,
    instantiate_builtin,
    list_builtin_scenes,
)
from app.features.materials.service import list_scene_library


def _inputs_of(spec):
    return {i["key"]: i["value"] for i in spec["inputs"]}


def test_reflection_seed_is_neutral():
    """中性种子：给参数与取值范围，但**不带图形**。

    一旦这里预填了 figure/points，后端兜底就会在「题面没点名图形」时也给出一个
    图形——那不是讲解，是臆造。
    """
    spec = get_builtin_scene("reflection")
    assert spec is not None
    vals = _inputs_of(spec)
    assert vals["axisAngle"] == 90
    assert vals["axisX"] == 0.5
    assert vals["axisY"] == 0.5
    assert vals["figure"] == ""
    assert vals["points"] == []
    # 结论也不预置：是不是轴对称取决于具体图形，只有实例化方知道。
    assert spec["outputs"] == {}


def test_unknown_kind_returns_none():
    assert get_builtin_scene("rotation") is None
    assert get_builtin_scene("") is None
    assert get_builtin_scene(None) is None
    assert instantiate_builtin("rotation", {"figure": "house"}) is None


def test_registry_return_is_isolated_deep_copy():
    """改返回值不许污染注册表——否则第二个知识点会莫名带上第一个的参数。"""
    mutated = get_builtin_scene("reflection")
    for inp in mutated["inputs"]:
        if inp["key"] == "axisAngle":
            inp["value"] = 1
    mutated["title"] = "被改脏了"
    fresh = get_builtin_scene("reflection")
    assert _inputs_of(fresh)["axisAngle"] == 90
    assert fresh["title"] == "轴对称演示"


def test_instantiate_overrides_and_appends_new_inputs():
    """覆盖同名 key + 补进模板里没有的 key（承袭 ADR-0061 §Q 的教训）。"""
    spec = instantiate_builtin(
        "reflection",
        {"axisAngle": 45, "figure": "square", "points": [[0.1, 0.2]]},
    )
    vals = _inputs_of(spec)
    assert vals["axisAngle"] == 45
    assert vals["figure"] == "square"
    assert vals["points"] == [[0.1, 0.2]]
    # 未列出的项保持注册表默认，而不是被清成空
    assert vals["axisY"] == 0.5


def test_list_builtin_scenes_returns_copies():
    first = list_builtin_scenes()
    assert len(first) == len(SCENE_LIBRARY)
    first[0]["title"] = "脏了"
    assert list_builtin_scenes()[0]["title"] == "轴对称演示"


def test_snapshot_unaffected_by_registry_change():
    """快照铁律（比早期草案更强）：实例从不引用注册表。

    所以即使把注册表改个底朝天，已经生成、已经发到学生手里的场景也不该有
    任何变化；同时重新融合同一份 ``kp.scenes`` 也不受影响。
    """
    kp_scenes = get_builtin_scene("reflection")
    snapshot = fuse_scene_spec(
        kp_scenes, overrides={"figure": "square", "points": [[0, 0]]}
    )
    before = copy.deepcopy(snapshot)
    try:
        SCENE_LIBRARY["reflection"]["inputs"][0]["value"] = 1
        SCENE_LIBRARY["reflection"]["title"] = "改过的默认值"
        assert snapshot == before
        assert (
            fuse_scene_spec(
                kp_scenes, overrides={"figure": "square", "points": [[0, 0]]}
            )
            == before
        )
    finally:
        SCENE_LIBRARY["reflection"]["inputs"][0]["value"] = 90
        SCENE_LIBRARY["reflection"]["title"] = "轴对称演示"


def test_default_scene_from_figure_still_reports_shape_truth():
    """重构为注册表消费者后的回归保护：特有的三项仍按图形给出。"""
    shape = figure_by_key("square")
    spec = default_scene_from_figure("square")
    assert spec["kind"] == "reflection"
    assert spec["title"] == f"{shape.label}·轴对称"
    assert spec["derivedFrom"] == "figure_library"
    assert _inputs_of(spec)["figure"] == "square"
    assert _inputs_of(spec)["axisAngle"] == shape.default_axis_angle
    # 是不是轴对称如实回答，不写死 True（平行四边形就该是 False）
    assert spec["outputs"] == {"isAxisymmetric": True}
    assert default_scene_from_figure("para")["outputs"] == {
        "isAxisymmetric": False
    }


def test_default_scene_does_not_fabricate_figure():
    assert default_scene_from_figure(None) is None
    assert default_scene_from_figure("not-a-figure") is None


class _FakeKp:
    def __init__(self, name, scenes, *, semester="上学期"):
        self.id = uuid.uuid4()
        self.name = name
        self.subject = "数学"
        self.grade = 4
        self.semester = semester
        self.scenes = scenes


class _Rows:
    def __init__(self, rows):
        self._rows = rows

    def all(self):
        return self._rows


class _ListSession:
    def __init__(self, rows):
        self._rows = rows

    def exec(self, *a, **k):
        return _Rows(self._rows)


def test_list_scene_library_counts_distinct_knowledge_points():
    """「内置实例数量」= 引用该 kind 的知识点数，且同一知识点不重复计数。"""
    same = _FakeKp(
        "轴对称",
        [
            {"kind": "reflection", "inputs": []},
            {"kind": "reflection", "inputs": []},  # 同知识点第二个同 kind 场景
        ],
    )
    other = _FakeKp("平移", [{"kind": "rotation", "inputs": []}])
    none = _FakeKp("还没配", None)
    library = list_scene_library(
        _ListSession([same, other, none]), teacher_id=uuid.uuid4()
    )
    reflection = next(s for s in library.scenes if s.kind == "reflection")
    # 同一知识点的两个同 kind 场景只算一个实例；rotation 不在注册表里所以不出现。
    assert reflection.instance_count == 1
    assert len(reflection.associated_knowledge_points) == 1
    assert reflection.associated_knowledge_points[0].id == same.id
    assert reflection.associated_knowledge_points[0].scenes == same.scenes
    # 注册表里的每个 kind 都要有条目，即使没人引用
    assert {s.kind for s in library.scenes} == set(SCENE_LIBRARY)
