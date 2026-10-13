"""GET /questions 必须下发 `semester` 与 `scene_spec`（ADR-0061 §U / ADR-0091）。

为什么是**接口级**测试而不是只测 service：此前 `scene_spec` 只加在了助手查询
工具的 service 投影里，**REST 端点的 schema / router 整段漏写**——前端题库详情
拿到的永远是 null，于是「题库详情没有图形」。单测 service 全绿也照漏不误，
只有打到端点才能钉住这条链路。

两条断言：
1. 未配模板、题面点名图形 → 图库兜底出图（ADR-0091 新形：顶点在 `figure` 里，
   命中的是正方形，带图库身份键）；
2. 纯计算题（题面无图形）→ `scene_spec` 为 null，不臆造。

（「选项文字不反猜图形」由 ``tests/features/materials/test_scene_fusion.py``
在生产端单测钉住，此处不重复。）

⚠️ ADR-0091 ticket 02 起生产端产**有类型** SceneSpec；响应侧 `model_dump()`
序列化归 ticket 03——在本票合入后、ticket 03 落地前，本文件第 1 条会因端点
响应校验（schema 仍声明 `dict | None`）转红，属**契约变更红**，非回归。
"""
import uuid

from sqlmodel import Session as DBSession

from app.core.db import engine
from app.db.models import Question
from tests.utils.user import auth_headers, register_teacher


def _teacher_id(client, token: str) -> uuid.UUID:
    r = client.get("/api/v1/auth/me", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return uuid.UUID(r.json()["id"])


def _list(client, token: str) -> list[dict]:
    r = client.get("/api/v1/questions", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return r.json()["items"]


def test_bank_list_returns_semester(client):
    r = register_teacher(client, username="bank_scene_teacher")
    token = r.json()["access_token"]
    pid = _teacher_id(client, token)
    with DBSession(engine) as s:
        s.add(
            Question(
                id=uuid.uuid4(),
                teacher_id=pid,
                subject="数学",
                grade=4,
                knowledge_point="图形的运动（轴对称）",
                qtype="choice",
                stem="下面哪个图形是轴对称图形？",
                options=["A. 房子", "B. 平行四边形"],
                answer="A",
                semester="下学期",
            )
        )
        s.commit()
    item = next(i for i in _list(client, token) if "轴对称" in i["knowledge_point"])
    # 详情「知识点信息」要展示学期；此前 schema 漏字段 → 永远显示整学年。
    assert item["semester"] == "下学期"


def test_bank_list_scene_spec_falls_back_to_figure_library(client):
    """没配任何知识点模板时，「正方形有几条对称轴」也必须出图（ADR-0091 新形）。"""
    r = register_teacher(client, username="bank_scene_teacher2")
    token = r.json()["access_token"]
    pid = _teacher_id(client, token)
    with DBSession(engine) as s:
        s.add(
            Question(
                id=uuid.uuid4(),
                teacher_id=pid,
                subject="数学",
                grade=4,
                knowledge_point="图形的运动（轴对称）",
                qtype="choice",
                stem="正方形有几条对称轴？",
                options=["A. 1条", "B. 2条", "C. 3条", "D. 4条"],
                answer="D",
            )
        )
        s.commit()
    item = next(i for i in _list(client, token) if "正方形" in i["stem"])
    spec = item["scene_spec"]
    assert spec is not None, "题库详情 no 图形：scene_spec 不应为 null"
    assert spec["kind"] == "reflection"
    # ADR-0091：顶点收进主图形，带图库身份键；顶层不再摊平 points/edges，
    # 也没有 derivedFrom（来源标记字段已从生产端移除）
    assert set(spec) == {"kind", "figure", "options", "curated"}
    assert spec["figure"]["key"] == "square"
    assert "derivedFrom" not in spec
    # 顶点必须随 spec 下发（只发 kind 的话前端会画回兜底房子）
    assert len(spec["figure"]["points"]) == 4


def test_bank_list_no_figure_word_has_no_scene(client):
    """纯计算题没有图形可讲 → null，前端据此不渲染图形区（不占位、不报错）。"""
    r = register_teacher(client, username="bank_scene_teacher3")
    token = r.json()["access_token"]
    pid = _teacher_id(client, token)
    with DBSession(engine) as s:
        s.add(
            Question(
                id=uuid.uuid4(),
                teacher_id=pid,
                subject="数学",
                grade=4,
                knowledge_point="两位数加减法",
                qtype="calc",
                stem="学校图书馆有故事书 86 本，借出 47 本，还剩多少本？",
                answer="39",
            )
        )
        s.commit()
    item = next(i for i in _list(client, token) if "图书馆" in i["stem"])
    assert item["scene_spec"] is None
