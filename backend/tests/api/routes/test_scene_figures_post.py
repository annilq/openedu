"""画板保存用户图形（ADR-0083 T04）：``POST /materials/scene-library/figures``。

守四件事：
1. 写入 ``figure_library``（``is_builtin=False``），返回**后端分配**的 key（``user_`` 前缀）；
2. ``points`` / ``edges`` 完整往返；``edges`` 缺省 → 按顶点顺序补默认闭合；
3. 非法输入（<3 顶点 / 坐标越界 / 点非 [x,y] / 边索引越界 / 空名称）→ 422；
4. 行内**无任何 axis 属性**（对称判定是纯视觉，图库只留几何）。

⚠️ 套件共享一个 test DB（`tests/conftest.py` 只 unlink 一次），且 ``db`` 夹具**不清理**
``figure_library``。故本模块自带 autouse 清场，删掉写入的 ``user_*`` 行，避免污染
``test_scene_figures.py::test_figure_library_service_matches_source``（它断言库 == 内置集）。
"""
from __future__ import annotations

from collections.abc import Generator

import pytest
from sqlmodel import Session, delete

from app.core.db import engine
from app.db.models import FigureLibrary
from tests.utils.user import auth_headers, login, register_teacher

_ENDPOINT = "/api/v1/materials/scene-library/figures"

# 一个自定义三角形（刻意不是内置预设）。
_TRI = [[0.20, 0.80], [0.80, 0.80], [0.50, 0.30]]


@pytest.fixture(autouse=True)
def _clean_user_figures() -> Generator[None]:
    """删掉本模块留下的 ``user_*`` 图库行（前置 + 后置各一次，保证顺序无关）。"""

    def _purge() -> None:
        with Session(engine) as s:
            s.exec(delete(FigureLibrary).where(FigureLibrary.key.startswith("user_")))
            s.commit()

    _purge()
    yield
    _purge()


@pytest.fixture()
def ptoken(client) -> str:
    register_teacher(client, username="fig_post_teacher", password="pw123456")
    r = login(client, "fig_post_teacher", "pw123456")
    return r.json()["access_token"]


def _post(client, token, **body):
    return client.post(_ENDPOINT, headers=auth_headers(token), json=body)


def test_create_assigns_key_and_persists(client, ptoken):
    r = _post(client, ptoken, label="我的三角形", points=_TRI)
    assert r.status_code == 200, r.text
    item = r.json()
    # key 由后端分配，带 user_ 前缀（与内置短 key 一眼可分）
    assert item["key"].startswith("user_")
    assert item["label"] == "我的三角形"
    assert item["points"] == _TRI
    # edges 缺省 → 按顶点顺序闭合
    assert item["edges"] == [[0, 1], [1, 2], [2, 0]]
    # 用户行 ≠ 内置行
    assert item["is_builtin"] is False
    # **无任何 axis 属性**（对称纯视觉）
    for banned in (
        "axisAngle",
        "axisAngles",
        "axisCount",
        "defaultAxisAngle",
        "default_axis_angle",
    ):
        assert banned not in item

    # GET 能读到刚写入的行（同一事实源）
    listing = client.get(
        "/api/v1/materials/scene-library/figures", headers=auth_headers(ptoken)
    ).json()
    keys = {f["key"] for f in listing["figures"]}
    assert item["key"] in keys


def test_create_keeps_explicit_edges(client, ptoken):
    r = _post(
        client,
        ptoken,
        label="开折线",
        points=[[0.10, 0.10], [0.50, 0.50], [0.90, 0.20]],
        edges=[[0, 1], [1, 2]],
    )
    assert r.status_code == 200, r.text
    assert r.json()["edges"] == [[0, 1], [1, 2]]


def test_create_coerces_float_noise(client, ptoken):
    """画板拖拽可能产生 1.0000001 这类浮点噪声——不该当成越界，夹紧到 0..1。"""
    r = _post(
        client,
        ptoken,
        label="边界",
        points=[[-0.0000001, 1.0000001], [0.5, 0.5], [0.9, 0.1]],
    )
    assert r.status_code == 200, r.text
    pts = r.json()["points"]
    assert pts[0] == [0.0, 1.0]


@pytest.mark.parametrize(
    "bad_points",
    [
        [[0.1, 0.1], [0.5, 0.5]],  # 少于 3 个顶点
        [[0.1, 0.1], [0.5, 0.5], [1.5, 0.2]],  # 坐标越界
        [[0.1, 0.1], [0.5, 0.5], [0.2]],  # 某点不是 [x, y]
    ],
)
def test_create_rejects_bad_points(client, ptoken, bad_points):
    r = _post(client, ptoken, label="坏几何", points=bad_points)
    assert r.status_code == 422, r.text


def test_create_rejects_out_of_range_edge(client, ptoken):
    r = _post(client, ptoken, label="坏边", points=_TRI, edges=[[0, 9]])
    assert r.status_code == 422, r.text


def test_create_rejects_blank_label(client, ptoken):
    r = _post(client, ptoken, label="   ", points=_TRI)
    assert r.status_code == 422, r.text


def test_keys_unique_across_calls(client, ptoken):
    a = _post(client, ptoken, label="A", points=_TRI).json()["key"]
    b = _post(client, ptoken, label="B", points=_TRI).json()["key"]
    assert a != b


def test_requires_auth(client):
    r = client.post(_ENDPOINT, json={"label": "x", "points": _TRI})
    assert r.status_code in (401, 403), r.text
