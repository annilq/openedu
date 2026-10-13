// §场景规格（ADR-0091）
//
// 此前前端**没有**这个类型：`scene_spec` 只是一张裸 `Map<String, dynamic>`，而解析
// 散落在 `ReflectionSceneData.fromSpec`（读顶层几何）与 `SceneOptionItem.fromJson`
// （读选项条目）两处——那正是「两套解析」的根源。现在形状只有一个、解析只有一处
// （[SceneSpec.tryParse]），形状变更能被静态发现，而不是线上静默画空。
//
// 一次演示 = `kind` 外壳 + 图形：
// - `kind` 是稳定契约，决定取哪个**交互外壳**（轴初值 / 控件 / 引导语归外壳，不进 spec）；
// - `figure` 是主图形；`options` 非空 → 渲染成图形画廊（点卡片弹对折演示）；
// - 两者皆空 → 空态（讲清「为什么空 + 下一步」，ADR-0051）。
//
// 几何只存在于 [FigureShape] 里（`vertices` / `edges`），快照自包含——改图库顶点不
// 影响已落库内容。`key` 只作身份 / 溯源 / 校验，**渲染不消费它**：不按 key 回查图库，
// 运行时零图库依赖（ADR-0083 决策 7 不动）。
library;

import 'figures.dart';

/// 一次演示的快照：`{kind, figure?, options?, curated}`。
class SceneSpec {
  /// 场景类型（前后端双登记的稳定契约，如 `reflection`）。
  final String kind;

  /// 主图形（演示对象）。null = 本份 spec 没有单场景几何。
  final FigureShape? figure;

  /// 选项 / 编排图形组。非空 → 渲染图形画廊（原有 `optionGroup.items`）。
  final List<FigureShape> options;

  /// 是否课件编排语境（决定图库卡片挂不挂选项角标）。
  final bool curated;

  const SceneSpec({
    required this.kind,
    this.figure,
    this.options = const <FigureShape>[],
    this.curated = false,
  });

  /// **唯一解析入口**：后端下发的 JSON → [SceneSpec]。
  ///
  /// 只认**新形**（`figure` / `options[]` 按 `Figure{key,label,points,edges}` 读）。
  /// 旧形（顶层 `points` / `edges`、`optionGroup`）一律**拒绝**：它读不到 `figure`
  /// 也读不到 `options`，得到的就是一份「没有几何」的 spec，由调用方走空态——
  /// **不做双读**（ADR-0091 决策 5），双读分支正是「两套形状」的持久化。
  ///
  /// null 只表示「这不是一份 spec」（不是 Map / 没有 kind）：那种情况连空态都不该
  /// 由解释器负责，调用方本就不渲染。
  static SceneSpec? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'];
    if (kind is! String || kind.isEmpty) return null;
    final rawOptions = raw['options'];
    final options = <FigureShape>[];
    if (rawOptions is List) {
      for (final e in rawOptions) {
        final f = _parseFigure(e);
        if (f != null) options.add(f);
      }
    }
    return SceneSpec(
      kind: kind,
      figure: _parseFigure(raw['figure']),
      options: options,
      curated: raw['curated'] == true,
    );
  }

  /// 回写形状（课件草稿 / 知识点保存）：与后端 `SceneSpec` 同形。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        if (figure != null) 'figure': _figureJson(figure!),
        if (options.isNotEmpty)
          'options': <Map<String, dynamic>>[
            for (final f in options) _figureJson(f),
          ],
        if (curated) 'curated': true,
      };

  /// `Figure`（后端 `app/domain/figures.py`）→ [FigureShape]。
  ///
  /// `key` 为空或顶点不足 3 个 → null（画不出多边形，也不该占一个身份）。
  static FigureShape? _parseFigure(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    if (key is! String || key.isEmpty) return null;
    final vertices = <({double x, double y})>[];
    final rawPoints = raw['points'];
    if (rawPoints is List) {
      for (final p in rawPoints) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          vertices.add(
            (x: (p[0] as num).toDouble(), y: (p[1] as num).toDouble()),
          );
        }
      }
    }
    if (vertices.length < 3) return null;
    final label = raw['label'];
    return FigureShape(
      key: key,
      // 展示名缺省回落到身份键：卡片至少要有一个可朗读的名，但不参与身份判定。
      label: (label is String && label.isNotEmpty) ? label : key,
      vertices: vertices,
      // 后端 Figure.edges 必填；缺了就按顶点顺序闭合（= 简单多边形默认连接）。
      edges: _parseEdges(raw['edges']) ?? closedEdges(vertices.length),
    );
  }

  static List<List<int>>? _parseEdges(Object? raw) {
    if (raw is! List || raw.isEmpty) return null;
    final out = <List<int>>[];
    for (final e in raw) {
      if (e is List && e.length >= 2 && e[0] is int && e[1] is int) {
        out.add(<int>[e[0] as int, e[1] as int]);
      }
    }
    return out.isEmpty ? null : out;
  }

  static Map<String, dynamic> _figureJson(FigureShape f) => <String, dynamic>{
        'key': f.key,
        'label': f.label,
        'points': <List<double>>[
          for (final v in f.vertices) <double>[v.x, v.y],
        ],
        'edges': f.edges ?? closedEdges(f.vertices.length),
      };
}
