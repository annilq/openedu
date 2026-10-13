import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:flutter/widgets.dart';

import '../../domain/figures.dart';
import '../../domain/scene_spec.dart';
import '../../utils/option_text.dart' show cleanOptionText;
import '../app_empty_state.dart';
import 'reflection_figure_gallery.dart';
import 'reflection_scene.dart';
import 'reflection_scene_data.dart';
import 'reflection_scene_dialog.dart';

// =====================================================================
// §场景解释器（ADR-0061 决策 7 / 8 · ADR-0091）
//
// 三处消费方（出题解析卡 / 错题本 / AI 伴学讲解卡）统一经此入口渲染交互讲解，
// 复用同一套渲染器。kind 词汇表前后端双登记：新增 kind 必须在此 + 后端 _KIND 同步。
//
// ADR-0091 起 spec 是**类型**（[SceneSpec]）而不是裸 Map：几何只存在于
// `figure` / `options[]` 里（`Figure{key,label,points,edges}`），解析只有
// [SceneSpec.tryParse] 一处。渲染只吃顶点与连接关系，**不消费身份键**
// ——`key` 只用于身份 / 溯源 / 校验（画廊角标、高亮、去重）。
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

/// 场景解释器：按 [SceneSpec.kind] 将场景规格分发到对应渲染器。
///
/// 未识别的 kind 走降级空态（ADR-0051：空态讲清「为什么空 + 下一步」）。
///
/// **选项组优先**（ADR-0061 §O / §V）：spec 带 `options` 时不渲染单个场景，而是
/// 展开成**图形画廊**——每个选项一张卡，点一个弹对折演示对话框，儿童逐个亲手旋转 /
/// 平移对称轴去验证，而不是看程序报答案。
class SceneInterpreter extends StatelessWidget {
  /// 一次演示的快照（类型化契约，ADR-0091）：kind + 图形。
  final SceneSpec spec;

  /// 画布下方**是否显示对称轴滑块**（仅 `kind == reflection` 的单场景路径生效）。
  ///
  /// 这是**展示关切**，不是 SceneSpec 字段——ADR-0083 决策 5 已把 `editable` 从新
  /// spec 删除，并明确「是否允许儿童拖轴」由调用方在构造时决定。故需要静态缩略图的
  /// 调用方（场景库详情页预览）直接传 `false`，**不再往 spec 里塞已废的 `editable`**。
  ///
  /// null = 显示（新形 spec 不带该开关；ADR-0091 后连旧形 `editable` 也不再被读取
  /// ——轴初值与控件一律归 kind 外壳 / 本开关）。
  ///
  /// **只作用于单场景路径**：`options` 走图形画廊，交互发生在点开的弹窗里
  /// （那里必须能拖轴），故该路径不消费本开关。
  final bool? showAxisControls;

  const SceneInterpreter({
    super.key,
    required this.spec,
    this.showAxisControls,
  });

  @override
  Widget build(BuildContext context) {
    if (spec.options.isNotEmpty) {
      return SceneOptionGroup(spec: spec);
    }
    switch (SceneKindX.fromName(spec.kind)) {
      case SceneKind.reflection:
        if (spec.figure == null) {
          // 几何只存在于 figure / options（ADR-0091）：两者皆空（含被拒绝的旧形
          // 快照）→ 空态讲清「为什么空 + 下一步」，**不臆造几何**（ADR-0051）。
          return const AppEmptyState(
            icon: LucideIcons.circleHelp,
            title: '这个场景还没有配置图形',
            message: '演示内容里没有可渲染的图形。请在编辑页重新选择图形，或先用文字讲解。',
          );
        }
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
/// **身份由 `Figure.key` 承担**（ADR-0091 决策 2，修掉的身份缺陷）：此前条目不带
/// 图库身份键，画廊只能拿**展示名**当身份——教师改一次图形名，角标映射与高亮就断；
/// 同名图形还会被静默合并。现在角标映射 / 高亮 / 去重全部按 `key`，展示名回归显示。
///
/// **零图库依赖**（ADR-0083 决策 7）：渲染只吃 spec 内联的 `points`/`edges`，
/// 不查图库、不缓存、不发起取数。图库只在画板 / 画廊这类**创作 UI** 打开时按需拉取。
///
/// [SceneSpec.curated] 为真（课件编排，ADR-0076 §2.2）时**不挂选项角标**——课件语境
/// 没有 A/B/C，挂上空角标纯噪声；两种语境下卡片顺序都严格等于 `options` 顺序
/// （顺序就是编排意图）。
class SceneOptionGroup extends StatelessWidget {
  /// 本次演示的快照：`options` 是要摆开的图形，`curated` 决定挂不挂角标，
  /// `figure`（若有）给弹窗提供基础几何与 kind 外壳参数。
  final SceneSpec spec;

  const SceneOptionGroup({
    super.key,
    required this.spec,
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
    // 选项标号（「A」…）按**条目下标**推：新形 spec 只存图形（ADR-0091：旧条目里的
    // A/B 标号不进 Figure，与存量迁移脚本同口径）。curated 语境没有 A/B/C，
    // 故一律不挂（否则每张卡挂一个空角标）。
    final labels = spec.curated
        ? const <String, String>{}
        : <String, String>{
            for (var i = 0; i < entries.length; i++)
              entries[i].key: String.fromCharCode(65 + i),
          };
    return ReflectionFigureGallery(
      figures: entries,
      optionLabels: labels,
      // 条目顺序就是意图（题库的 A/B/C/D 序、课件的编排序），一律不重排。
      preserveOrder: true,
      hint: '点一个图形打开对折演示：拖对称轴、点播放，看到 180° 时两侧能否完全重合。',
      onOpen: (figure) {
        ReflectionSceneDialog.show(
          context,
          data: base.copyWith(
            // 顶点 / 边优先用后端下发的（ADR-0061 §O：条目几何是权威）。
            points: <Offset>[
              for (final v in figure.vertices) Offset(v.x, v.y),
            ],
            edges: figure.edges,
            figureLabel: cleanOptionText(figure.label),
            // 轴初值不按图形走：图库不存 axis 属性（ADR-0083 决策 2），初值统一归
            // kind 外壳——[base] 已带上它，这里刻意不覆盖。
          ),
          optionLabel: labels[figure.key],
        );
      },
    );
  }

  /// 可直接渲染的图形（**按 options 数组顺序**，几何不足 3 顶点的丢掉）。
  ///
  /// 去重按**身份键**（`Figure.key`），不按展示名：同一个图形挂两次角标没有教学
  /// 意义；而**同名不同键**（教师自绘的与内置的同名）是两个图形，按名去重会把
  /// 其中一个悄悄吃掉——那正是 ADR-0091 修掉的身份缺陷。
  List<FigureShape> _entries() {
    final out = <FigureShape>[];
    final seen = <String>{};
    for (final figure in spec.options) {
      if (figure.vertices.length < 3) continue;
      if (!seen.add(figure.key)) continue;
      out.add(figure);
    }
    return out;
  }
}
