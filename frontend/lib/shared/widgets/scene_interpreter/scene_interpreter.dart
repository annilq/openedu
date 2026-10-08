import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:flutter/widgets.dart';

import '../../domain/figures.dart';
import '../app_empty_state.dart';
import 'reflection_figure_gallery.dart';
import 'reflection_scene.dart';
import 'reflection_scene_data.dart';
import 'reflection_scene_dialog.dart';

// =====================================================================
// §场景解释器（ADR-0061 决策 7 / 8）
//
// 三处消费方（出题解析卡 / 错题本 / AI 伴学讲解卡）统一经此入口渲染交互讲解，
// 复用同一套渲染器。kind 词汇表前后端双登记：新增 kind 必须在此 + 后端 _KIND 同步。
// =====================================================================

/// 场景类型（前后端双登记，ADR-0061 决策 7）。
enum SceneKind { reflection, unknown }

extension SceneKindX on SceneKind {
  static SceneKind fromName(String? name) {
    switch (name) {
      case 'reflection':
        return SceneKind.reflection;
      default:
        return SceneKind.unknown;
    }
  }
}

/// 场景解释器：按 [kind] 将 SceneSpec（原始 JSON）分发到对应渲染器。
///
/// 未识别的 kind 走降级空态（ADR-0051：空态讲清「为什么空 + 下一步」）。
///
/// **选项组优先**（ADR-0061 §O / §V）：spec 带 `optionGroup` 时不渲染单个场景，而是
/// 展开成**图形画廊**——平面图形库全部铺成网格，点一个图形弹对折演示对话框，儿童
/// 逐个亲手旋转/平移对称轴去验证，而不是看程序报答案。
class SceneInterpreter extends StatelessWidget {
  final String kind;
  final Map<String, dynamic> spec;

  const SceneInterpreter({
    super.key,
    required this.kind,
    required this.spec,
  });

  @override
  Widget build(BuildContext context) {
    final group = spec['optionGroup'];
    if (group is Map && group['items'] is List && (group['items'] as List).isNotEmpty) {
      return SceneOptionGroup(
        spec: spec,
        // 就地读取显式开关（ADR-0076 §2.2）：不给解释器加构造参数——它被多处调用，
        // 加参会波及全部消费方。
        curated: group['curated'] == true,
        items: (group['items'] as List)
            .whereType<Map>()
            .map((e) => SceneOptionItem.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.points != null)
            .toList(growable: false),
      );
    }
    switch (SceneKindX.fromName(kind)) {
      case SceneKind.reflection:
        return ReflectionSceneWidget(data: ReflectionSceneData.fromSpec(spec));
      case SceneKind.unknown:
        return const AppEmptyState(
          icon: LucideIcons.circleHelp,
          title: '暂不支持的交互讲解',
          message: '当前版本未实现该类型的交互演示，可先用文字讲解。',
        );
    }
  }
}

/// 一个选项对应的场景实例（ADR-0061 §O）。
class SceneOptionItem {
  /// 选项标号（「A」「B」…），仅用于界面定位，不参与判定。
  final String label;

  /// 图形中文名（副标题，如「房子」）。
  final String? caption;

  /// 该选项的顶点（归一化）。null = 该项没有可渲染几何，应被过滤掉。
  final List<Offset>? points;

  /// 该图形的默认对称轴角度（度）。
  final double? defaultAxisAngle;

  const SceneOptionItem({
    required this.label,
    this.caption,
    this.points,
    this.defaultAxisAngle,
  });

  factory SceneOptionItem.fromJson(Map<String, dynamic> json) => SceneOptionItem(
        label: (json['label'] as String?) ?? '',
        caption: json['caption'] as String?,
        points: ReflectionSceneData.parsePoints(json['points']),
        defaultAxisAngle: (json['defaultAxisAngle'] as num?)?.toDouble(),
      );
}

/// 选项组：图形画廊 + 点开进对折演示（ADR-0061 §V，取代 §O 的「N 个场景平铺」）。
///
/// **为什么不把每个选项各渲染一个完整场景平铺在页面上**（§O 旧做法）：
/// [ReflectionSceneWidget] 的画布是「边长 = 可用宽度」的正方形，一个场景竖直方向就要
/// 吃掉 画布 + 状态条 + 播放条 + 3 个轴滑块 ≈ 700px。4 个选项平铺 ≈ 2800px，儿童只能
/// 靠滚动逐个看，「对比着看」实际变成「记不住上一个长什么样」。
///
/// 现在：图形库全部平面图形铺成网格（本题选项带 A/B/C/D 角标、排在最前），点一个
/// 弹 [ReflectionSceneDialog]——里面是同一个 [ReflectionSceneWidget]，交互一件不少。
/// 「先挑图形、再认真折」两步分开，正是对折这道题的操作顺序。
///
/// [curated] 为真（课件编排，ADR-0076 §2.2）时改为**只渲染条目指定的那几张、并按
/// 条目顺序**——教师挑哪几个、按什么排，本身就是教学意图。
class SceneOptionGroup extends StatelessWidget {
  /// 原始 spec（提供轴默认值、controls、narrative 等共享项）。
  final Map<String, dynamic> spec;
  final List<SceneOptionItem> items;

  /// 是否按 [items] 裁剪并保序（教师编排）。缺省 false = 整库铺开。
  ///
  /// **必须是显式开关**：题库 / 错题路径的 items 恰好也非空（它们就是选项），靠
  /// 「有没有条目」区分两种语境会静默剥夺学生探索其余图形的能力。
  final bool curated;

  const SceneOptionGroup({
    super.key,
    required this.spec,
    required this.items,
    this.curated = false,
  });

  @override
  Widget build(BuildContext context) {
    final matched = _matchFigures();
    if (items.isEmpty || (curated && matched.isEmpty)) {
      return const AppEmptyState(
        icon: LucideIcons.circleHelp,
        title: '暂无可演示的选项',
        message: '这道题没有可图形化的选项，请先用文字讲解。',
      );
    }
    final base = ReflectionSceneData.fromSpec(spec);
    final pointsOf = <String, List<Offset>>{
      for (final m in matched) m.figure.key: m.points,
    };
    // curated 语境没有 A/B/C，故不传角标（否则每张卡挂一个空角标）。
    final labels = curated
        ? const <String, String>{}
        : <String, String>{for (final m in matched) m.figure.key: m.label};
    return ReflectionFigureGallery(
      // 整库铺开（儿童可自由探索任意图形），本题选项靠角标认出来；curated 时换成
      // 条目解析出的子集，交给画廊时置上保序——顺序就是编排意图。
      figures: curated
          ? matched.map((m) => m.figure).toList(growable: false)
          : kFigureShapes,
      optionLabels: labels,
      preserveOrder: curated,
      hint: '点一个图形打开对折演示：拖对称轴、点播放，看到 180° 时两侧能否完全重合。',
      onOpen: (figure) => ReflectionSceneDialog.show(
        context,
        data: base.copyWith(
          // 顶点优先用后端下发的（ADR-0061 §O：顶点是权威）；图形库只是兜底。
          points: pointsOf[figure.key] ??
              figure.vertices.map((v) => Offset(v.x, v.y)).toList(growable: false),
          figureLabel: figure.label,
          // 轴初始值用**该图形自己的**默认轴，不用模板的（否则箭头停在竖轴、
          // 一开始就不重合，儿童会以为题目错了）。
          axisAngle: figure.defaultAxisAngle,
        ),
        optionLabel: labels[figure.key],
      ),
    );
  }

  /// 条目 → 图形库的命中结果，**按 items 数组顺序**（重排会抹掉编排意图）。
  ///
  /// 先按图形名配（ caption 就是图形中文名），配不上再逐点比对顶点——两者都来自
  /// 同一份镜像数据，正常必然命中；配不上说明后端下发了库外图形：整库语境下当普通
  /// 库内图形打开（画廊本来就是整库，不会因此少一个可探索的图形），curated 语境下
  /// 跳过、不留空卡。
  List<_MatchedFigure> _matchFigures() {
    final out = <_MatchedFigure>[];
    final seen = <String>{};
    for (final item in items) {
      final points = item.points;
      if (points == null || points.length < 3) continue;
      final figure = _matchFigure(item, points);
      if (figure == null || !seen.add(figure.key)) continue;
      out.add(_MatchedFigure(figure: figure, label: item.label, points: points));
    }
    return out;
  }

  static FigureShape? _matchFigure(SceneOptionItem item, List<Offset> points) {
    final caption = item.caption;
    if (caption != null) {
      for (final f in kFigureShapes) {
        if (f.label == caption) return f;
      }
    }
    for (final f in kFigureShapes) {
      if (f.vertices.length != points.length) continue;
      var same = true;
      for (var i = 0; i < points.length; i++) {
        if ((f.vertices[i].x - points[i].dx).abs() > 1e-6 ||
            (f.vertices[i].y - points[i].dy).abs() > 1e-6) {
          same = false;
          break;
        }
      }
      if (same) return f;
    }
    return null;
  }
}

/// 一个条目命中的库内图形：图形本身 + 选项标号 + 条目自带的顶点。
///
/// 用记录类型而非 Map：Map 会丢掉条目的数组顺序，而 curated 语境下**顺序就是编排
/// 意图**（ADR-0076 §2.2）。
class _MatchedFigure {
  final FigureShape figure;
  final String label;
  final List<Offset> points;

  const _MatchedFigure({
    required this.figure,
    required this.label,
    required this.points,
  });
}
