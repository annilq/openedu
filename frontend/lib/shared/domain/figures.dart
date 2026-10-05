// §轴对称教学图形顶点库（ADR-0061 §O）—— **几何数据的单一事实源**。
//
// 为什么独立成文件：图形顶点是**教学素材**（人工设计，刻意让 para 不对称、
// 让 arrow 走水平轴），不是算法产物。此前它们硬编码在 `reflection_scene.dart` 的
// 枚举里，导致两个问题：
//   1. 渲染器（`ReflectionSceneWidget`）被迫「认识」房子/风筝这类概念——
//      而它本该只负责「给一组顶点，把多边形画出来并判定能否对折重合」；
//   2. 后端无法把「识别出的图形」变成可渲染的数据（它拿不到 Dart 里的顶点），
//      于是选项组（每个选项一个图形）无从生成。
//
// 纯数据、无逻辑、无 import。坐标归一化到 0..1、y 向下（与画布一致）。
// 后端镜像同一份数据见 `backend/app/features/materials/scene_figures.py`——
// **改任何一处顶点都必须同步另一处**（几何漂移会让「是否轴对称」的判定变错）。
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
const List<FigureShape> kFigureShapes = <FigureShape>[
  // 房子：五边形（底 + 两腰 + 屋顶），竖直对称。
  FigureShape(
    key: 'house',
    label: '房子',
    vertices: <({double x, double y})>[
      (x: 0.30, y: 0.70),
      (x: 0.70, y: 0.70),
      (x: 0.70, y: 0.45),
      (x: 0.50, y: 0.25),
      (x: 0.30, y: 0.45),
    ],
    defaultAxisAngle: 90,
    axisAngles: <double>[90],
  ),
  // 风筝：菱形，竖直对称。
  FigureShape(
    key: 'kite',
    label: '风筝',
    vertices: <({double x, double y})>[
      (x: 0.50, y: 0.20),
      (x: 0.72, y: 0.50),
      (x: 0.50, y: 0.80),
      (x: 0.28, y: 0.50),
    ],
    defaultAxisAngle: 90,
    axisAngles: <double>[90],
  ),
  // 箭头：横向（**故意水平对称**）→ 默认轴 0°。
  FigureShape(
    key: 'arrow',
    label: '箭头',
    vertices: <({double x, double y})>[
      (x: 0.20, y: 0.42),
      (x: 0.62, y: 0.42),
      (x: 0.62, y: 0.30),
      (x: 0.82, y: 0.50),
      (x: 0.62, y: 0.70),
      (x: 0.62, y: 0.58),
      (x: 0.20, y: 0.58),
    ],
    defaultAxisAngle: 0,
    // 横向箭头：唯一那条轴是水平线（竖直方向上下不对称）。
    axisAngles: <double>[0],
  ),
  // 平行四边形：**刻意画成不对称**（错切：上边中点 0.50 / 下边 0.62），
  // 用来演示「不是轴对称图形」。若被「修正」成矩形，这道题就失去判断意义
  // ——所以它的顶点不可动，且 axisAngles 为空（真的没有对称轴）。
  FigureShape(
    key: 'para',
    label: '平行四边形',
    vertices: <({double x, double y})>[
      (x: 0.30, y: 0.40),
      (x: 0.70, y: 0.40),
      (x: 0.82, y: 0.70),
      (x: 0.42, y: 0.70),
    ],
    defaultAxisAngle: 90,
    axisAngles: <double>[],
  ),
  // 正方形：**程序生成**（ADR-0061 §Q 决策 A：轴对齐、零微扰）。
  // 为什么它可以程序生成而 para 不行：正方形的几何定义**唯一且无歧义**，
  // 任何实现都必然得到一个 4 条对称轴的图形；而 para 的「不对称」是
  // **教学设计的意图**，算法只会把它"修好"。
  // 4 条轴：竖(90) / 横(0) / 两条对角(45,135)——「有几条对称轴」的答案就是 4。
  FigureShape(
    key: 'square',
    label: '正方形',
    vertices: <({double x, double y})>[
      (x: 0.28, y: 0.28),
      (x: 0.72, y: 0.28),
      (x: 0.72, y: 0.72),
      (x: 0.28, y: 0.72),
    ],
    defaultAxisAngle: 90,
    axisAngles: <double>[90, 0, 45, 135],
  ),
  // 等腰三角形：apex 朝上、底边水平 → 仅一条竖直对称轴（1 条轴）。
  FigureShape(
    key: 'iso_triangle',
    label: '等腰三角形',
    vertices: <({double x, double y})>[
      (x: 0.50, y: 0.22),
      (x: 0.26, y: 0.78),
      (x: 0.74, y: 0.78),
    ],
    defaultAxisAngle: 90,
    axisAngles: <double>[90],
  ),
  // 等边三角形：apex 朝上、底边水平；3 条对称轴（竖直 + 两条 ±60° 的腰中线）。
  FigureShape(
    key: 'eq_triangle',
    label: '等边三角形',
    vertices: <({double x, double y})>[
      (x: 0.50, y: 0.347),
      (x: 0.25, y: 0.78),
      (x: 0.75, y: 0.78),
    ],
    defaultAxisAngle: 90,
    axisAngles: <double>[90, 30, 150],
  ),
  // 矩形（长方形）：水平 + 竖直两条对称轴 → 2 条轴。
  FigureShape(
    key: 'rectangle',
    label: '矩形',
    vertices: <({double x, double y})>[
      (x: 0.22, y: 0.35),
      (x: 0.78, y: 0.35),
      (x: 0.78, y: 0.65),
      (x: 0.22, y: 0.65),
    ],
    defaultAxisAngle: 90,
    axisAngles: <double>[90, 0],
  ),
  // 等腰梯形：上下边都居中于 x=0.5 → 仅一条竖直对称轴（1 条轴）。
  FigureShape(
    key: 'iso_trapezoid',
    label: '等腰梯形',
    vertices: <({double x, double y})>[
      (x: 0.38, y: 0.40),
      (x: 0.62, y: 0.40),
      (x: 0.82, y: 0.72),
      (x: 0.18, y: 0.72),
    ],
    defaultAxisAngle: 90,
    axisAngles: <double>[90],
  ),
  // 任意梯形（非等腰）：上下边中点错开 → 真无对称轴（0 条轴），作干扰项。
  FigureShape(
    key: 'trapezoid_gen',
    label: '任意梯形',
    vertices: <({double x, double y})>[
      (x: 0.30, y: 0.40),
      (x: 0.62, y: 0.40),
      (x: 0.86, y: 0.72),
      (x: 0.20, y: 0.72),
    ],
    defaultAxisAngle: 90,
    axisAngles: <double>[],
  ),
  // 一般四边形：刻意不规则，真无对称轴（0 条轴），作干扰项。
  FigureShape(
    key: 'quad_gen',
    label: '一般四边形',
    vertices: <({double x, double y})>[
      (x: 0.25, y: 0.30),
      (x: 0.80, y: 0.40),
      (x: 0.70, y: 0.74),
      (x: 0.30, y: 0.66),
    ],
    defaultAxisAngle: 90,
    axisAngles: <double>[],
  ),
];

/// 按 key 取图形；未命中回落房子（与旧 `fromName` 行为一致，避免空场景）。
FigureShape figureByKey(String? key) => kFigureShapes.firstWhere(
      (f) => f.key == key,
      orElse: () => kFigureShapes.first,
    );
