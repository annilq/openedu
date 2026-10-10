import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import '../../../../shared/domain/figures.dart';
import '../../../../shared/domain/providers/figure_library_provider.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/scene_interpreter/reflection_scene_data.dart';
import '../widgets/scene_figure_tile.dart';

/// 「演示哪几个图形、按什么顺序」（ADR-0076 §2.1 / §2.2 · ticket 04）。
///
/// 教师在本环节已关联的**轴对称**场景上勾选一组图形，结果写进
/// `scene['optionGroup']`；讲课页的解释器据此摆出多张图（条目顺序 = 讲解顺序）。
///
/// 图形清单来自图库、**打开时按需拉取**（ADR-0083 决策 7）：内置预设与用户在画板上
/// 自建的图形同表，故这里能挑到自己画的图形。这也意味着本组件是**创作 UI**，
/// 允许依赖 `figureLibraryProvider`（运行时渲染路径如 `SceneOptionGroup` 一律不许）。
///
/// 为什么是独立文件：`courseware_section_edit_dialog.dart` 已 371 行，只剩 29 行
/// 余量（ADR-0058 §1 的 400 行棘轮）。
///
/// **只写副本**：[scene] 是本环节的草稿（教师「关联知识点场景」时快照复制进来的
/// 那一份），改完后整份经 [onChanged] 交回；本组件从不持有、也绝不回写知识点上的
/// 场景（ADR-0073 红线）。
class SectionSceneFiguresPicker extends ConsumerWidget {
  const SectionSceneFiguresPicker({
    super.key,
    required this.scene,
    required this.onChanged,
  });

  /// 本环节的场景草稿。只动 `optionGroup` 这一个键，其余字段原样带回。
  final Map<String, dynamic> scene;

  /// 改写后的整份场景（调用方直接 `copyWith(scene: …)` 落到草稿上）。
  final void Function(Map<String, dynamic> scene) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(figureLibraryProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: Text('正在读取图形库…')),
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('图形库读取失败', style: AppTheme.textOf(context).titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '挑图形需要连接服务读取图形库。请检查网络后重试（$e）',
            style: AppTheme.textOf(context)
                .bodySmall
                ?.copyWith(color: AppTheme.colorsOf(context).onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextAction(
            label: '重试',
            onPressed: () => ref.invalidate(figureLibraryProvider),
          ),
        ],
      ),
      // 图库到货后才立内部状态：勾选态的播种要靠图库把 spec 里的**内联顶点**
      // 反查回库内图形（条目不带图库 key，ADR-0083 决策 6）。
      data: (library) => _Picker(
        scene: scene,
        library: library,
        onChanged: onChanged,
      ),
    );
  }
}

class _Picker extends StatefulWidget {
  const _Picker({
    required this.scene,
    required this.library,
    required this.onChanged,
  });

  final Map<String, dynamic> scene;
  final List<FigureShape> library;
  final void Function(Map<String, dynamic> scene) onChanged;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  /// 已勾选的图形，**顺序 = 勾选 / 拖动后的顺序**（不是库序）。
  ///
  /// 为什么它是本地状态而不是每次从 [widget.scene] 读回来：数量闸门（<2 张删键）
  /// 意味着「只勾了 1 张」这个中间态**根本不写进场景**——若以场景为准，教师勾第一张
  /// 时界面不会有任何反应（勾选被自己写的闸门吃掉了）。
  late List<FigureShape> _picked;

  /// 最近一次写进场景的条目 key（<2 张时是空表——那时键被删了）。
  ///
  /// 用来分辨「场景变了」是谁造成的：与它一致 = 我们自己刚写出去的回声，不能拿
  /// 空表把本地草稿冲掉；不一致 = 外部换了场景（教师改关联了另一份模板），以场
  /// 景为准重播种。
  late List<String> _emitted;

  @override
  void initState() {
    super.initState();
    _picked = _shapesFromScene(widget.scene, widget.library);
    _emitted = <String>[for (final f in _picked) f.key];
  }

  @override
  void didUpdateWidget(covariant _Picker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fromScene = _shapesFromScene(widget.scene, widget.library);
    final keys = <String>[for (final f in fromScene) f.key];
    if (!_sameKeys(keys, _emitted)) {
      setState(() {
        _picked = fromScene;
        _emitted = keys;
      });
    }
  }

  /// 场景里已编排的图形（按 items 数组顺序）。
  ///
  /// 条目只带**内联几何**（ADR-0083 决策 6：spec 不引用图库 key），所以这里拿顶点
  /// 逐点反查图库找回身份。图库里找不到（教师挑完后又把那张图删了 / 顶点被改过）
  /// 就跳过：留一张渲染不出来、也点不掉的空卡，比少一张更让人困惑。
  static List<FigureShape> _shapesFromScene(
    Map<String, dynamic> scene,
    List<FigureShape> library,
  ) {
    final group = scene['optionGroup'];
    if (group is! Map) return const <FigureShape>[];
    final items = group['items'];
    if (items is! List) return const <FigureShape>[];
    final out = <FigureShape>[];
    final seen = <String>{};
    for (final e in items) {
      if (e is! Map) continue;
      final points = ReflectionSceneData.parsePoints(e['points']);
      if (points == null) continue;
      final shape = figureMatchingVertices(library, points);
      if (shape == null || !seen.add(shape.key)) continue;
      out.add(shape);
    }
    return out;
  }

  static bool _sameKeys(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 勾选 / 取消勾选：**追加到末尾**，故勾选顺序天然就是条目顺序。
  void _toggle(FigureShape figure) {
    final next = <FigureShape>[..._picked];
    final at = next.indexWhere((f) => f.key == figure.key);
    if (at >= 0) {
      next.removeAt(at);
    } else {
      next.add(figure);
    }
    _commit(next);
  }

  void _move(int index, int delta) {
    final next = <FigureShape>[..._picked];
    final moved = next.removeAt(index);
    next.insert(index + delta, moved);
    _commit(next);
  }

  /// 落到场景草稿上（ADR-0076 §2.3 数量闸门）：**<2 张就删掉 `optionGroup` 这个
  /// 键**（不是把 scene 清空），让讲课页回落到「按 spec 渲染单场景」；≥2 张才写。
  ///
  /// 只勾 1 张也走单场景路径——那张图本就是场景自带的，多包一层画廊只是多一次点击。
  void _commit(List<FigureShape> next) {
    final updated = Map<String, dynamic>.from(widget.scene);
    if (next.length < 2) {
      updated.remove('optionGroup');
    } else {
      updated['optionGroup'] = <String, dynamic>{
        // 必须是**显式开关**（§2.2）：题库 / 错题路径的 items 也非空（它们是选项），
        // 靠条目有无区分两种语境会改变学生的观感。
        'curated': true,
        'items': <Map<String, dynamic>>[
          for (final f in next) _item(f),
        ],
      };
    }
    setState(() {
      _picked = next;
      _emitted = next.length < 2
          ? const <String>[]
          : <String>[for (final f in next) f.key];
    });
    widget.onChanged(updated);
  }

  /// 与后端 `extract_option_group` **同形状**，保证 `SceneOptionItem.fromJson` 直读。
  ///
  /// 只写几何（`points` + `edges`），不写图库 `key`、不写任何 axis 属性（ADR-0083
  /// 决策 6：SceneSpec 内联几何、不引用 key；决策 2：图库不存 axis）。
  static Map<String, dynamic> _item(FigureShape f) => <String, dynamic>{
        // 课件语境没有 A/B/C 选项 → 标号留空；caption 用中文名（卡片副标题）。
        'label': '',
        'caption': f.label,
        // 顶点 + 边**保存时展开**（§4 红线 2）：不能只存 key 让渲染层运行时回查——
        // 课堂演示不能依赖一次查询，走廊网络不该成为「图形出不来」的理由。
        'points': <List<double>>[
          for (final v in f.vertices) <double>[v.x, v.y],
        ],
        'edges': closedEdges(f.vertices.length),
      };

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('演示哪几个图形、按什么顺序', style: text.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '勾选 2 张以上，讲课页会把它们按下面的顺序摆成一组，学生逐个打开对折演示。',
          style: text.bodySmall?.copyWith(
            color: AppTheme.colorsOf(context).onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final f in widget.library)
              SceneFigureTile(
                figure: f,
                order: _orderOf(f),
                onTap: () => _toggle(f),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_picked.isEmpty)
          // ADR-0051：回答「为什么空」+「下一步做什么」，不写「暂无数据」。
          const AppEmptyState.inline(
            icon: LucideIcons.layoutGrid,
            title: '还没挑图形',
            message: '当前只演示场景自带的那一张。在上方勾选至少 2 个图形，'
                '讲课页才会把它们摆成一组。',
            steps: <String>['勾选 ≥2 个图形', '用上移 / 下移排出讲解顺序'],
          )
        else ...[
          for (var i = 0; i < _picked.length; i++)
            _orderRow(context, i, _picked[i]),
          if (_picked.length < 2)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '只勾了 1 张：按单场景演示（场景自带的图形）。再勾 1 张才会摆成一组。',
                style: text.bodySmall?.copyWith(
                  color: AppTheme.colorsOf(context).onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// 该图形已勾选时的序号（1 起）；未勾选返回 null。
  int? _orderOf(FigureShape figure) {
    final at = _picked.indexWhere((f) => f.key == figure.key);
    return at >= 0 ? at + 1 : null;
  }

  /// 已选行：序号 + 上移 / 下移 / 移除（序号就是讲课页的演示顺序）。
  Widget _orderRow(BuildContext context, int index, FigureShape figure) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${index + 1}. ${figure.label}',
              style: text.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AppTextAction(
            label: '上移',
            onPressed: index > 0 ? () => _move(index, -1) : null,
            semanticLabel: '把${figure.label}上移',
          ),
          AppTextAction(
            label: '下移',
            onPressed: index < _picked.length - 1 ? () => _move(index, 1) : null,
            semanticLabel: '把${figure.label}下移',
          ),
          AppTextAction(
            label: '移除',
            color: app.error,
            onPressed: () => _toggle(figure),
            semanticLabel: '从演示中移除${figure.label}',
          ),
        ],
      ),
    );
  }
}
