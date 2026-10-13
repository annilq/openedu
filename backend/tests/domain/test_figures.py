"""图形（Figure）单测（ADR-0089 v3 / ADR-0091 ticket 01）。

``Figure`` 是几何的**唯一载体**：纯数据、零业务依赖。本文件只锁它的**形状契约**——
字段集、默认值、以及与前端 ``FigureShape`` 的同构（身份键 / 中文名 / 顶点 / 连接关系）。

「校验入口拒绝什么」不在这里，见 ``test_scene_spec.py``。
"""

from app.domain.figures import Figure


def test_shape_is_key_label_points_edges():
    """字段就是这四个，多一个少一个都会破坏与前端 ``FigureShape`` 的同构。"""
    assert set(Figure.model_fields) == {"key", "label", "points", "edges"}


def test_label_defaults_to_none():
    """中文名可选：身份靠 key，名字只是显示用。"""
    figure = Figure(key="para", points=[[0.30, 0.40]], edges=[])
    assert figure.label is None


def test_geometry_is_inlined_and_readable_as_is():
    """渲染只吃内联的 points / edges：原样进出，不做任何换算或补全。"""
    figure = Figure(
        key="para",
        label="平行四边形",
        points=[[0.30, 0.40], [0.70, 0.40], [0.82, 0.70], [0.42, 0.70]],
        edges=[[0, 1], [1, 2], [2, 3], [3, 0]],
    )
    assert figure.points == [[0.30, 0.40], [0.70, 0.40], [0.82, 0.70], [0.42, 0.70]]
    assert figure.edges == [[0, 1], [1, 2], [2, 3], [3, 0]]


def test_model_dump_keeps_snake_shape_for_wire():
    """落库 / 下发形状即字段本身：前端按同名键解析，不做字段名映射。"""
    figure = Figure(key="square", label="正方形", points=[[0.3, 0.3]], edges=[[0, 0]])
    assert figure.model_dump() == {
        "key": "square",
        "label": "正方形",
        "points": [[0.3, 0.3]],
        "edges": [[0, 0]],
    }
