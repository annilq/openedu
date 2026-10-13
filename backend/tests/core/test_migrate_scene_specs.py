"""存量 SceneSpec 快照迁移脚本测试（ADR-0091 §5 / ticket 05）。

接缝：脚本的可编程入口 ``migrate_session(session, dry_run=...)`` 与 CLI ``main()``。
全部断言走**外部行为**——临时库里的行内容与报告计数，不碰内部私有函数。

覆盖 ticket 05 验收：旧形 → 新形且顶点反查拿到身份键（figure / options 都查）；
反查不到 → ``user_`` 自绘前缀键（内容寻址、跨库稳定；不是展示名、不是兜底房子）；
幂等（连跑两次结果相同）；干跑默认不写库、``--apply`` 才落库；课件编排顺序严格保留。
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import sys
import uuid
from pathlib import Path

import pytest
from sqlmodel import Session, SQLModel, create_engine, select

from app.db.models import (
    Courseware,
    FigureLibrary,
    KnowledgePoint,
    Question,
    TaskQuestion,
    User,
)

_SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "migrate_scene_specs.py"
_spec = importlib.util.spec_from_file_location("migrate_scene_specs", _SCRIPT)
assert _spec is not None and _spec.loader is not None
migrate_scene_specs = importlib.util.module_from_spec(_spec)
# 先注册再执行：dataclass 在 py3.14 要从 sys.modules 找回模块命名空间。
sys.modules["migrate_scene_specs"] = migrate_scene_specs
_spec.loader.exec_module(migrate_scene_specs)

_TEACHER = uuid.UUID("11111111-1111-1111-1111-111111111111")

# 图库顶点（与 BUILTIN_FIGURE_SEED 逐点一致；迁移脚本按顶点反查的就是它们）。
_PARA_PTS = [[0.30, 0.40], [0.70, 0.40], [0.82, 0.70], [0.42, 0.70]]
_PARA_EDGES = [[0, 1], [1, 2], [2, 3], [3, 0]]
_SQUARE_PTS = [[0.28, 0.28], [0.72, 0.28], [0.72, 0.72], [0.28, 0.72]]
_SQUARE_EDGES = [[0, 1], [1, 2], [2, 3], [3, 0]]
# 库里**没有**的几何（教师画完又删了图库行）：反查必须落空 → user_ 键。
_KITE_PTS = [[0.50, 0.20], [0.72, 0.50], [0.50, 0.80], [0.28, 0.50]]
_KITE_EDGES = [[0, 1], [1, 2], [2, 3], [3, 0]]
# 渲染期最后兜底图形（房子）的顶点：断言它不被当作身份键落库。
_HOUSE_PTS = [[0.30, 0.70], [0.70, 0.70], [0.70, 0.45], [0.50, 0.25], [0.30, 0.45]]
_HOUSE_EDGES = [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0]]


def _user_key(points: list, edges: list) -> str:
    """与脚本同构的自绘键期望值（内容寻址：sha256(points+edges) 前 16 位）。"""
    payload = json.dumps(
        {"points": points, "edges": edges}, separators=(",", ":"), sort_keys=True
    )
    return "user_" + hashlib.sha256(payload.encode()).hexdigest()[:16]


_KITE_KEY = _user_key(_KITE_PTS, _KITE_EDGES)


def _legacy(points: list, edges: list, **extra) -> dict:
    """旧形 spec：顶点摊平在顶层。"""
    return {"kind": "reflection", "points": points, "edges": edges, **extra}


def _item(caption: str, points: list, edges: list, label: str = "") -> dict:
    """旧选项组条目（ADR-0061 §O 形状：标号 + 展示名 + 内联几何）。"""
    return {"label": label, "caption": caption, "points": points, "edges": edges}


def _figure(key: str, label: str, points: list, edges: list) -> dict:
    return {"key": key, "label": label, "points": points, "edges": edges}


def _task_question(**kwargs) -> TaskQuestion:
    base = dict(
        task_id=_TEACHER,
        subject="数学",
        grade=4,
        knowledge_point="轴对称图形",
        qtype="choice",
        stem="下列图形哪些是轴对称？",
    )
    return TaskQuestion(**{**base, **kwargs})


@pytest.fixture()
def engine(tmp_path):
    eng = create_engine(f"sqlite:///{tmp_path / 'migrate.db'}")
    SQLModel.metadata.create_all(eng)
    with Session(eng) as session:
        session.add(
            User(
                id=_TEACHER,
                username="teacher",
                display_name="教师",
                role="teacher",
                hashed_password="x",
            )
        )
        session.add(
            FigureLibrary(
                key="para",
                label="平行四边形",
                points=_PARA_PTS,
                edges=_PARA_EDGES,
                is_builtin=True,
            )
        )
        session.add(
            FigureLibrary(
                key="square",
                label="正方形",
                points=_SQUARE_PTS,
                edges=_SQUARE_EDGES,
                is_builtin=True,
            )
        )
        # 题目旧形：顶点摊平在顶层 + 来源标记（derivedFrom 应被丢弃）。
        session.add(
            Question(
                teacher_id=_TEACHER,
                subject="数学",
                grade=4,
                knowledge_point="轴对称图形",
                qtype="choice",
                stem="平行四边形是轴对称图形吗？",
                scene_spec=_legacy(
                    _PARA_PTS, _PARA_EDGES, derivedFrom="figure_library"
                ),
            )
        )
        # 任务题旧形：optionGroup 两项（square 命中图库；kite 库里没有 → user_ 键）。
        session.add(
            _task_question(
                scene_spec=_legacy(
                    _SQUARE_PTS,
                    _SQUARE_EDGES,
                    optionGroup={
                        "items": [
                            _item("正方形", _SQUARE_PTS, _SQUARE_EDGES, label="A"),
                            _item("风筝", _KITE_PTS, _KITE_EDGES, label="B"),
                        ]
                    },
                )
            )
        )
        # 知识点 scenes：一条旧形 + 一条已是新形（新形不得被再加工）。
        session.add(
            KnowledgePoint(
                teacher_id=_TEACHER,
                subject="数学",
                grade=4,
                name="轴对称图形",
                scenes=[
                    _legacy(_PARA_PTS, _PARA_EDGES),
                    {"kind": "reflection", "figure": _figure(
                        "para", "平行四边形", _PARA_PTS, _PARA_EDGES
                    )},
                ],
            )
        )
        # 课件环节：教师编排顺序刻意**反字母序**（kite 在前），验证顺序严格保留。
        session.add(
            Courseware(
                teacher_id=_TEACHER,
                subject="数学",
                grade=4,
                kp_name="轴对称图形",
                title="课件",
                sections=[
                    {"id": "s1", "kind": "scene", "scene": None},
                    {
                        "id": "s2",
                        "kind": "scene",
                        "scene": _legacy(
                            _SQUARE_PTS,
                            _SQUARE_EDGES,
                            optionGroup={
                                "curated": True,
                                "items": [
                                    _item("风筝", _KITE_PTS, _KITE_EDGES),
                                    _item("正方形", _SQUARE_PTS, _SQUARE_EDGES),
                                ],
                            },
                        ),
                    },
                ],
            )
        )
        session.commit()
    return eng


def _one(engine, model):
    with Session(engine) as s:
        return s.exec(select(model)).one()


def _run(engine, **kwargs):
    with Session(engine) as s:
        return migrate_scene_specs.migrate_session(s, **kwargs)


# ── 旧形 → 新形 + 顶点反查 ───────────────────────────────────────────
def test_legacy_snapshots_migrate_with_vertex_reverse_lookup(engine):
    report = _run(engine, dry_run=False)

    q = _one(engine, Question)
    # 顶层 points/edges 包成 figure，key 由图库反查得到，顶点逐点保留。
    assert q.scene_spec == {
        "kind": "reflection",
        "figure": _figure("para", "平行四边形", _PARA_PTS, _PARA_EDGES),
        "curated": False,
    }
    assert "derivedFrom" not in q.scene_spec

    tq = _one(engine, TaskQuestion)
    # 主图形反查 square；optionGroup.items → options，顺序保留。
    assert tq.scene_spec["figure"]["key"] == "square"
    options = tq.scene_spec["options"]
    assert [o["key"] for o in options] == ["square", _KITE_KEY]
    assert [o["label"] for o in options] == ["正方形", "风筝"]
    assert options[0]["points"] == _SQUARE_PTS
    assert options[1]["points"] == _KITE_PTS
    assert "optionGroup" not in tq.scene_spec

    scenes = _one(engine, KnowledgePoint).scenes
    assert scenes[0] == {
        "kind": "reflection",
        "figure": _figure("para", "平行四边形", _PARA_PTS, _PARA_EDGES),
        "curated": False,
    }
    # 已是新形的第二条：内容不得被改动。
    assert scenes[1]["figure"]["key"] == "para"

    cw = _one(engine, Courseware)
    scene = cw.sections[1]["scene"]
    # curated 从 optionGroup 提升到顶层；items → options 且**编排顺序严格保留**。
    assert scene["curated"] is True
    assert [o["label"] for o in scene["options"]] == ["风筝", "正方形"]
    assert [o["key"] for o in scene["options"]] == [_KITE_KEY, "square"]
    assert scene["figure"]["key"] == "square"
    assert "optionGroup" not in scene
    # 无场景的环节保持原样。
    assert cw.sections[0]["scene"] is None

    assert report.migrated == 4  # 题 / 任务题 / kp 旧场景 / 课件环节场景
    assert report.already_new == 1
    assert report.skipped == 0


# ── 幂等 ─────────────────────────────────────────────────────────────
def test_second_run_changes_nothing(engine):
    _run(engine, dry_run=False)
    before = (
        _one(engine, Question).scene_spec,
        _one(engine, TaskQuestion).scene_spec,
        _one(engine, KnowledgePoint).scenes,
        _one(engine, Courseware).sections,
    )

    report = _run(engine, dry_run=False)

    after = (
        _one(engine, Question).scene_spec,
        _one(engine, TaskQuestion).scene_spec,
        _one(engine, KnowledgePoint).scenes,
        _one(engine, Courseware).sections,
    )
    assert after == before
    # 第二次全部识别为新形：0 迁移、0 跳过。
    assert report.migrated == 0
    assert report.skipped == 0
    assert report.already_new == 5  # 上轮 4 个新形 + 原本就是新形的 1 个


# ── 干跑 ─────────────────────────────────────────────────────────────
def test_dry_run_reports_without_writing(engine):
    before = _one(engine, Question).scene_spec

    report = _run(engine, dry_run=True)

    after = _one(engine, Question).scene_spec
    assert after == before  # 库一字节没动
    assert "points" in after  # 仍是旧形
    assert report.dry_run is True
    assert report.migrated > 0  # 但报告说得出「会改什么」


def test_cli_defaults_to_dry_run_and_apply_writes(engine, tmp_path, capsys):
    db_path = tmp_path / "cli.db"
    shutil.copy(engine.url.database, db_path)
    cli_engine = create_engine(f"sqlite:///{db_path}")

    # 默认（无 --apply）：干跑，不落库。
    rc = migrate_scene_specs.main(["--db", str(db_path)])
    assert rc == 0
    out = capsys.readouterr().out
    assert "干跑" in out
    assert "points" in _one(cli_engine, Question).scene_spec

    # --apply：落库。
    rc = migrate_scene_specs.main(["--db", str(db_path), "--apply"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "已落库" in out
    spec = _one(cli_engine, Question).scene_spec
    assert spec["figure"]["key"] == "para"
    assert "points" not in spec


# ── 兜底图形不落库 ───────────────────────────────────────────────────
def test_unmatched_vertices_never_become_fallback_house(engine):
    with Session(engine) as s:
        q = s.exec(select(Question)).one()
        q.scene_spec = _legacy(_HOUSE_PTS, _HOUSE_EDGES)
        s.add(q)
        s.commit()

    _run(engine, dry_run=False)

    spec = _one(engine, Question).scene_spec
    # 房子顶点库里没有 → user_ 自绘键；顶点原样保留，不偷换成 house 身份。
    assert spec["figure"]["key"].startswith("user_")
    assert spec["figure"]["key"] != "house"
    assert spec["figure"]["points"] == _HOUSE_PTS
    assert spec["figure"]["label"] is None  # 没有展示名可凑，就不凑


def test_user_prefixed_key_is_stable_across_databases(engine, tmp_path):
    """同一份未命中几何在两个独立库上得到同一个 user_ 键（内容寻址 → 幂等的前提）。"""
    other = create_engine(f"sqlite:///{tmp_path / 'other.db'}")
    SQLModel.metadata.create_all(other)
    with Session(other) as s:
        s.add(
            _task_question(
                stem="风筝是轴对称图形吗？",
                scene_spec=_legacy(_KITE_PTS, _KITE_EDGES),
            )
        )
        s.commit()

    _run(engine, dry_run=False)
    _run(other, dry_run=False)

    spec = _one(other, TaskQuestion).scene_spec
    assert spec["figure"]["key"] == _KITE_KEY


def test_spec_without_geometry_is_skipped_not_fabricated(engine):
    """旧形但没有任何几何（如只剩 inputs 的模板壳）：跳过并留痕，不臆造图形。"""
    with Session(engine) as s:
        kp = s.exec(select(KnowledgePoint)).one()
        kp.scenes = [{"kind": "reflection", "inputs": {"axisAngle": 90}}]
        s.add(kp)
        s.commit()

    report = _run(engine, dry_run=False)

    assert _one(engine, KnowledgePoint).scenes == [
        {"kind": "reflection", "inputs": {"axisAngle": 90}}
    ]  # 原样不动
    assert report.skipped == 1
