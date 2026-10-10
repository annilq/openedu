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
/// 展开成**图形画廊**——每个选项一张卡，点一个弹对折演示对话框，儿童逐个亲手旋转 /
/// 平移对称轴去验证，而不是看程序报答案。
class SceneInterpreter extends StatelessWidget {
  final String kind;
  final Map<String, dynamic> spec;

  /// 画布下方**是否显示对称轴滑块**（仅 `kind == reflection` 生效）。
  ///
  /// 这是**展示关切**，不是 SceneSpec 字段——ADR-0083 决策 5 已把 `editable` 从新
  /// spec 删除，并明确「是否允许儿童拖轴」由调用方在构造时决定。故需要静态缩略图的
  /// 调用方（场景库详情页预览）直接传 `false`，**不再往 spec 里塞已废的 `editable`**。
  ///
  /// null = 沿用 spec 推断（新形 spec 无此键 → 显示；**存量旧快照**的 `editable`
  /// 仍被适配层采信，观感不变，见 [ReflectionSceneData.fromSpec]）。
  ///
  /// **只作用于单场景路径**：`optionGroup` 走图形画廊，交互发生在点开的弹窗里
  /// （那里必须能拖轴），故该路径不消费本开关。
  final bool? showAxisControls;

  const SceneInterpreter({
    super.key,
    required this.kind,
    required this.spec,
    this.showAxisControls,
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
        final data = ReflectionSceneData.fromSpec(spec);
        final override = showAxisControls;
        return ReflectionSceneWidget(
          data: override == null ? data : data.copyWith(showAxisControls: override),
        );
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
///
/// 与后端 `extract_option_group` 同形状（`label` / `caption` / `points` / `edges`）：
/// 几何**内联**在条目里，渲染时不再回查图库（ADR-0083 决策 6/7）。
class SceneOptionItem {
  /// 选项标号（「A」「B」…），仅用于界面定位，不参与判定。
  final String label;

  /// 图形中文名（卡片副标题，如「房子」）。课件语境没有 A/B/C，卡片就靠它区分。
  final String? caption;

  /// 该选项的顶点（归一化）。null = 该项没有可渲染几何，应被过滤掉。
  final List<Offset>? points;

  /// 该选项的顶点连接关系（顶点索引对）。null/空 = 按顶点顺序闭合。
  final List<List<int>>? edges;

  const SceneOptionItem({
    required this.label,
    this.caption,
    this.points,
    this.edges,
  });

  factory SceneOptionItem.fromJson(Map<String, dynamic> json) => SceneOptionItem(
        label: (json['label'] as String?) ?? '',
        caption: json['caption'] as String?,
        points: ReflectionSceneData.parsePoints(json['points']),
        edges: ReflectionSceneData.parseEdges(json['edges']),
      );
}

/// 选项组：图形画廊 + 点开进对折演示（ADR-0061 §V，取代 §O 的「N 个场景平铺」）。
///
/// **为什么不把每个选项各渲染一个完整场景平铺在页面上**（§O 旧做法）：
/// [ReflectionSceneWidget] 的画布是「边长 = 可用宽度」的正方形，一个场景竖直方向就要
/// 吃掉 画布 + 状态条 + 播放条 + 3 个轴滑块 ≈ 700px。4 个选项平铺 ≈ 2800px，儿童只能
/// 靠滚动逐个看，「对比着看」实际变成「记不住上一个长什么样」。
///
/// 现在：每个选项压成一张 ~124px 的卡片（本题选项带 A/B/C/D 角标），点一个弹
/// [ReflectionSceneDialog]——里面是同一个 [ReflectionSceneWidget]，交互一件不少。
/// 「先挑图形、再认真折」两步分开，正是对折这道题的操作顺序。
///
/// **零图库依赖**（ADR-0083 决策 7）：渲染只吃 spec 内联的 `points`/`edges`，
/// 不查图库、不缓存、不发起取数——旧实现在这里铺「整库」是靠前端常量（`kFigureShapes`），
/// 那正是本轮退役掉的双源。图库只在画板 / 画廊这类**创作 UI** 打开时按需拉取。
///
/// [curated] 为真（课件编排，ADR-0076 §2.2）时**不挂选项角标**——课件语境没有 A/B/C，
/// 挂上空角标纯噪声；两种语境下卡片顺序都严格等于 `items` 顺序（顺序就是编排意图）。
class SceneOptionGroup extends StatelessWidget {
  /// 原始 spec（提供该 kind 的几何与共享项）。
  final Map<String, dynamic> spec;
  final List<SceneOptionItem> items;

  /// 是否按课件编排渲染（当前只影响「挂不挂选项角标」，见类文档）。
  ///
  /// **必须是显式开关**：题库 / 错题路径的 items 恰好也非空（它们就是选项），靠
  /// 「有没有条目」区分两种语境会静默改变学生的观感。
  final bool curated;

  const SceneOptionGroup({
    super.key,
    required this.spec,
    required this.items,
    this.curated = false,
  });

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    if (entries.isEmpty) {
      return const AppEmptyState(
        icon: LucideIcons.circleHelp,
        title: '暂无可演示的选项',
        message: '这道题没有可图形化的选项，请先用文字讲解。',
      );
    }
    final base = ReflectionSceneData.fromSpec(spec);
    // 选项标号（「A」…）挂到对应卡片上。curated 语境没有 A/B/C，故一律不挂（否则
    // 每张卡挂一个空角标）。
    final labels = curated
        ? const <String, String>{}
        : <String, String>{
            for (final e in entries)
              if (e.optionLabel.isNotEmpty) e.figure.key: e.optionLabel,
          };
    return ReflectionFigureGallery(
      figures: <FigureShape>[for (final e in entries) e.figure],
      optionLabels: labels,
      // 条目顺序就是意图（题库的 A/B/C/D 序、课件的编排序），一律不重排。
      preserveOrder: true,
      hint: '点一个图形打开对折演示：拖对称轴、点播放，看到 180° 时两侧能否完全重合。',
      onOpen: (figure) {
        final entry = entries.firstWhere((e) => e.figure.key == figure.key);
        ReflectionSceneDialog.show(
          context,
          data: base.copyWith(
            // 顶点 / 边优先用后端下发的（ADR-0061 §O：条目几何是权威）。
            points: entry.points,
            edges: entry.edges,
            figureLabel: figure.label,
            // 轴初值不按图形走：图库不存 axis 属性（ADR-0083 决策 2），初值统一归
            // kind 外壳——[base] 已带上它，这里刻意不覆盖。
          ),
          optionLabel: labels[figure.key],
        );
      },
    );
  }

  /// 条目 → 可直接渲染的图形 + 它的内联几何（**按 items 数组顺序**）。
  ///
  /// `key` 用图形名（caption / label）：条目**不带图库 key**（决策 6），而画廊要一个
  /// 稳定标识来挂角标、判高亮，图形名是条目里唯一的稳定身份。同名条目只认第一个
  /// ——重复的图形再挂一个角标没有教学意义。
  List<_OptionEntry> _entries() {
    final out = <_OptionEntry>[];
    final seen = <String>{};
    for (final item in items) {
      final points = item.points;
      if (points == null || points.length < 3) continue;
      final name = item.caption ?? item.label;
      if (name.isEmpty || !seen.add(name)) continue;
      out.add((
        figure: FigureShape(
          key: name,
          label: name,
          vertices: <({double x, double y})>[
            for (final p in points) (x: p.dx, y: p.dy),
          ],
        ),
        optionLabel: item.label,
        points: points,
        edges: item.edges,
      ));
    }
    return out;
  }
}

/// 一条已就绪的选项条目：图形 + 选项标号 + 它自己的内联几何。
///
/// 用记录类型而非 Map：Map 会丢掉条目的数组顺序，而**顺序就是编排意图**
/// （题库的 A/B/C/D 序、课件教师编排的序）。
typedef _OptionEntry = ({
  FigureShape figure,
  String optionLabel,
  List<Offset> points,
  List<List<int>>? edges,
});
