"""内置图形**种子**不变量（ADR-0061 §O / ADR-0083）。

几何事实源已是 `figure_library` 表（决策 1）。本文件守两件事：

1. **种子几何自身正确**：顶点数 ≥3、落在单位方格内、`para` 不能被「修好」成矩形、
   每个图形都带 `note`（教学意图不能失传）、正方形确实是轴对齐正方形。
2. **端点下发 == 种子**：`GET /materials/scene-library/figures` 读表且不做二次加工。

⚠️ 已随 ADR-0083 退役（勿再回归）：
- **前后端 parity 锁**（`TestFrontendBackendParity`）与 `gen_figures.py --check`——
  前端不再有 `figures.dart` 生成物，改为创作 UI 按需 `GET`（决策 7）。
- **一切 axis 断言**（`axis_angles` / `axis_count` / `default_axis_angle`）——图库
  不存 axis 属性（决策 2：对称判定纯视觉，拖轴 + 翻转自己看）。轴**初值**属 kind
  交互外壳，见 `test_scene_templates.py`。
"""
from __future__ import annotations

from app.features.materials.scene_figures import BUILTIN_FIGURE_SEED


class TestSeedSelfConsistency:
    def test_keys_unique(self):
        keys = [f.key for f in BUILTIN_FIGURE_SEED]
        assert len(keys) == len(set(keys)), "图形 key 重复"

    def test_has_eleven_builtin_figures(self):
        assert len(BUILTIN_FIGURE_SEED) == 11, (
            "内置图形数量变了——画廊/课件选择器的默认铺开规模随之变化，"
            "确认是有意为之再改这条断言"
        )

    def test_all_figures_have_at_least_3_vertices(self):
        for f in BUILTIN_FIGURE_SEED:
            assert len(f.vertices) >= 3, f"{f.key} 顶点少于 3 个，不成多边形"

    def test_vertices_in_unit_square(self):
        for f in BUILTIN_FIGURE_SEED:
            for x, y in f.vertices:
                assert 0.0 <= x <= 1.0 and 0.0 <= y <= 1.0, f"{f.key} 顶点越界 {(x, y)}"

    def test_every_figure_carries_a_note(self):
        """每个图形都必须带 note——「为什么 para 必须歪着」这类教学意图不能失传。"""
        for shape in BUILTIN_FIGURE_SEED:
            assert shape.note.strip(), f"{shape.key} 缺 note（教学意图说明）"

    def test_para_is_deliberately_asymmetric(self):
        """平行四边形**必须**保持不对称——它就是那道「不是轴对称」的干扰项。

        不对称体现在**错切**（shear）：上下两条边等宽但中心错开（上边中点 0.50、
        下边中点 0.62）。有人若嫌「歪」把它修正成矩形，这道题就废了。这里钉住。
        """
        para = next(f for f in BUILTIN_FIGURE_SEED if f.key == "para")
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

    def test_square_vertices_form_an_axis_aligned_square(self):
        """正方形是轴对齐、零微扰的正方形（ADR-0061 §Q 决策 A）。

        顶点按顺序绕一圈，故「边长」要看**相邻顶点的距离**（含水平边与竖直边），
        而不是横坐标之差。
        """
        v = next(f for f in BUILTIN_FIGURE_SEED if f.key == "square").vertices
        assert len(v) == 4, "正方形必须是 4 个顶点"

        def dist(a, b) -> float:
            return round(((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5, 6)

        sides = [dist(v[i], v[(i + 1) % 4]) for i in range(4)]
        assert len(set(sides)) == 1, f"四边必须等长，实测{sides}"
        assert sides[0] > 0, "边长必须为正"
        # 轴对齐（决策 A 的核心——不引入任何旋转/微扰）：4 个顶点落在两个 x、两个 y 上
        assert len({x for x, _ in v}) == 2, "轴对齐：只应有两个不同的 x"
        assert len({y for _, y in v}) == 2, "轴对齐：只应有两个不同的 y"


class TestFigureLibraryEndpoint:
    """`GET /materials/scene-library/figures` 读的是 `figure_library` 表。"""

    def test_matches_seed_geometry_and_edges(self, db):
        """端点不做二次加工：points 与种子逐点一致，edges 按顶点顺序补默认闭合。"""
        from app.features.materials.service import list_figure_library

        resp = list_figure_library(db)
        by_key = {f.key: f for f in resp.figures}
        assert set(by_key) == {f.key for f in BUILTIN_FIGURE_SEED}, "表里的 key 集合与种子不一致"
        for shape in BUILTIN_FIGURE_SEED:
            item = by_key[shape.key]
            assert item.points == [[x, y] for x, y in shape.vertices]
            n = len(shape.vertices)
            assert item.edges == [[i, (i + 1) % n] for i in range(n)]
            # 内置图形 is_builtin=True
            assert item.is_builtin is True
            # note 随种子落库（教学意图），且是给维护者看的说明、不是渲染数据
            assert (item.note or "").strip() == shape.note.strip()

    def test_response_carries_no_axis_attribute(self, db):
        """图库**不表态**对称轴（ADR-0083 决策 2）：响应里不得出现任何 axis 字段。"""
        from app.features.materials.service import list_figure_library

        item = list_figure_library(db).figures[0]
        dumped = item.model_dump()
        axis_like = {k for k in dumped if "axis" in k.lower()}
        assert axis_like == set(), f"图库响应不该带 axis 字段，实测 {axis_like}"

    def test_figure_geometry_reads_db_and_returns_plain_geometry(self, db):
        from app.features.materials.scene_figures import figure_geometry

        geom = figure_geometry(db, "square")
        assert geom is not None
        assert set(geom) == {"key", "label", "points", "edges"}
        assert len(geom["points"]) == 4
        assert len(geom["edges"]) == 4
        # 未命中返回 None——绝不兜底到某个内置图形（反臆造，ADR-0061 §U）
        assert figure_geometry(db, "nope") is None
        assert figure_geometry(db, None) is None
