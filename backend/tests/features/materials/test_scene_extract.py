"""题面 → 场景输入抽取（ADR-0061 §M 第1 步）单元测试。

核心主张：**抽不到就不抽，绝不猜**。给一个与题目无关的图形比不给场景更糟——
那会让教师对着错误图形理解本题。所以「空overrides」是合法且常见的结果。
"""
import uuid

from sqlalchemy import create_engine
from sqlmodel import Session, select

from app.db.models import KnowledgePoint
from app.features.materials.scene_extract import (
    extract_option_group,
    extract_scene_inputs,
)


class TestFigure:
    def test_stem_figure_wins(self):
        assert extract_scene_inputs(stem="下面哪个是轴对称图形？房子")["figure"] == "house"

    def test_falls_back_to_options(self):
        got = extract_scene_inputs(
            stem="下列图形中既是轴对称又是中心对称的是（  ）",
            options=["A. 风筝", "B. 任意四边形"],
        )
        assert got["figure"] == "kite"

    def test_para_not_stolen_by_generic_word(self):
        """「平行四边形」要能命中 para，而不是被更泛的词抢走。"""
        assert (
            extract_scene_inputs(stem="平行四边形是轴对称图形吗？")["figure"] == "para"
        )

    def test_stem_priority_over_options(self):
        """题面指定的图形优先于选项里出现的图形。"""
        got = extract_scene_inputs(
            stem="下图是风筝，它是对称图形吗？",
            options=["A. 房子", "B. 箭头"],
        )
        assert got["figure"] == "kite"

    def test_no_figure_no_key(self):
        """题面没提图形 → 干脆不给figure 键（让模板默认值留着）。"""
        assert "figure" not in extract_scene_inputs(stem="计算 12× 8 的结果")

    def test_empty_inputs(self):
        assert extract_scene_inputs(stem=None, options=None) == {}
        assert extract_scene_inputs(stem="", options=[]) == {}


class TestAxisAngle:
    def test_degree_symbol(self):
        assert extract_scene_inputs(stem="把图形沿45° 的线对折")["axisAngle"] == 45.0

    def test_chinese_degree_unit(self):
        assert extract_scene_inputs(stem="沿60度的直线对折")["axisAngle"] == 60.0

    def test_first_angle_wins(self):
        got = extract_scene_inputs(stem="从 30° 转到 90°，哪种是对称轴？")
        assert got["axisAngle"] == 30.0

    def test_out_of_range_rejected(self):
        """360° 是旋转题不是轴对称题 → 不覆盖（否则场景会转到无意义的角度）。"""
        assert "axisAngle" not in extract_scene_inputs(stem="图形绕中心旋转 360°")

    def test_negative_rejected(self):
        assert "axisAngle" not in extract_scene_inputs(stem="沿 -30° 对折")

    def test_no_angle_no_key(self):
        assert "axisAngle" not in extract_scene_inputs(stem="什么是轴对称图形？")


class TestAxisPositionNeverGuessed:
    def test_axis_x_y_never_extracted(self):
        """axisX/axisY 是归一化对称轴位置，题面极少精确表述 → 永远不猜。

        这条是「宁可沿用教师手摆的默认值，也不编一个与题目无关的位置」。
        """
        got = extract_scene_inputs(
            stem="把风筝沿x=0.3、y=0.7 的直线对折",
            options=None,
        )
        assert "axisX" not in got
        assert "axisY" not in got


class TestCombined:
    def test_figure_and_angle_together(self):
        got = extract_scene_inputs(
            stem="下图是一个箭头，沿 0° 的水平线对折，能完全重合吗？"
        )
        assert got["figure"] == "arrow"
        assert got["axisAngle"] == 0.0
        # 命中 figure 时**必须连带下发几何**（ADR-0061 §Q）：只改 figure 而留着
        # 模板里的旧顶点，画面上仍是上一个图形（前端 points 优先于 figure 预设）。
        assert got["points"] == [
            [0.20, 0.42],
            [0.62, 0.42],
            [0.62, 0.30],
            [0.82, 0.50],
            [0.62, 0.70],
            [0.62, 0.58],
            [0.20, 0.58],
        ]
        assert got["axisAngles"] == [0]
        assert got["axisCount"] == 1

    def test_figure_hit_always_carries_geometry(self):
        """任何 figure 命中都必须带上 points —— 否则改了等于没改。"""
        for stem in ("房子", "正方形有几条对称轴", "下列图形中风筝是轴对称图形吗"):
            got = extract_scene_inputs(stem=stem)
            assert "figure" in got, stem
            assert len(got["points"]) >= 3, stem
            assert got["axisCount"] >= 1, stem

    def test_square_carries_four_axes(self):
        """"正方形有几条对称轴"的答案 4，必须真的在数据里。"""
        got = extract_scene_inputs(stem="正方形有几条对称轴？")
        assert got["figure"] == "square"
        assert got["axisCount"] == 4
        assert sorted(got["axisAngles"]) == [0, 45, 90, 135]

    def test_para_carries_no_axes(self):
        """平行四边形真的没有对称轴 → axis_angles 空、axisCount **如实为 0**。

        不做「至少 1」兜底：这份数据回答的是「有几条对称轴」，兜底=教错。
        渲染要的初始轴是defaultAxisAngle（另一个字段）。
        """
        got = extract_scene_inputs(stem="平行四边形是轴对称图形吗")
        assert got["figure"] == "para"
        assert got["axisAngles"] == []
        assert got["axisCount"] == 0

    def test_realistic_choice_question(self):
        """真实形态的选择题：多个选项各有图形 → 只取第一个命中的（单kind 结构限制）。"""
        got = extract_scene_inputs(
            stem="下列图形中，轴对称图形有哪些？（  ）",
            options=["A. 房子", "B. 平行四边形", "C. 箭头", "D. 一般四边形"],
        )
        assert got["figure"] == "house"
        # 且这是刻意的：逐选项各配一个场景需要新 kind（集合语义），见 ADR §M 第3 步


class TestNoneStoresAsSqlNull:
    """`JSON(none_as_null=True)` 的回归守卫（ADR-0061 §M）。

    SQLAlchemy 的 JSON 类型**默认**把 Python ``None`` 序列化成文本 ``'null'``，
    于是「清空模板」写进去的是字符串而不是 SQL NULL：`IS NOT NULL` 为真、内容却是
    空的，任何「非空计数」都失真（实测：205 个知识点里唯一那条「有 scenes」的，
    内容就是文本 ``null``）。三个场景列都必须带 ``none_as_null=True``。
    """

    def _stored_form(self, value):
        """把 value 写进真实模型、落库，返回 (读回值, 底层 typeof, 底层值)。"""
        engine = create_engine("sqlite://")
        KnowledgePoint.__table__.create(engine)
        with Session(engine) as s:
            s.add(
                KnowledgePoint(
                    id=uuid.uuid4(),
                    teacher_id=uuid.uuid4(),
                    subject="数学",
                    grade=4,
                    semester="下学期",
                    name="轴对称",
                    scenes=value,
                )
            )
            s.commit()
            # 直接查底层存储形态：区分「SQL NULL」与「文本 'null'」
            stored = s.connection().exec_driver_sql(
                "SELECT scenes, typeof(scenes) FROM knowledgepoint"
            ).first()
            read_back = s.exec(select(KnowledgePoint)).first().scenes
        return read_back, stored[1], stored[0]

    def test_none_becomes_sql_null_not_text(self):
        read_back, type_of, raw = self._stored_form(None)
        assert read_back is None
        # 关键断言：底层是 SQL NULL（typeof='null' 且值为 None），而非文本 'null'
        assert type_of == "null", "应落库为 SQL NULL"
        assert raw is None, f"实际落库值={raw!r}，期望真正 NULL（而非文本 'null'）"

    def test_real_payload_round_trips(self):
        payload = {"kind": "reflection", "inputs": [{"key": "figure", "value": "kite"}]}
        read_back, _, _ = self._stored_form(payload)
        assert read_back == payload


class TestOptionGroup:
    """选项组（ADR-0061 §O）：每个选项一个独立可交互图形。"""

    def test_four_options_each_get_own_figure_and_points(self):
        g = extract_option_group(["A. 房子", "B. 风筝", "C. 箭头", "D. 平行四边形"])
        assert g is not None
        assert [i["label"] for i in g["items"]] == ["A", "B", "C", "D"]
        assert [i["caption"] for i in g["items"]] == ["房子", "风筝", "箭头", "平行四边形"]
        # 逐项带自己的顶点（前端据此渲染互不干扰的场景）
        for item in g["items"]:
            assert len(item["points"]) >= 3
            assert item["defaultAxisAngle"] in (0, 90)

    def test_arrow_gets_horizontal_default_axis(self):
        """箭头是横向的 → 默认轴 0°。若变成 90°，学生一打开就不重合。"""
        g = extract_option_group(["A. 箭头", "B. 房子"])
        by_caption = {i["caption"]: i for i in g["items"]}
        assert by_caption["箭头"]["defaultAxisAngle"] == 0
        assert by_caption["房子"]["defaultAxisAngle"] == 90

    def test_points_match_figure_library(self):
        """下发的 points 必须与图形库逐点一致（几何漂移会改判定）。"""
        from app.features.materials.scene_figures import figure_by_key

        g = extract_option_group(["A. 风筝", "B. 平行四边形"])
        for item in g["items"]:
            shape = figure_by_key(item["figureKey"])
            assert item["points"] == [[x, y] for x, y in shape.vertices]

    def test_label_from_chinese_separator(self):
        g = extract_option_group(["A、房子", "B、风筝"])
        assert [i["label"] for i in g["items"]] == ["A", "B"]

    def test_label_falls_back_to_index_when_no_prefix(self):
        g = extract_option_group(["房子", "风筝", "箭头"])
        assert [i["label"] for i in g["items"]] == ["A", "B", "C"]

    def test_all_or_nothing_when_one_option_unrecognized(self):
        """任一选项识别不出 → 整体 None（半套选项组比没有更容易误导）。"""
        g = extract_option_group(
            ["A. 房子", "B. 风筝", "C. 箭头", "D. 一些不认识的图形"]
        )
        assert g is None

    def test_needs_at_least_two_options(self):
        assert extract_option_group(["A. 房子"]) is None
        assert extract_option_group([]) is None
        assert extract_option_group(None) is None

    def test_two_options_is_valid(self):
        """两个选项也能逐个试（不必凑满 4个）。"""
        g = extract_option_group(["A. 房子", "B. 风筝"])
        assert g is not None and len(g["items"]) == 2
