import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import '../../../../shared/domain/figures.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_focusable_action.dart';

/// 课件挑图形的一张小卡（ADR-0076 §2.1 · 从 `section_scene_figures_picker` 抽出）。
///
/// 为什么独立成文件：那个选择器已顶到 ADR-0058 的 400 行棘轮，而「一张图形卡长什么样」
/// 与「勾了哪几张、什么顺序」是两件事——卡片是纯展示（+ 一个点击回调整），选择器只管状态。
///
/// 缩略图只描边，**不画对称轴、不作任何判定**：「能不能对折重合」只能由学生在演示弹窗
/// 里亲手折出来（ADR-0061 §O 只画不判）。
class SceneFigureTile extends StatelessWidget {
  const SceneFigureTile({
    super.key,
    required this.figure,
    required this.order,
    required this.onTap,
  });

  /// 这张卡代表的图形（几何 + 中文名）。
  final FigureShape figure;

  /// 已勾选时的**序号**（1 起，就是讲课页的演示顺序）；null = 未勾选。
  final int? order;

  /// 点按切换勾选。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final picked = order != null;
    return AppFocusableAction(
      onTap: onTap,
      hoverHighlight: true,
      semanticLabel: picked
          ? '已勾选${figure.label}，当前第 $order 个（再点一次取消）'
          : '勾选${figure.label}加入演示',
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        width: 92,
        decoration: BoxDecoration(
          // 选中态沿用画廊那套语言（淡强调底 + 强调色边）。
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
}

/// 卡片缩略图：只描边，不画轴、不判定（ADR-0061 §O）。
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
