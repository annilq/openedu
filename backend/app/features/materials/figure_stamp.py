"""图形目录投影 / 校验 / 盖章（ADR-0089 决策 3）。

出题与答疑**共用**的一套逻辑，只装三件事：

1. **目录投影** :func:`available_figures` —— 给定知识点，产出**本次可用的图形目录**。
   教师已配置的 ``kp.scenes`` 里的图形优先（curated），无配置时回落 ``figure_library``
   全量。目录条目是 :class:`FigureRef`（**只有 key + label**）——类型层面就保证
   「顶点进不了提示词」。
2. **校验** —— ``figure_key`` 必须落在目录内（调用方传 ``allowed`` 集合）。
3. **盖章** :func:`stamp_figures` / :func:`stamp_scene_spec` —— 合法身份键 → 从
   ``figure_library``（几何**唯一权威**）取顶点与连接关系，**内联**进图文对象。

纪律（与 :mod:`app.features.materials.scene_extract` 被删掉的猜测逻辑相对）：

- 顶点**永远**来自图库这一处权威，**不由调用方传入**，模型也绝不输出顶点。
- 本模块**不新增任何关联表或列**：``kp.scenes`` 本身就是知识点↔场景的关联，
  图库只是它的派生视图（ADR-0073：库是派生视图，**不是**来源，运行时**不回查**）。
- 只做投影 / 校验 / 盖章：拼装提示词与发射是 ticket 02/03 的事。

边界：``figure_stamp`` 属 ``features/materials``（场景域），被 ``features/tasks`` 与
``ai/subagents`` **单向**消费；``Figure`` 属 ``app.domain``（渲染契约），谁都能引。
"""
from __future__ import annotations

from sqlmodel import Session, SQLModel, select

from app.db.models import FigureLibrary, KnowledgePoint
from app.domain.figures import Figure
from app.domain.scene_spec import SceneSpec, normalize_scene_spec
from app.features.materials.scene_figures import figure_geometry
from app.features.materials.scene_fusion import resolve_kp_scene, scene_spec_from_figure

__all__ = [
    "FigureRef",
    "available_figures",
    "render_figure_catalog",
    "stamp_figures",
    "stamp_scene_spec",
]


class FigureRef(SQLModel):
    """给模型的目录条目：**只有 key + 中文名**。

    刻意**不是** :class:`~app.domain.figures.Figure`——类型层面就保证「顶点进不了
    提示词」（``Figure`` 带着几何，直接序列化进 prompt 就会漏；``FigureRef`` 里根本
    没有几何字段）。渲染层不消费它。
    """

    key: str
    label: str


def available_figures(
    session: Session, *, kp: KnowledgePoint | None = None
) -> list[FigureRef]:
    """本次可用的图形目录：``kp.scenes`` curated 图形优先 → 回落 ``figure_library`` 全量。

    - **curated 优先**：知识点模板里显式配的图形（主图形 + 选项图形）——教师的选择即
      权威，且**教师自绘图形与自编知识点都能进来**（旧词表只认内置图形，这是本次的
      能力增量）。
    - **回落全量**：知识点还没配模板时，用图库全量（内置 11 个 + 用户自绘）——保证
      「有图库就有目录」，不会因为「没配模板」而让 AI 完全无图可用。

    返回**非空目录**的判定：只要图库有种子行（部署后恒真）就非空；curated 与回落
    都取不到时才为空 list（调用方据此 L0 门控，见 ADR-0089 §4.2）。
    """
    curated = _curated_refs(kp)
    if curated:
        return curated
    return _library_refs(session)


def render_figure_catalog(figures: list[FigureRef]) -> str:
    """把目录渲染进提示词：**只给 key + 中文名**，一行一个（顶点绝不出现）。"""
    return "\n".join(f"{f.key} — {f.label}" for f in figures)


def stamp_figures(
    session: Session,
    figures: list[Figure | None],
    *,
    allowed: set[str],
) -> list[Figure] | None:
    """按 ``figure.key`` 从图库盖几何章：**全-or-无**，任一不合法即整组丢弃。

    规则（ADR-0089 决策 2 的校验层）：

    - **全-or-无**：一组里只要**有一个条目没有图**（``None``）→ 整组返回 ``None``。
      理由：半套图会把「这个选项本来没图」误导成「这个选项不是图形」。
    - 任一 ``key`` **不在目录内**（``allowed``）或**图库里没有这一行** → 返回 ``None``，
      且**不抛错**（未知键是模型幻觉，属正常输入）。
    - 全部合法 → 按图库几何盖章，**顺序等于传入顺序**。

    ``None`` 表示「这一组不给图」，由调用方整体退化（题面纯文字 / 不发射场景卡）。
    """
    if not figures:
        return None
    if any(f is None for f in figures):
        # 全-or-无：部分有图 → 整组丢弃（含「全都无图」）。
        return None
    stamped: list[Figure] = []
    for f in figures:
        assert f is not None  # 上面已挡；仅为类型收窄
        if f.key not in allowed:
            return None
        geometry = figure_geometry(session, f.key)
        if geometry is None:
            return None
        stamped.append(geometry)
    return stamped


def stamp_scene_spec(
    session: Session, figure_key: str | None, *, allowed: set[str]
) -> SceneSpec | None:
    """答疑侧盖章：``key`` → :class:`~app.domain.scene_spec.SceneSpec`（不合法返回 ``None``）。

    ``key`` 为空 / 不在目录内 / 图库无此行 → ``None``（调用方据此**不发射**场景卡）。
    ``kind`` 由盖章原语恒给 ``reflection``——它是稳定契约，不由模型输出。
    """
    if not figure_key or figure_key not in allowed:
        return None
    return scene_spec_from_figure(session, figure_key)


# ───────────────────────── 内部：目录投影 ─────────────────────────


def _curated_refs(kp: KnowledgePoint | None) -> list[FigureRef]:
    """从 ``kp.scenes``（经唯一读取入口）抽出显式配置的图形，去重保序。"""
    scenes = resolve_kp_scene(kp)
    if not scenes:
        return []
    refs: list[FigureRef] = []
    seen: set[str] = set()

    def _add(figure: Figure | None) -> None:
        if figure is None or not figure.key or figure.key in seen:
            return
        seen.add(figure.key)
        refs.append(FigureRef(key=figure.key, label=figure.label or figure.key))

    for raw in scenes:
        spec = normalize_scene_spec(raw)
        if spec is None:
            # 旧形 / 畸形模板：跳过（不做双读），不因此让整份目录为空。
            continue
        _add(spec.figure)
        for opt in spec.options or []:
            _add(opt)
    return refs


def _library_refs(session: Session) -> list[FigureRef]:
    """图库全量（内置 + 用户自绘），按 key 排序，作为无模板时的目录回落。"""
    rows = session.exec(
        select(FigureLibrary).order_by(FigureLibrary.key)
    ).all()
    return [FigureRef(key=r.key, label=r.label) for r in rows]
