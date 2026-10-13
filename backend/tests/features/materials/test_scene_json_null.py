"""``KnowledgePoint.scenes`` 的 JSON 列空值语义回归守卫（ADR-0061 §M）。

原在 ``test_scene_extract.py`` 里，随 ADR-0089 删除整个文本抽取模块（连同它的测试）
一起搬到这里——它守的是**列语义**，与抽取逻辑无关，不该被删掉。

``JSON(none_as_null=True)`` 的回归守卫（ADR-0061 §M）：SQLAlchemy 的 JSON 类型**默认**
把 Python ``None`` 序列化成文本 ``'null'``，于是「清空模板」写进去的是字符串而不是
SQL NULL：``IS NOT NULL`` 为真、内容却是空的，任何「非空计数」都失真（实测：205 个
知识点里唯一那条「有场景」的，内容就是文本 ``null``）。场景列必须带 ``none_as_null=True``。
"""
import uuid

from sqlalchemy import create_engine
from sqlmodel import Session, select

from app.db.models import KnowledgePoint


def _stored_form(value):
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


def test_none_becomes_sql_null_not_text():
    read_back, type_of, raw = _stored_form(None)
    assert read_back is None
    # 关键断言：底层是 SQL NULL（typeof='null' 且值为 None），而非文本 'null'
    assert type_of == "null", "应落库为 SQL NULL"
    assert raw is None, f"实际落库值={raw!r}，期望真正 NULL（而非文本 'null'）"


def test_real_payload_round_trips():
    payload = {
        "kind": "reflection",
        "figure": {
            "key": "house",
            "label": "房子",
            "points": [[0.3, 0.7], [0.7, 0.7], [0.5, 0.25]],
            "edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0]],
        },
    }
    read_back, _, _ = _stored_form(payload)
    assert read_back == payload
