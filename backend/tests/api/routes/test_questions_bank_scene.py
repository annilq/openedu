"""GET /questions 必须下发 `semester` 与 `scene_spec`（ADR-0061 §U）。

为什么是**接口级**测试而不是只测 service：此前 `scene_spec` 只加在了助手查询
工具的 service 投影里，**REST 端点的 schema / router 整段漏写**——前端题库详情
拿到的永远是 null，于是「题库详情没有图形」。单测 service 全绿也照漏不误，
只有打到端点才能钉住这条链路。

两条断言：
1. 未配模板、题面点名图形 → 图库兜底出图（`figure == "square"`）；
2. 纯计算题（题面无图形）→ `scene_spec` 为 null，不臆造。
"""
import uuid

from sqlmodel import Session as DBSession

from app.core.db import engine
from app.db.models import Question
from tests.utils.user import auth_headers, register_parent


def _parent_id(client, token: str) -> uuid.UUID:
    r = client.get("/api/v1/auth/me", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return uuid.UUID(r.json()["id"])


def _list(client, token: str) -> list[dict]:
    r = client.get("/api/v1/questions", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return r.json()["items"]


def test_bank_list_returns_semester(client):
    r = register_parent(client, username="bank_scene_parent")
    token = r.json()["access_token"]
    pid = _parent_id(client, token)
    with DBSession(engine) as s:
        s.add(
            Question(
                id=uuid.uuid4(),
                parent_id=pid,
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
    """没配任何知识点模板时，「正方形有几条对称轴」也必须出图。"""
    r = register_parent(client, username="bank_scene_parent2")
    token = r.json()["access_token"]
    pid = _parent_id(client, token)
    with DBSession(engine) as s:
        s.add(
            Question(
                id=uuid.uuid4(),
                parent_id=pid,
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
    vals = {i["key"]: i["value"] for i in spec["inputs"]}
    assert vals["figure"] == "square"
    # 顶点必须随 spec 下发（只发 figure 的话前端会画回模板默认的房子）
    assert len(vals["points"]) == 4


def test_bank_list_no_figure_word_has_no_scene(client):
    """纯计算题没有图形可讲 → null，前端据此不渲染图形区（不占位、不报错）。"""
    r = register_parent(client, username="bank_scene_parent3")
    token = r.json()["access_token"]
    pid = _parent_id(client, token)
    with DBSession(engine) as s:
        s.add(
            Question(
                id=uuid.uuid4(),
                parent_id=pid,
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
