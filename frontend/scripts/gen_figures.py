#!/usr/bin/env python3
"""从后端图形库生成前端 ``figures.dart``（ADR-0073 遗留 4：几何收口）。

**为什么是"生成"而不是"运行时拉取"**
顶点是**随包内置**的教学素材：整库画廊（``ReflectionFigureGallery``，ADR-0061 §V）
必须离线可用，而 tablet-first / 离线教室（ADR-0045）下不能指望首次渲染前先联网。
改成运行时拉取会把"画廊第一次打开是空的"变成常态，那是拿教学可用性换架构洁癖。

所以路径是：后端 ``scene_figures.py`` 是**唯一手写源** → 本脚本在**构建期**把它
翻译成 Dart 常量 → 前端仍是 ``const``、离线、零网络。手写副本从 2 份降到 1 份，
代价只是"改顶点后要跑一次脚本"，而这件事由 ``--check`` 兜住（忘了跑就红）。

用法::

    python3 frontend/scripts/gen_figures.py           # 生成（覆盖写）
    python3 frontend/scripts/gen_figures.py --check    # 只校验是否过期，退出码 1 = 过期

幂等：同一份后端数据永远产出同一份字节，重复跑不产生 diff（可安全接 CI）。
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
_TARGET = _REPO / "frontend" / "lib" / "shared" / "domain" / "figures.dart"

#: 后端把 FIGURES 序列化成 JSON 的小程序。走子进程而不是 import，是为了让本脚本
#: 不依赖 backend 的 venv/依赖——它只是个文本生成器，import 后端会把 CI 环境
#: 绑定到后端可导入，那是没必要的耦合。
#: ``note`` 是教学意图说明（"为什么 para 必须歪着"），刻意不在 ``to_dict()`` 里
#: ——它是给维护者看的，不是给渲染器消费的。但前端同样需要它：改顶点的人多半在
#: 前端看到图形才动手，所以随生成一并带过去。
_DUMP = """
import json
from app.features.materials.scene_figures import FIGURES
print(json.dumps(
    [{**f.to_dict(), "note": f.note} for f in FIGURES],
    ensure_ascii=False,
))
"""

_HEADER = '''// §轴对称教学图形顶点库（ADR-0061 §O / ADR-0073 遗留 4）。
//
// ⚠️ **本文件由 `frontend/scripts/gen_figures.py` 生成，请勿手改。**
// 唯一手写事实源是 `backend/app/features/materials/scene_figures.py`；
// 改顶点请改那里，然后重跑生成脚本（`--check` 会阻止你忘掉这一步）。
//
// 为什么顶点是**教学素材**而非算法产物：它们人工设计（para 刻意错切成不对称、
// arrow 走水平轴），此前硬编码在 `reflection_scene.dart` 的枚举里带来两个问题：
//   1. 渲染器（`ReflectionSceneWidget`）被迫「认识」房子/风筝这类概念——
//      而它本该只负责「给一组顶点，把多边形画出来并判定能否对折重合」；
//      2. 后端无法把「识别出的图形」变成可渲染的数据（它拿不到 Dart 里的顶点），
//         于是选项组（每个选项一个图形）无从生成。
//
// 纯数据（+ 一个 key 反查），无 import。坐标归一化到 0..1、y 向下（与画布一致）。
library;

/// 一个轴对称教学图形：归一化顶点 + 默认对称轴角度 + 全部对称轴角度。
class FigureShape {
  /// 图形标识（后端下发的稳定 key，不是给用户看的名字）。
  final String key;

  /// 图形中文名（仅用于界面标签与题面识别，不参与渲染判定）。
  final String label;

  /// 归一化顶点（x, y∈0..1，y 向下）。多边形按序连线。
  final List<({double x, double y})> vertices;

  /// 默认对称轴角度（度，0=水平、90=竖直）。
  ///
  /// 为何每图形不同：arrow 是横向的 → 0°；其余立着 → 90°。这让学生一打开
  /// 就落在「大概率正确」的初始轴上，调偏才有教学意义。
  final double defaultAxisAngle;

  /// **全部**对称轴的角度（度）。「有几条对称轴」这类题要数它（ADR-0061 §Q）。
  /// 空列表 = 该图形真的没有对称轴（如平行四边形）→ [axisCount] 为 0。
  final List<double> axisAngles;

  /// 对称轴条数——「正方形有几条对称轴」的答案就是这个数。
  ///
  /// **如实返回**（平行四边形 = 0），不做「至少 1」的兜底：这份数据的唯一用途
  /// 就是回答「有几条」，兜底会把「它没有对称轴」谎报成 1 条——那是**教错**。
  /// 渲染器要的「初始轴」另有 [defaultAxisAngle]，两者语义不同，别混。
  int get axisCount => axisAngles.length;

  const FigureShape({
    required this.key,
    required this.label,
    required this.vertices,
    required this.defaultAxisAngle,
    this.axisAngles = const [],
  });
}

/// 内置图形预设集。key 与后端 `scene_figures.py` 一一对应。
///
/// 顶点几何严格对齐已验证原型（`prototypes/reflection_demo.html`），迁移时**逐点
/// 照搬**、不重绘，确保视觉零回归。
const List<FigureShape> kFigureShapes = <FigureShape>['''

_FOOTER = """];

/// 按 key 取图形；未命中回落**第一个图形**（渲染层的「永不空」安全网）。
///
/// ⚠️ 这个兜底是**前端独有**的渲染关切，不要搬到后端去：后端 `figure_by_key`
/// 未命中返回 `None`（调用方据此降级为「不给图」），因为后端没有画布要填——
/// 若两边都兜底成 house，题面没点名图形时会凭空多出一栋房子，那是编造。
FigureShape figureByKey(String? key) => kFigureShapes.firstWhere(
      (f) => f.key == key,
      orElse: () => kFigureShapes.first,
    );
"""


def _num(value: float) -> str:
    """把浮点数写成 Dart 字面量，尽量贴近**手写时的视觉样式**。

    整数不带小数点（``90`` 而不是 ``90.0``——Dart 里 int literal 赋给 double
    字段是合法的，且读起来更像角度）；两位以内的小数补零对齐（``0.30`` 而不是
    ``0.3``，顶点列对齐才好看得出图形轮廓）；更长的保留原样（``0.347``）。
    数值完全等价，只是让生成结果的手写感不丢——这份文件是被人阅读的。
    """
    number = float(value)
    if number.is_integer():
        return str(int(number))
    if round(number, 2) == number:
        return f"{number:.2f}"
    return repr(number)


def _render(figures: list[dict]) -> str:
    out = [_HEADER]
    for item in figures:
        note = str(item.get("note") or "").strip()
        if note:
            # 折行位置由后端 note 自带的 ``\n`` 决定：机器按字符数硬切会把
            # 「45,135」切成「45,1 / 35」，比一整行长更难读。人在写 note 时
            # 顺手分行，成本为零，质量最高。
            for line in note.split("\n"):
                out.append(f"  // {line.strip()}")
        out.append(f"  FigureShape(\n    key: '{item['key']}',")
        out.append(f"    label: '{item['label']}',")
        out.append("    vertices: <({double x, double y})>[")
        for point in item["points"]:
            out.append(f"      (x: {_num(point[0])}, y: {_num(point[1])}),")
        out.append("    ],")
        out.append(f"    defaultAxisAngle: {_num(item['defaultAxisAngle'])},")
        angles = ", ".join(_num(a) for a in item["axisAngles"])
        out.append(f"    axisAngles: <double>[{angles}],")
        out.append("  ),")
    out.append(_FOOTER)
    return "\n".join(out)


def _load() -> list[dict]:
    import json
    import shutil

    # 优先走 `uv run`（后端依赖都在 uv 管理的 venv 里）；没有 uv 时才退回当前
    # 解释器——那时大概率 import 失败，但错误信息仍然指向"环境"而非"脚本 bug"。
    runner = (
        ["uv", "run", "python", "-c", _DUMP]
        if shutil.which("uv")
        else [sys.executable, "-c", _DUMP]
    )
    proc = subprocess.run(
        runner,
        cwd=_REPO / "backend",
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise SystemExit(
            "无法从后端导出图形库（backend 可导入吗？）\n" + proc.stderr.strip()
        )
    # 后端 stdout 里可能夹带日志/告警，只取最后一个 JSON 数组。
    matches = re.findall(r"\[.*\]", proc.stdout, re.DOTALL)
    if not matches:
        raise SystemExit(f"后端输出里没有找到 JSON 数组：{proc.stdout!r}")
    return json.loads(matches[-1])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="只校验生成结果是否最新（过期则退出码 1），不写文件",
    )
    args = parser.parse_args()

    expected = _render(_load())
    current = _TARGET.read_text(encoding="utf-8") if _TARGET.exists() else None
    if args.check:
        if current == expected:
            print(f"figures.dart 与后端图形库一致（{_TARGET}）")
            return 0
        print(
            "figures.dart 已过期：后端顶点改过但前端没重新生成。\n"
            f"请运行：python3 {Path(__file__).relative_to(_REPO)}"
        )
        return 1
    if current == expected:
        print("figures.dart 已是最新，未改动")
        return 0
    _TARGET.write_text(expected, encoding="utf-8")
    print(f"已生成 {_TARGET}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
