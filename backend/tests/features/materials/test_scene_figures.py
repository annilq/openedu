"""图形顶点库前后端**同步守卫**（ADR-0061 §O / ADR-0073 遗留 4）。

后端 `scene_figures.py` 是顶点**唯一手写事实源**，前端 `figures.dart` 由
`frontend/scripts/gen_figures.py` **生成**（构建期，不是运行时拉取）。漂移的后果
不是「显示难看」，而是**「是否轴对称」的判定变错**——学生拖轴永远对不上。

所以本文件守两件事：
1. **跨语言逐字比对**：解析生成出来的 Dart 源，与 Python 侧比对，不一致立刻红
   （机制无关——就算哪天换了生成方式，只要产物对得上就通过）；
2. **生成物没过期**：直接跑 `gen_figures.py --check`，忘了重跑脚本就红。

代价是依赖前端源文件路径（CI 里前后端同仓才可用）；找不到文件时 ``skip`` 而不是
误报通过——但会打印提醒，别让它长期skip。
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

import pytest

from app.features.materials.scene_figures import FIGURES

# <repo>/backend/tests/features/materials/ → <repo>/frontend/lib/shared/domain/figures.dart
_FRONTEND = (
    Path(__file__).resolve().parents[4]
    / "frontend"
    / "lib"
    / "shared"
    / "domain"
    / "figures.dart"
)


def _parse_dart_figures() -> dict[str, dict]:
    """从 Dart 源里抠出 key → {label, points, defaultAxisAngle, axisAngles}。

    实现要点：**先按 `FigureShape(` 切块，再逐字段独立解析**。不要写成一个跨越
    全部字段的大正则——字段之间夹一行 `// 注释` 就会因 `.*?` 回溯把**下一个图形
    整块吞掉**（实测：`arrow` 的匹配吃掉了 `para`，导致「图形 key 不一致」误报）。
    用正则而非 Dart 解析器：这份文件是纯数据字面量，格式受我们控制；引入
    Dart 工具链依赖不值得（测试要在纯后端环境也能跑）。
    """
    src = _FRONTEND.read_text(encoding="utf-8")
    out: dict[str, dict] = {}
    for raw_block in src.split("FigureShape(")[1:]:
        block = raw_block
        key_m = re.search(r"key:\s*'([^']+)'", block)
        if not key_m:
            continue
        key = key_m.group(1)
        label_m = re.search(r"label:\s*'([^']+)'", block)
        verts_m = re.search(
            r"vertices:\s*<[^>]*>\[(.*?)\]", block, re.S
        )
        angle_m = re.search(r"defaultAxisAngle:\s*([0-9.]+)", block)
        axes_m = re.search(r"axisAngles:\s*<double>\[([^\]]*)\]", block)
        verts = (
            [
                (float(x), float(y))
                for x, y in re.findall(
                    r"\(x:\s*([0-9.]+),\s*y:\s*([0-9.]+)\)",
                    verts_m.group(1) if verts_m else "",
                )
            ]
            if verts_m
            else []
        )
        out[key] = {
            "label": label_m.group(1) if label_m else None,
            "vertices": verts,
            "defaultAxisAngle": float(angle_m.group(1)) if angle_m else None,
            "axisAngles": [
                float(a) for a in re.findall(r"([0-9.]+)", axes_m.group(1))
            ]
            if axes_m
            else None,
        }
    return out


@pytest.mark.skipif(not _FRONTEND.exists(), reason="前端源文件不在（纯后端检出）")
class TestFrontendBackendParity:
    def test_same_figure_keys(self):
        dart = _parse_dart_figures()
        assert set(dart) == {f.key for f in FIGURES}, (
            f"图形 key 不一致：前端 {sorted(dart)} vs 后端 {sorted(f.key for f in FIGURES)}"
        )

    def test_vertices_labels_and_angles_identical(self):
        dart = _parse_dart_figures()
        for f in FIGURES:
            assert len(dart[f.key]["vertices"]) == len(f.vertices), (
                f"{f.key} 顶点数不一致（几何漂移会改判定）"
            )
            for i, (dx, dy) in enumerate(dart[f.key]["vertices"]):
                bx, by = f.vertices[i]
                assert (dx, dy) == (bx, by), f"{f.key} 第 {i} 个顶点不一致: {dx,dy} vs {bx,by}"
            assert dart[f.key]["label"] == f.label, f"{f.key} 中文名不一致"
            assert dart[f.key]["defaultAxisAngle"] == f.default_axis_angle, (
                f"{f.key} 默认轴角度不一致"
            )
            assert dart[f.key]["axisAngles"] == list(f.axis_angles), (
                f"{f.key} 对称轴组不一致（『有几条对称轴』的答案会错）"
            )


class TestBackendSelfConsistency:
    def test_keys_unique(self):
        keys = [f.key for f in FIGURES]
        assert len(keys) == len(set(keys)), "图形 key 重复"

    def test_all_figures_have_at_least_3_vertices(self):
        for f in FIGURES:
            assert len(f.vertices) >= 3, f"{f.key} 顶点少于 3 个，不成多边形"

    def test_vertices_in_unit_square(self):
        for f in FIGURES:
            for x, y in f.vertices:
                assert 0.0 <= x <= 1.0 and 0.0 <= y <= 1.0, f"{f.key} 顶点越界 {(x, y)}"

    def test_para_is_deliberately_asymmetric(self):
        """平行四边形**必须**保持不对称——它就是那道「不是轴对称」的干扰项。

        不对称体现在**错切**（shear）：上下两条边等宽但中心错开（上边中点 0.50、
        下边中点 0.62），故不存在任何一条对称轴。有人若嫌「歪」把它修正成矩形，
        这道题就废了。这里钉住。
        """
        para = next(f for f in FIGURES if f.key == "para")
        ys = sorted({round(y, 4) for _, y in para.vertices})
        assert len(ys) == 2, f"para 应是上下两条边，实际 {len(ys)} 条"
        centers = []
        for yy in ys:
            xs_at = [x for x, y in para.vertices if abs(y - yy) < 1e-6]
            centers.append((min(xs_at) + max(xs_at)) / 2)
        assert abs(centers[0] - centers[1]) > 1e-3, (
            f"para 被修正成了矩形（上下边中点重合于 {centers[0]}）"
            " → 不再是干扰项，题目失去意义"
        )

    def test_to_dict_shape(self):
        d = FIGURES[0].to_dict()
        assert set(d) == {
            "key",
            "label",
            "points",
            "defaultAxisAngle",
            "axisAngles",
            "axisCount",
        }
        assert isinstance(d["points"][0], list) and len(d["points"][0]) == 2

    def test_figure_by_key_missing_returns_none(self):
        from app.features.materials.scene_figures import figure_by_key

        assert figure_by_key("nope") is None
        assert figure_by_key(None) is None
        assert figure_by_key("house").key == "house"


class TestSquareIsProceduralAndCorrect:
    """正方形是**程序生成**的（ADR-0061 §Q 决策 A），几何必须绝对正确。"""

    def _square(self):
        return next(f for f in FIGURES if f.key == "square")

    def test_has_exactly_four_axes(self):
        """「正方形有几条对称轴」= 4，这是题目的答案，不能错。"""
        sq = self._square()
        assert sq.axis_count == 4
        assert sorted(sq.axis_angles) == [0, 45, 90, 135]

    def test_vertices_form_an_axis_aligned_square(self):
        """决策 A：轴对齐、零微扰 —— 顶点必须严格构成正方形。

        顶点按顺序绕一圈：(x0,y0)→(x1,y1)→(x2,y2)→(x3,y3)，所以
        「边长」要看**相邻顶点的距离**（含水平边与竖直边），而不是横坐标之差。
        """
        v = self._square().vertices
        assert len(v) == 4, "正方形必须是 4 个顶点"

        def dist(a, b) -> float:
            return round(((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5, 6)

        sides = [dist(v[i], v[(i + 1) % 4]) for i in range(4)]
        assert len(set(sides)) == 1, f"四边必须等长，实测{sides}"
        assert sides[0] > 0, "边长必须为正"
        # 轴对齐（决策 A 的核心——不引入任何旋转/微扰）：4 个顶点落在两个 x、两个 y 上
        assert len({x for x, _ in v}) == 2, "轴对齐：只应有两个不同的 x"
        assert len({y for _, y in v}) == 2, "轴对齐：只应有两个不同的 y"

    def test_para_reports_no_axes(self):
        """平行四边形真的没有对称轴 → axis_angles 空、axis_count **如实为 0**。

        刻意不用「至少 1」兜底：这份数据用来回答「有几条对称轴」，兜底会把
        「它没有对称轴」谎报成 1 条 —— 那是教错。渲染要的初始轴另有
        ``default_axis_angle``，两者语义不同。
        """
        para = next(f for f in FIGURES if f.key == "para")
        assert para.axis_angles == []
        assert para.axis_count == 0
        # 但仍必须有初始轴可渲染
        assert para.default_axis_angle == 90

    def test_to_dict_exposes_axis_angles_and_count(self):
        d = self._square().to_dict()
        assert d["axisAngles"] == [90, 0, 45, 135]
        assert d["axisCount"] == 4

    def test_every_figure_carries_a_note(self):
        """每个图形都必须带 note——「为什么 para 必须歪着」这类教学意图不能失传。

        note 随生成脚本一起下发到前端，改顶点的人多半是在前端看到图形才动手的；
        没有 note 的话，「顺手把它修好看」的悲剧就有真实发生路径。
        """
        for shape in FIGURES:
            assert shape.note.strip(), f"{shape.key} 缺 note（教学意图说明）"

    def test_note_is_not_part_of_wire_format(self):
        """note 是给维护者看的，**不进** ``to_dict()``——渲染器不该收到它。

        一旦进 wire，前端 optionGroup 每个选项都会多扛一段中文，白白增大载荷，
        而且没人消费。
        """
        assert "note" not in self._square().to_dict()

    def test_figure_library_service_matches_source(self):
        """``GET /materials/scene-library/figures`` 的数据源就是 FIGURES 本身。

        端点与生成脚本读同一份数据，所以「API 下发的几何」与「前端随包内置的
        几何」不可能不一致——这条测试钉住端点没做二次加工（比如手抖补个兜底）。
        """
        from app.features.materials.service import list_figure_library

        resp = list_figure_library()
        assert [f.key for f in resp.figures] == [f.key for f in FIGURES]
        for item, shape in zip(resp.figures, FIGURES):
            assert item.points == [[x, y] for x, y in shape.vertices]
            # axisCount 必须**如实**等于轴列表长度，不补 1（补了就是教错）
            assert item.axisCount == len(item.axisAngles)
            assert item.axisCount == shape.axis_count


def test_frontend_figures_are_not_stale():
    """前端 `figures.dart` 必须是最新生成结果——**忘了跑脚本就红**。

    顶点改了却没重新生成，是这套「单一手写源 + 生成」方案唯一的失效模式：
    后端和前端会静默漂移，而渲染看起来"还能用"，直到某道题判定出错。所以把
    `--check` 接进测试，让失效变成 CI 可见的红灯。
    """
    script = _FRONTEND.parents[4] / "frontend" / "scripts" / "gen_figures.py"
    if not script.exists():
        pytest.skip(f"找不到生成脚本：{script}")
    proc = subprocess.run(
        [sys.executable, str(script), "--check"],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, (
        "前端 figures.dart 与后端图形库不一致（后端顶点改过但没重新生成）。\n"
        f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
    )
