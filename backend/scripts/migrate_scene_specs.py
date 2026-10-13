#!/usr/bin/env python3
"""存量 SceneSpec 快照一次性迁移（ADR-0091 §5 / ticket 05）。

把四处存量快照从**旧形**改写成**新形**（ADR-0091：几何唯一载体 = ``Figure``）：
``question.scene_spec`` / ``taskquestion.scene_spec``（题目与任务题快照列）、
``knowledgepoint.scenes[]``（知识点场景配置）、``courseware.sections[].scene``
（课件环节内嵌场景，编排顺序严格保留）。

改写规则：旧形顶层 ``points``/``edges`` → 包成 ``figure{key,label,points,edges}``；
``optionGroup.items[]`` → ``options[]``（条目顺序 = 编排顺序，一律不重排）；
``optionGroup.curated`` → 顶层 ``curated``；``derivedFrom`` / ``inputs`` 等旧键
**丢弃**（交互参数归 kind 外壳，ADR-0083 决策 5）。

身份键（旧快照本来没有 key）：按顶点反查 ``figure_library`` 表（前端
``figureMatchingVertices`` 的服务端等价物：逐点比对、容差 1e-6、忽略 edges、
按 key 序取首个命中）拿图库 key；查不到 → 生成 ``user_<hash>`` 自绘前缀键
（对 ``points``+``edges`` 内容寻址，跨库稳定——这是幂等的前提）。
**不拿展示名凑键、不兜底成渲染期的房子**（``kFallbackFigure`` 只在画布上兜底，
不参与落库）。

纪律：**幂等**（新形原样跳过、``user_`` 键重跑不换键）；**默认干跑**（不加
``--apply`` 只出报告不写库，``--check`` 是显式干跑）；**一次性改写、不做双读**
（迁移后代码只认新形，:func:`normalize_scene_spec` 拒绝旧形）；迁移产物过不了
:func:`normalize_scene_spec` 自检的**不落库**、留痕跳过——绝不写半份几何。

用法::

    cd backend
    python scripts/migrate_scene_specs.py                  # 干跑（默认不写）
    python scripts/migrate_scene_specs.py --check          # 同上，显式干跑
    python scripts/migrate_scene_specs.py --apply          # 落库
    python scripts/migrate_scene_specs.py --db path/to/app.db --apply
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# 让脚本从 backend/ 启动时能 import app（与 ingest_textbooks.py 同款）。
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import inspect  # noqa: E402
from sqlmodel import Session, create_engine, select  # noqa: E402

from app.db.models import (  # noqa: E402
    Courseware,
    FigureLibrary,
    KnowledgePoint,
    Question,
    TaskQuestion,
)
from app.domain.scene_spec import normalize_scene_spec  # noqa: E402

# 旧形键：出现任意一个即判旧形。与 ``app.domain.scene_spec._LEGACY_KEYS`` 同源
# （那边是私有名，这里显式复述；改动须同步）。``inputs`` 也在内——交互参数归
# kind 外壳（ADR-0083 决策 5），旧键必须丢，否则读路径校验入口拒绝整份 spec。
_LEGACY_KEYS = frozenset({"points", "edges", "optionGroup", "derivedFrom", "inputs"})

# 顶点逐点比对容差（归一化 0..1；与前端 kVertexEpsilon 一致）。
_VERTEX_EPSILON = 1e-6

# 自绘键前缀（与 ``_allocate_user_figure_key`` 的 user_ 前缀一致）。
_USER_KEY_PREFIX = "user_"

# spec 四态：无场景（None/空，不计入扫描）/ 已是新形 / 旧形待改写 / 跳过（畸形或无几何）。
_STATUS_ABSENT = "absent"
_STATUS_NEW = "new"
_STATUS_MIGRATED = "migrated"
_STATUS_SKIPPED = "skipped"


@dataclass
class Report:
    """迁移摘要：计数 + 逐行留痕（跳过的原因要能定位到行）。"""

    dry_run: bool
    scanned: int = 0
    migrated: int = 0
    already_new: int = 0
    skipped: int = 0
    absent: int = 0  # 无场景（None / 空 dict）：本来就没东西，不算问题
    figures_keyed: int = 0  # 顶点反查命中图库的图形数
    figures_fallback: int = 0  # 反查落空、生成 user_ 键的图形数
    details: list[str] = field(default_factory=list)

    def note(self, where: str, reason: str) -> None:
        self.skipped += 1
        self.details.append(f"[跳过] {where}: {reason}")


# ── 身份键：顶点反查 / 自绘兜底 ────────────────────────────────────────
def _fallback_key(points: Any, edges: Any) -> str:
    """未命中图库 → ``user_<hash>``：对 points+edges 内容寻址（稳定 → 幂等）。"""
    normalized = {
        "points": [[float(x), float(y)] for x, y in points],
        "edges": [[int(i), int(j)] for i, j in edges],
    }
    payload = json.dumps(normalized, separators=(",", ":"), sort_keys=True)
    return _USER_KEY_PREFIX + hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


def _match_library(library: list[FigureLibrary], points: list) -> FigureLibrary | None:
    """按顶点反查图库（前端 ``figureMatchingVertices`` 的服务端等价物）。

    只比顶点、忽略 edges、按 key 序取首个命中（图库列表同序，确定性）。库里没有
    返回 ``None``——调用方走自绘键，不臆造名字、不兜底成任何内置图形。
    """
    for row in library:
        row_points = row.points or []
        if len(row_points) != len(points):
            continue
        if all(
            abs(a - b) <= _VERTEX_EPSILON and abs(c - d) <= _VERTEX_EPSILON
            for (a, c), (b, d) in zip(row_points, points)
        ):
            return row
    return None


def _figure(
    points: Any, edges: Any, label: str | None, library: list[FigureLibrary]
) -> dict[str, Any] | None:
    """旧几何（裸 points/edges，或选项条目）→ 新 ``Figure`` dict。

    顶点/边**原样深拷贝保留**（快照不可变：迁移不重绘任何几何）；只补身份键与
    展示名。geometry 畸形（无法过校验）返回 ``None``，由调用方跳过整行。
    """
    if not isinstance(points, list) or not isinstance(edges, list):
        return None
    match = _match_library(library, points)
    if match is not None:
        key, name = match.key, match.label
    else:
        key, name = _fallback_key(points, edges), label
    return {
        "key": key,
        "label": name,
        "points": copy.deepcopy(points),
        "edges": copy.deepcopy(edges),
    }


def _figure_from_item(item: Any, library: list[FigureLibrary]) -> dict[str, Any] | None:
    """旧选项条目（``{label,caption,points,edges}``）→ 新 ``Figure``。

    展示名取 ``caption``（图形中文名；命中图库时以图库 label 为权威）；
    旧 ``label``（A/B 标号）不进新形——前端按索引推标号，spec 只存图形。
    无几何的条目返回 ``None``（渲染期本就过滤空卡，迁移不保留）。
    """
    if not isinstance(item, dict):
        return None
    caption = item.get("caption")
    return _figure(
        item.get("points"),
        item.get("edges"),
        caption if isinstance(caption, str) and caption else None,
        library,
    )


# ── spec 级改写 ────────────────────────────────────────────────────────
def _rewrite(spec: dict, library: list[FigureLibrary]) -> tuple[str, dict | None]:
    """旧形 spec → 新形 spec。返回 ``(状态, 新形或 None)``。"""
    kind = spec.get("kind")
    if not isinstance(kind, str) or not kind.strip():
        return _STATUS_SKIPPED, None

    figure: dict | None = None
    if spec.get("points") is not None or spec.get("edges") is not None:
        figure = _figure(spec.get("points"), spec.get("edges"), None, library)
        if figure is None:
            return _STATUS_SKIPPED, None

    options: list[dict] | None = None
    curated = False
    group = spec.get("optionGroup")
    if isinstance(group, dict):
        curated = bool(group.get("curated", False))
        items = group.get("items")
        if isinstance(items, list) and items:
            options = []
            for item in items:
                entry = _figure_from_item(item, library)
                if entry is None:  # 条目几何残缺：整份跳过，不丢编排顺序
                    return _STATUS_SKIPPED, None
                options.append(entry)

    # 除旧键外原样保留（kind 及其余字段）；几何重组进 figure/options。
    new: dict[str, Any] = {
        k: copy.deepcopy(v) for k, v in spec.items() if k not in _LEGACY_KEYS
    }
    if figure is not None:
        new["figure"] = figure
    if options:
        new["options"] = options
    new["curated"] = curated

    # 自检门：过不了读路径校验的产物不落库（半份几何比旧形更糟）。
    if normalize_scene_spec(new) is None:
        return _STATUS_SKIPPED, None
    return _STATUS_MIGRATED, new


def _migrate_spec(
    spec: Any, library: list[FigureLibrary]
) -> tuple[str, dict | None]:
    """分类 + 改写。无场景 / 已新形 → 不动；旧形 → 改写或跳过。"""
    if spec is None or spec == {}:
        return _STATUS_ABSENT, None
    if not isinstance(spec, dict):
        return _STATUS_SKIPPED, None
    if _LEGACY_KEYS.intersection(spec):
        return _rewrite(spec, library)
    if normalize_scene_spec(spec) is not None:
        return _STATUS_NEW, None
    return _STATUS_SKIPPED, None


def _tally(report: Report, status: str, new: dict | None, where: str) -> None:
    """把单个 spec 的结果记进报告（身份键来源按产物统计）。"""
    if status == _STATUS_ABSENT:
        report.absent += 1
        return
    report.scanned += 1
    if status == _STATUS_NEW:
        report.already_new += 1
        return
    if status == _STATUS_SKIPPED:
        report.note(where, "不可迁移（无几何 / 畸形 / 非 dict），原样保留")
        return
    report.migrated += 1
    for fig in [new.get("figure")] + list(new.get("options") or []):
        if fig is None:
            continue
        if fig["key"].startswith(_USER_KEY_PREFIX):
            report.figures_fallback += 1
        else:
            report.figures_keyed += 1


# ── 四处存储 ───────────────────────────────────────────────────────────
def _migrate_column(
    session: Session,
    model: Any,
    column: str,
    library: list[FigureLibrary],
    report: Report,
    *,
    dry_run: bool,
) -> None:
    """单列 spec（question / taskquestion 的 scene_spec）。"""
    label = f"{model.__name__}.{column}"
    for row in session.exec(select(model)).all():
        status, new = _migrate_spec(getattr(row, column), library)
        _tally(report, status, new, f"{label}#{row.id}")
        if status == _STATUS_MIGRATED and not dry_run:
            setattr(row, column, new)
            session.add(row)


def _migrate_scenes(
    session: Session, library: list[FigureLibrary], report: Report, *, dry_run: bool
) -> None:
    """知识点 scenes（list[spec]）：逐条迁移，已是新形 / 跳过的原样保留。

    ⚠️ 必须**新建 list** 再整体赋值：JSON 列原地变异后重赋同一个对象不会被
    ORM 识别（flush 序列化旧值，实测静默不落库）。
    """
    for kp in session.exec(select(KnowledgePoint)).all():
        scenes = kp.scenes
        if not isinstance(scenes, list):
            continue
        new_scenes = list(scenes)
        changed = False
        for idx, spec in enumerate(new_scenes):
            status, new = _migrate_spec(spec, library)
            _tally(report, status, new, f"KnowledgePoint.scenes[{idx}]#{kp.id}")
            if status == _STATUS_MIGRATED:
                new_scenes[idx] = new
                changed = True
        if changed and not dry_run:
            kp.scenes = new_scenes  # 新对象，ORM 才会标脏
            session.add(kp)


def _migrate_sections(
    session: Session, library: list[FigureLibrary], report: Report, *, dry_run: bool
) -> None:
    """课件 sections[].scene：环节顺序不动，只替换内嵌 scene 的值。

    同样新建 list 与 section dict（见 :func:`_migrate_scenes` 的 JSON 列注意）；
    除 ``scene`` 外环节字段原样深拷贝，编排顺序天然保留。
    """
    for cw in session.exec(select(Courseware)).all():
        sections = cw.sections
        if not isinstance(sections, list):
            continue
        new_sections = list(sections)
        changed = False
        for idx, section in enumerate(new_sections):
            if not isinstance(section, dict) or "scene" not in section:
                continue
            status, new = _migrate_spec(section["scene"], library)
            _tally(report, status, new, f"Courseware.sections[{idx}].scene#{cw.id}")
            if status == _STATUS_MIGRATED:
                new_sections[idx] = {**section, "scene": new}
                changed = True
        if changed and not dry_run:
            cw.sections = new_sections  # 新对象，ORM 才会标脏
            session.add(cw)


def migrate_session(session: Session, *, dry_run: bool = True) -> Report:
    """迁移一个会话可见的全部存量快照。返回摘要（干跑时不写任何库）。"""
    report = Report(dry_run=dry_run)
    engine = session.get_bind()
    inspector = inspect(engine)
    library = (
        session.exec(select(FigureLibrary).order_by(FigureLibrary.key)).all()
        if inspector.has_table("figure_library")
        else []
    )
    for model, column in ((Question, "scene_spec"), (TaskQuestion, "scene_spec")):
        if inspector.has_table(model.__tablename__):
            _migrate_column(session, model, column, library, report, dry_run=dry_run)
    if inspector.has_table(KnowledgePoint.__tablename__):
        _migrate_scenes(session, library, report, dry_run=dry_run)
    if inspector.has_table(Courseware.__tablename__):
        _migrate_sections(session, library, report, dry_run=dry_run)
    if not dry_run:
        session.commit()
    return report


def _print_report(report: Report) -> None:
    mode = "干跑（未写库；--apply 才落库）" if report.dry_run else "已落库"
    print(f"SceneSpec 存量迁移[{mode}]")
    print(
        f"  扫描 {report.scanned} 份 spec：迁移 {report.migrated}，"
        f"已是新形 {report.already_new}，跳过 {report.skipped}，"
        f"无场景 {report.absent}"
    )
    print(
        f"  身份键：图库反查命中 {report.figures_keyed}，"
        f"自绘键(user_) {report.figures_fallback}"
    )
    for line in report.details:
        print(f"  {line}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="存量 SceneSpec 快照一次性迁移（ADR-0091 §5）：旧形 → 新形，幂等，默认干跑。",
    )
    parser.add_argument(
        "--db",
        default=None,
        help="SQLite 库路径（默认取 app.core.db 的 DATABASE_URL，即 backend/.env 配置）",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="显式干跑（默认行为）：只出报告不写库",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="真落库（默认不写；干跑与 --apply 互斥）",
    )
    args = parser.parse_args(argv)
    if args.apply and args.check:
        parser.error("--check 与 --apply 互斥：一个只读报告、一个真写库")

    if args.db:
        engine = create_engine(f"sqlite:///{args.db}")
    else:  # 延迟 import：--db 模式不依赖 .env / settings
        from app.core.db import engine  # noqa: PLC0415

    with Session(engine) as session:
        report = migrate_session(session, dry_run=not args.apply)
    _print_report(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
