import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show LucideIcons, ShadDialog, showShadDialog;

import '../../domain/figures.dart';
import '../../theme/app_theme.dart';
import '../app_actions.dart';
import '../app_buttons.dart';
import '../app_empty_state.dart';
import '../app_inputs.dart';
import '../app_toast.dart';
import 'reflection_figure_gallery.dart';
import 'reflection_scene.dart';
import 'reflection_scene_data.dart';

// =====================================================================
// §图形画板（ADR-0083 决策 3/8）
//
// 教师的创作入口：把图形**亲手画出来**（拖顶点）、放入工具栏预设、起名、存进图库。
// 与播放共用同一个 `ReflectionSceneWidget`（决策 8：同一渲染器 = 播放器 = 画板），
// 差别只在 `editing: true`——画布可拖、顶点带手柄、且**不报「是不是轴对称」的结论**
// （决策 2：判定交给眼睛；作者也不该照着结论去微调顶点）。
//
// 分层：本文件在 `shared/` 下，**不得 import `features/`**（main→features→shared 单向）。
// 故保存走调用方注入的 [FigureBoardSave] 回调——真实调用点用
// `MaterialRepository.createFigure` 接线，测试可注入假实现直接断言「保存了什么」。
// =====================================================================

/// 画板保存回调：`(名称, 归一化顶点, 顶点索引对)` → 后端分配的 key。
typedef FigureBoardSave = Future<String> Function(
  String label,
  List<List<double>> points,
  List<List<int>> edges,
);

/// 图形画板：工具栏预设 + 编辑态画布 + 起名 + 保存入库。
class ReflectionSceneBoard extends StatefulWidget {
  /// 保存回调（见文件头分层说明）。
  final FigureBoardSave onSave;

  /// 工具栏预设（由调用方注入：图库只在创作 UI 打开时按需拉取，ADR-0083 决策 7）。
  ///
  /// **没有默认值**：图库几何已不在前端常量里，「预设有哪些」只有取数方知道。
  final List<FigureShape> presets;

  /// 关闭出口（页面态经 HomeScreen 单一 `_go(back)` 回落，ADR-0059）。null = 不显示关闭。
  final VoidCallback? onBack;

  /// 标题（页面态 / 弹窗态调用方可覆盖）。
  final String title;

  const ReflectionSceneBoard({
    super.key,
    required this.onSave,
    required this.presets,
    this.onBack,
    this.title = '图形画板',
  });

  @override
  State<ReflectionSceneBoard> createState() => _ReflectionSceneBoardState();
}

class _ReflectionSceneBoardState extends State<ReflectionSceneBoard> {
  final TextEditingController _label = TextEditingController();

  /// 画板上的顶点（归一化 0..1）。空 = 还没放图形。
  List<Offset> _points = const <Offset>[];

  /// 顶点连接关系；与 [_points] 同步（拖顶点不改索引，故连接不变）。
  List<List<int>> _edges = const <List<int>>[];

  /// 当前放上画板的是哪个预设（画廊高亮用）；null = 手工画的 / 还没放。
  String? _placedKey;

  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  bool get _hasShape => _points.length >= 3;

  /// 点工具栏预设 → 该预设**整体落到画板**（顶点 + 按序闭合的边）。
  ///
  /// 只落几何、不带任何轴属性（ADR-0083 决策 2/3）：预设里本来也没有「对称轴」这回事，
  /// 「是不是轴对称、有几条」由作者拖轴翻转自己看。
  void _placePreset(FigureShape figure) {
    final pts = figure.vertices
        .map((v) => Offset(v.x, v.y))
        .toList(growable: false);
    setState(() {
      _points = pts;
      _edges = closedEdges(pts.length);
      _placedKey = figure.key;
      // 名字留空时用图形名预填，但不覆盖作者已经打好的名字。
      if (_label.text.trim().isEmpty) _label.text = figure.label;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final label = _label.text.trim();
    if (label.isEmpty) {
      AppToast.show(context, '请先给图形起个名字');
      return;
    }
    if (!_hasShape) {
      AppToast.show(context, '请先在工具栏点一个图形放入画板');
      return;
    }
    setState(() => _saving = true);
    try {
      final key = await widget.onSave(
        label,
        <List<double>>[
          for (final p in _points) <double>[p.dx, p.dy],
        ],
        _edges,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, '已保存到图库（$key）');
      widget.onBack?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, '保存失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(widget.title, style: text.titleMedium)),
              if (widget.onBack != null)
                AppIconAction(
                  icon: Icons.close,
                  iconSize: 18,
                  semanticLabel: '关闭画板',
                  onPressed: widget.onBack!,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs2),
          Text(
            '拖顶点改形状、拖空白处移动对称轴，点播放看对折。'
            '下方工具栏点一个图形即可放入画板；保存后它进入图库，可被复用。',
            style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_hasShape)
            ReflectionSceneWidget(
              // 画板 = 渲染器的编辑态（决策 8）。轴参数 / 控件走 ReflectionSceneData
              // 默认值（轴 90°、居中、可播放可拖进度）；不传 narrative——画板不该
              // 出现讲给学生听的那段引导话术。
              data: ReflectionSceneData(points: _points, edges: _edges),
              editing: true,
              onPointsChanged: (pts) => setState(() => _points = pts),
            )
          else
            const AppEmptyState(
              icon: LucideIcons.component,
              title: '画板是空的',
              message: '在下方工具栏点一个图形放入画板，再拖顶点微调；也可以直接保存一个自定义图形。',
            ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: '图形名称',
            controller: _label,
            hintText: '例如：我的图形',
            enabled: !_saving,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppPrimaryButton(
            label: '保存到图库',
            loading: _saving,
            onPressed: _hasShape && !_saving ? _save : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('工具栏（点一个图形放入画板）', style: text.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          ReflectionFigureGallery(
            figures: widget.presets,
            optionLabels: const <String, String>{},
            selectedKey: _placedKey,
            hint: '预设只提供顶点，不带「是不是轴对称」的答案——判定交给眼睛。',
            showPlayBadge: false,
            onOpen: _placePreset,
          ),
        ],
      ),
    );
  }
}

/// 以弹窗形式打开画板（与 [ReflectionSceneDialog] 同一 ShadDialog 口径）。
///
/// 为什么要钉宽：画板里的画布是「边长 = 可用宽度」的正方形，弹窗给多宽它就多高；
/// 不钉的话大屏上画布会顶掉整屏。钉到 [maxBoardWidth]，竖直方向交给 ShadDialog
/// 自带的 scrollable 兜住（任何屏高都不会 RenderFlex 溢出）。
class ReflectionSceneBoardDialog {
  ReflectionSceneBoardDialog._();

  /// 画板宽度上限（≈ 对折演示弹窗的画布上限，顶点还数得清）。
  static const double maxBoardWidth = 460;

  static Future<void> show(
    BuildContext context, {
    required FigureBoardSave onSave,
    required List<FigureShape> presets,
  }) {
    final app = AppTheme.colorsOf(context);
    return showShadDialog<void>(
      context: context,
      barrierColor: app.scrim,
      builder: (ctx) => ShadDialog(
        // 标题与关闭动作都交给画板自己的头部（画板自带 header + 关闭按钮），
        // 这里不再重复一个标题 / 一个右上角 X。
        closeIcon: const SizedBox.shrink(),
        constraints: const BoxConstraints(maxWidth: maxBoardWidth + 48),
        child: SizedBox(
          width: maxBoardWidth,
          child: ReflectionSceneBoard(
            onSave: onSave,
            // 工具栏预设由调用方注入（ADR-0083 决策 7：图库在打开创作 UI 时按需拉取，
            // 取数属 feature 关切）——画板本身不认识 provider，保持哑组件。
            presets: presets,
            onBack: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
    );
  }
}
