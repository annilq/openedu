import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import '../../../../shared/domain/figures.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_focusable_action.dart';

/// 「演示哪几个图形、按什么顺序」（ADR-0076 §2.1 / §2.2 · ticket 04）。
///
/// 教师在本环节已关联的**轴对称**场景上勾选一组内置图形，结果写进
/// `scene['optionGroup']`；讲课页的解释器据此摆出多张图（`curated` 只渲染条目指定
/// 的那几张、按条目顺序）。
///
/// 为什么是独立文件：`courseware_section_edit_dialog.dart` 已 371 行，只剩 29 行
/// 余量（ADR-0058 §1 的 400 行棘轮）。
///
/// **只写副本**：[scene] 是本环节的草稿（教师「关联知识点场景」时快照复制进来的
/// 那一份），改完后整份经 [onChanged] 交回；本组件从不持有、也绝不回写知识点上的
/// 场景（ADR-0073 红线）。
class SectionSceneFiguresPicker extends StatefulWidget {
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
  State<SectionSceneFiguresPicker> createState() =>
      _SectionSceneFiguresPickerState();
}

class _SectionSceneFiguresPickerState
    extends State<SectionSceneFiguresPicker> {
  /// 已勾选的图形，**顺序 = 勾选 / 拖动后的顺序**（不是库序）。
  ///
  /// 为什么它是本地状态而不是每次从 [SectionSceneFiguresPicker.scene] 读回来：
  /// 数量闸门（<2 张删键）意味着「只勾了 1 张」这个中间态**根本不写进场景**——
  /// 若以场景为准，教师勾第一张时界面不会有任何反应（勾选被自己写的闸门吃掉了）。
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
    _picked = _shapesFromScene(widget.scene);
    _emitted = _keysFromScene(widget.scene);
  }

  @override
  void didUpdateWidget(covariant SectionSceneFiguresPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fromScene = _keysFromScene(widget.scene);
    if (!_sameKeys(fromScene, _emitted)) {
      setState(() {
        _picked = _shapesFromScene(widget.scene);
        _emitted = fromScene;
      });
    }
  }

  /// 场景里已编排的图形（按 items 数组顺序）。
  ///
  /// 库外 key（后端下发了前端图形库没有的图形）跳过：渲染层按 caption 命中库内
  /// 图形，留一张渲染不出来的空卡会让「勾了几张」与课堂看到的张数对不上。
  List<FigureShape> _shapesFromScene(Map<String, dynamic> scene) {
    final keys = _keysFromScene(scene);
    return <FigureShape>[
      for (final key in keys)
        for (final f in kFigureShapes)
          if (f.key == key) f,
    ];
  }

  static List<String> _keysFromScene(Map<String, dynamic> scene) {
    final group = scene['optionGroup'];
    if (group is! Map) return const <String>[];
    final items = group['items'];
    if (items is! List) return const <String>[];
    final out = <String>[];
    for (final e in items) {
      if (e is! Map) continue;
      final key = e['figureKey'] as String?;
      // 同一图形重复出现只认第一次（顺序即编排，重复没有教学意义）。
      if (key == null || out.contains(key)) continue;
      out.add(key);
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
        // 靠条目有无区分两种语境会剥夺学生的整库探索。
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

  /// 与后端 `extract_option_group` 同形状，保证 `SceneOptionItem.fromJson` 直读。
  static Map<String, dynamic> _item(FigureShape f) => <String, dynamic>{
        // 课件语境没有 A/B/C 选项 → 标号留空；caption 用中文名（渲染层按它命中图形）。
        'label': '',
        'caption': f.label,
        'figureKey': f.key,
        // 顶点**保存时展开**（§4 红线 2）：不能只存 key 让渲染层运行时回查——
        // 课堂演示不能依赖一次查询，走廊网络不该成为「图形出不来」的理由。
        'points': <List<double>>[
          for (final v in f.vertices) <double>[v.x, v.y],
        ],
        'defaultAxisAngle': f.defaultAxisAngle,
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
            for (final f in kFigureShapes) _tile(context, f),
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

  /// 图形卡：选中态沿用画廊那套**强调色描边**语言（淡强调底 + 强调色边）。
  Widget _tile(BuildContext context, FigureShape figure) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final at = _picked.indexWhere((f) => f.key == figure.key);
    final picked = at >= 0;
    return AppFocusableAction(
      onTap: () => _toggle(figure),
      hoverHighlight: true,
      semanticLabel: picked
          ? '已勾选${figure.label}，当前第 ${at + 1} 个（再点一次取消）'
          : '勾选${figure.label}加入演示',
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        width: 92,
        decoration: BoxDecoration(
          color: picked ? app.accent.withValues(alpha: 0.10) : app.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: picked ? app.accent : AppBrutal.ink,
            width: AppElevation.borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 92,
              height: 76,
              child: CustomPaint(painter: _FigureOutlinePainter(figure)),
            ),
            Container(
              height: AppElevation.borderWidthHairline,
              color: AppBrutal.ink,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  if (picked) ...[
                    Icon(LucideIcons.check, size: 12, color: app.accent),
                    const SizedBox(width: AppSpacing.xs2),
                  ],
                  Expanded(
                    child: Text(
                      figure.label,
                      style: text.labelSmall?.copyWith(color: app.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

/// 选择卡上的图形缩略图：只描边，**不画对称轴、不作任何判定**——「能不能对折重合」
/// 只能由学生在演示弹窗里亲手折出来（ADR-0061 §O 只画不判）。
class _FigureOutlinePainter extends CustomPainter {
  const _FigureOutlinePainter(this.figure);

  final FigureShape figure;

  @override
  void paint(Canvas canvas, Size size) {
    if (figure.vertices.length < 3) return;
    final inset = AppSpacing.sm;
    final w = size.width - inset * 2;
    final h = size.height - inset * 2;
    final path = Path();
    for (var i = 0; i < figure.vertices.length; i++) {
      final v = figure.vertices[i];
      final p = Offset(inset + v.x * w, inset + v.y * h);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppBrutal.ink
        ..strokeWidth = AppElevation.borderWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FigureOutlinePainter oldDelegate) =>
      oldDelegate.figure != figure;
}
