"""内置场景注册表（ADR-0073 v3 / ADR-0083）单元测试。

主线有四条，每条都对着一个**已经发生过或很容易发生**的坑：
1. 注册表是进程级共享常量 → 必须验证取出来的东西被改脏不会污染后续实例；
2. 外壳必须中性（只声明交互，不含几何）→ 否则后台兜底会退化成「永远给个房子」；
3. 快照铁律 → 改注册表绝不能影响已落库的 ``Question.scene_spec``；
4. 浏览页的「内置实例」口径 → 只数引用了该 kind 的知识点，且不按知识点重复计数。
"""
from __future__ import annotations

import copy
import uuid

from app.features.materials.scene_fusion import (
    default_scene_from_figure,
    fuse_scene_spec,
)
from app.features.materials.scene_templates import (
    REFLECTION_SHELL,
    SCENE_LIBRARY,
    get_builtin_scene,
    list_builtin_scenes,
)
from app.features.materials.service import list_scene_library


def test_reflection_shell_is_neutral():
    """外壳是「交互外壳」：给轴初值 / 控件 / 引导文案，但**不带任何几何**。

    一旦这里预填了 points/edges/figure，后端兜底就会在「题面没点名图形」时也给出
    一个图形——那不是讲解，是臆造。
    """
    shell = get_builtin_scene("reflection")
    assert shell is not None
    assert shell["kind"] == "reflection"
    assert shell["axisAngle"] == 90
    assert shell["axisX"] == 0.5
    assert shell["axisY"] == 0.5
    assert shell["controls"] == {"play": True, "scrub": True}
    assert shell["narrative"]
    # 外壳不含几何、不含已删字段（决策 5）
    for banned in ("points", "edges", "figure", "inputs", "outputs", "editable"):
        assert banned not in shell, f"外壳不该有 {banned}"


def test_shell_narrative_leaks_no_answer():
    """引导语不得出现「对称轴条数」——那是「有几条对称轴」的答案。"""
    import re

    text = REFLECTION_SHELL["narrative"]
    assert re.search(r"[0-9]+|[四三两一二]\s*条", text) is None


def test_unknown_kind_returns_none():
    assert get_builtin_scene("rotation") is None
    assert get_builtin_scene("") is None
    assert get_builtin_scene(None) is None


def test_registry_return_is_isolated_deep_copy():
    """改返回值不许污染注册表——否则第二个知识点会莫名带上第一个的参数。"""
    mutated = get_builtin_scene("reflection")
    mutated["axisAngle"] = 1
    mutated["title"] = "被改脏了"
    fresh = get_builtin_scene("reflection")
    assert fresh["axisAngle"] == 90
    assert fresh["title"] == "轴对称演示"


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
    kp_scenes = [
        {
            "kind": "reflection",
            "points": [[0.3, 0.7], [0.7, 0.7], [0.5, 0.3]],
            "edges": [[0, 1], [1, 2], [2, 0]],
        }
    ]
    override = {"points": [[0, 0], [1, 1], [0, 1]], "edges": [[0, 1], [1, 2], [2, 0]]}
    snapshot = fuse_scene_spec(kp_scenes, overrides=override)
    before = copy.deepcopy(snapshot)
    try:
        SCENE_LIBRARY["reflection"]["axisAngle"] = 1
        SCENE_LIBRARY["reflection"]["title"] = "改过的默认值"
        assert snapshot == before
        assert fuse_scene_spec(kp_scenes, overrides=override) == before
    finally:
        SCENE_LIBRARY["reflection"]["axisAngle"] = 90
        SCENE_LIBRARY["reflection"]["title"] = "轴对称演示"


def test_default_scene_from_figure_is_pure_geometry(db):
    """图库兜底产出**纯几何** SceneSpec：只有 kind / points / edges（+derivedFrom）。"""
    spec = default_scene_from_figure(db, "square")
    assert spec is not None
    assert spec["kind"] == "reflection"
    assert spec["derivedFrom"] == "figure_library"
    # 只剩几何字段（+来源标记）——旧字段一概不再出现
    assert set(spec) == {"kind", "points", "edges", "derivedFrom"}
    assert len(spec["points"]) == 4
    assert len(spec["edges"]) == 4


def test_default_scene_does_not_fabricate_figure(db):
    assert default_scene_from_figure(db, None) is None
    assert default_scene_from_figure(db, "not-a-figure") is None


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
            {"kind": "reflection", "points": [[0, 0], [1, 0], [0, 1]]},
            {"kind": "reflection", "points": [[0, 0], [1, 0], [0, 1]]},  # 同知识点第二个同 kind 场景
        ],
    )
    other = _FakeKp("平移", [{"kind": "rotation", "points": []}])
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
    # defaults 现在是「交互外壳」：带 axisAngle，不带几何
    assert reflection.defaults["axisAngle"] == 90
    assert "points" not in reflection.defaults
