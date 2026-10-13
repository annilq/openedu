"""题面 → 场景输入抽取（ADR-0061 §M / ADR-0083 / ADR-0091）单元测试。

核心主张：**抽不到就不抽，绝不猜**。给一个与题目无关的图形比不给场景更糟——
那会让教师对着错误图形理解本题。所以「空overrides」是合法且常见的结果。

ADR-0083 起：本模块只抽**图形名**（几何由上层按 key 查图库 DB），不再抽角度
（对称轴初值归 kind 外壳统一给定）。

ADR-0091 ticket 02 起：**只扫题面，不扫选项文字**——「扫选项文字反猜图形」的
代码路径已删（逐选项图形由 AI 链路「模型引用身份键 + 盖章」接回）。本文件钉住
这条删除：选项里出现图形词也不再产出主图形覆盖。
"""
import uuid

from sqlalchemy import create_engine
from sqlmodel import Session, select

from app.db.models import KnowledgePoint
from app.features.materials.scene_extract import extract_scene_inputs


class TestFigure:
    def test_stem_figure_wins(self):
        assert extract_scene_inputs(stem="下面哪个是轴对称图形？房子")["figure"] == "house"

    def test_para_not_stolen_by_generic_word(self):
        """「平行四边形」要能命中 para，而不是被更泛的词抢走。"""
        assert (
            extract_scene_inputs(stem="平行四边形是轴对称图形吗？")["figure"] == "para"
        )

    def test_no_figure_no_key(self):
        """题面没提图形 → 干脆不给figure 键（让模板默认值留着）。"""
        assert "figure" not in extract_scene_inputs(stem="计算 12× 8 的结果")

    def test_empty_inputs(self):
        assert extract_scene_inputs(stem=None) == {}
        assert extract_scene_inputs(stem="") == {}


class TestOptionTextNoLongerScanned:
    """ADR-0091 ticket 02：选项文字不再反猜图形。

    这条删除是**有意的**：文本匹配反猜会把「选项里出现房子」当成「本题演示房子」，
    而选项图形到底是谁应该由模型引用身份键来说（AI 链路票接回），后端只按身份键
    盖章几何。这里把「不再扫选项」钉住，免得有人凭旧记忆把 options 加回来。
    """

    def test_option_figure_words_produce_no_override(self):
        """题面没有图形词、只有选项有 → 空 dict（旧行为会回退命中选项）。"""
        got = extract_scene_inputs(stem="下列图形中既是轴对称又是中心对称的是（  ）")
        assert got == {}

    def test_realistic_choice_question_stem_only(self):
        """真实选择题：题面无图形词 → 不猜（逐选项图形归 AI 链路）。"""
        got = extract_scene_inputs(stem="下列图形中，轴对称图形有哪些？（  ）")
        assert got == {}


class TestAngleNoLongerExtracted:
    """ADR-0083 决策 6：对称轴初值归 kind 外壳，每条 scene 不再各自存。

    故题面里的角度数值**不再**产出 overrides——场景对称轴一律从反射外壳取（默认
    90°）。这里把「不再抽角度」钉住，免得有人凭旧记忆把它加回来。
    """

    def test_stem_angle_produces_no_override(self):
        assert "axisAngle" not in extract_scene_inputs(stem="把图形沿45° 的线对折")

    def test_only_figure_key_is_extracted(self):
        got = extract_scene_inputs(stem="正方形沿 45° 的线对折能重合吗？")
        assert set(got) == {"figure"}
        assert got["figure"] == "square"


class TestAxisPositionNeverGuessed:
    def test_axis_x_y_never_extracted(self):
        """axisX/axisY 是归一化对称轴位置，题面极少精确表述 → 永远不猜。

        这条是「宁可沿用教师手摆的默认值，也不编一个与题目无关的位置」。
        """
        got = extract_scene_inputs(stem="把风筝沿x=0.3、y=0.7 的直线对折")
        assert "axisX" not in got
        assert "axisY" not in got


class TestCombined:
    def test_figure_and_angle_together_no_geometry(self):
        """命中图形只给 key——几何由上层查图库取（ADR-0083）。"""
        got = extract_scene_inputs(stem="下图是一个箭头，沿 0° 的水平线对折，能完全重合吗？")
        assert got["figure"] == "arrow"
        # 不再连带下发几何 / 对称轴属性（几何事实源在 DB，对称判定改为纯视觉）
        assert "points" not in got
        assert "axisAngles" not in got
        assert "axisAngle" not in got


class TestNoneStoresAsSqlNull:
    """`JSON(none_as_null=True)` 的回归守卫（ADR-0061 §M）。

    SQLAlchemy 的 JSON 类型**默认**把 Python ``None`` 序列化成文本 ``'null'``，
    于是「清空模板」写进去的是字符串而不是 SQL NULL：`IS NOT NULL` 为真、内容却是
    空的，任何「非空计数」都失真（实测：205 个知识点里唯一那条「有场景」的，
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
        payload = {
            "kind": "reflection",
            "figure": {
                "key": "house",
                "label": "房子",
                "points": [[0.3, 0.7], [0.7, 0.7], [0.5, 0.25]],
                "edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0]],
            },
        }
        read_back, _, _ = self._stored_form(payload)
        assert read_back == payload
