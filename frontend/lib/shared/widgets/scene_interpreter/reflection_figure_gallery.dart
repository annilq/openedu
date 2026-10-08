import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import '../../domain/figures.dart';
import '../../theme/app_theme.dart';
import '../app_focusable_action.dart';

// =====================================================================
// §平面图形画廊（ADR-0061 §V）
//
// 轴对称交互讲解的**默认视图**：图形库（kFigureShapes）全部平面图形铺成网格，
// 点一个才进对折演示弹窗。缩略图只画「图形 + 初始对称轴」，不含任何判定——
// 「能不能重合」必须由学生在弹窗里亲手折出来，画廊不替他看答案。
// =====================================================================

/// 平面图形画廊：图形库铺成网格，点一个打开对折演示。
///
/// **为什么默认铺开，而不是把 N 个完整交互场景平铺在页面上**（§O 的旧做法）：
/// [ReflectionSceneWidget] 的画布是「边长 = 可用宽度」的正方形，一个场景竖直方向
/// 就要吃掉 画布 + 状态条 + 播放条 + 3 个轴滑块（≈ 700px）；4 个选项平铺 ≈ 2800px，
/// 学生只能靠滚动逐个看，「对比着看」实际变成「记不住上一个长什么样」。
/// 画廊把每个图形压成一张 ~124px 的卡片，一屏放得下全部 11 个：先挑图形、再认真
/// 折——这两步本来就是对折这道题的操作顺序。
///
/// 画廊**不认识弹窗**：[onOpen] 由调用方决定是弹对话框还是推整页，因此本组件
/// 可以在「题目选项」「知识点讲解」「自由探索」三种语境里复用。
class ReflectionFigureGallery extends StatelessWidget {
  /// 展示的图形；默认整库。传子集即为「只给这几个」。
  final List<FigureShape> figures;

  /// 图形 key → 选项标号（「A」「B」…）。
  ///
  /// 画廊是**整库**（学生能自由探索任意图形），但题目问的那几个必须看得出来——
  /// 带标号的排在最前并挂角标，其余照库序跟在后面。
  final Map<String, String> optionLabels;

  /// 点开某个图形。
  final void Function(FigureShape figure) onOpen;

  /// 当前选中的图形 key（编辑器语境下 = 模板图形）；null = 不高亮。
  ///
  /// 画廊本身是整库浏览，但编辑器需要让教师一眼看到「现在配的是哪个」——否则
  /// 11 张卡片里分不出哪张是模板，保存后也不确定生效没。选中态用强调色描边标示。
  final String? selectedKey;

  /// 网格上方的一句话说明（讲清「下一步做什么」，空态语言纪律 ADR-0051）。
  final String? hint;

  /// 是否**按 [figures] 的传入顺序**渲染（跳过「选项置顶」排序）。
  ///
  /// [_ordered] 会把命中的选项顶到最前、其余按库序跟——教师编排好的图形顺序会因此
  /// 被悄悄重排，而课件语境下**顺序就是教学意图**（ADR-0076 §2.2 的 curated）。
  /// 默认 false：题库 / 错题 / 自由探索路径的观感一字不变。
  final bool preserveOrder;

  /// 是否在只读卡右上角画 play 角标。默认 true（全站统一）。
  ///
  /// 个别纯预览语境（如已经身处演示弹窗内）可以关掉。
  final bool showPlayBadge;

  /// 卡片目标宽度——只用来算列数，实际宽度按可用宽度均分。
  ///
  /// 124 是「缩略图顶点还数得清」的下限再留一点余量：低于它，等边三角形与等腰
  /// 三角形在缩略图上几乎分不出来，画廊就失去「挑图形」的作用。
  static const int targetCardWidth = 124;

  static const int minColumns = 2;
  static const int maxColumns = 6;

  const ReflectionFigureGallery({
    super.key,
    this.figures = kFigureShapes,
    this.optionLabels = const <String, String>{},
    required this.onOpen,
    this.hint,
    this.selectedKey,
    this.preserveOrder = false,
    this.showPlayBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hint != null) ...[
          Text(
            hint!,
            style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        LayoutBuilder(
          builder: (ctx, constraints) {
            // 列数只由**可用宽度**决定（ADR-0045：不按设备形态 / 屏宽分支）。
            // 父级给了无界宽度时（如被塞进横向滚动的 Row）不能用 infinity 去算列数，
            // 退回「3 列」这个中性值——画廊本身不该要求调用方先给一个有界宽度。
            final available = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : targetCardWidth * 3.0;
            final cols =
                (available / targetCardWidth).floor().clamp(minColumns, maxColumns);
            final width =
                (available - (cols - 1) * AppSpacing.sm) / cols;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final f in _ordered())
                  _card(ctx, f, width),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 本题选项排前面（库序保持稳定，别让学生每次看到的顺序都不一样）。
  ///
  /// [preserveOrder] 为真时整段跳过：调用方给的顺序本身就是意图（教师编排），
  /// 重排等于把意图抹掉。
  List<FigureShape> _ordered() {
    if (preserveOrder || optionLabels.isEmpty) return figures;
    final inOption = <FigureShape>[];
    final rest = <FigureShape>[];
    for (final f in figures) {
      (optionLabels.containsKey(f.key) ? inOption : rest).add(f);
    }
    return <FigureShape>[...inOption, ...rest];
  }

  Widget _card(BuildContext context, FigureShape figure, double width) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final badge = optionLabels[figure.key];
    final selected = figure.key == selectedKey;
    return AppFocusableAction(
      onTap: () => onOpen(figure),
      // 画廊卡片是纯图标/短标签的密集块，不给悬停反馈桌面端等于没有反馈。
      hoverHighlight: true,
      // 「播放」而非「打开」：卡右上角那个 play 角标说的就是这件事，读屏 / 键盘
      // 路径因此拿到与视觉一致的语义（ADR-0076 §2.4）。
      semanticLabel: selected
          ? '当前讲解图形：${figure.label}（点开重新演示）'
          : '播放${figure.label}的对折演示',
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        width: width,
        // 卡片是白面（surfaceRaised）压在纸底上，两者几乎同色 → 必须靠 2px 描边
        // 画出边界（.impeccable.md §Design Principles 1）。选中态改用强调色描边 +
        // 淡强调底，让教师一眼看到「现在配的就是这张」（编辑器选图形语境）。
        decoration: BoxDecoration(
          color: selected ? app.accent.withValues(alpha: 0.10) : app.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? app.accent : AppBrutal.ink,
            width: AppElevation.borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                SizedBox(
                  width: width,
                  height: width,
                  child: CustomPaint(
                    painter: _FigureThumbPainter(
                      points: figure.vertices
                          .map((v) => Offset(v.x, v.y))
                          .toList(growable: false),
                      axisAngle: figure.defaultAxisAngle,
                    ),
                  ),
                ),
                // 「默认讲解」标识：该图形就是当前知识点要讲解的模板图形。
                // 编辑器把选中的那张卡标出来即可，不再在画廊下方重复渲染预览大块。
                if (selected)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: app.accent,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Text(
                        '默认讲解',
                        style: text.labelSmall?.copyWith(
                          color: app.onAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                // play 角标：**右上角**（与左上角的「默认讲解」错开，两者可共存）。
                if (showPlayBadge) _playBadge(),
              ],
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
                  if (badge != null) ...[
                    _optionBadge(context, badge),
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

  /// play 角标：**可见性提示**，不是命中区（ADR-0076 §2.4）。
  ///
  /// 整卡仍由 [AppFocusableAction] 承担点击——只留这个小图标当命中区会显著削弱
  /// 触屏可用性；而且不额外套手势识别器：可点区全站只有 [AppFocusableAction]
  /// 一种语言（ADR-0046）。深块配白字（.impeccable.md §Design Principles 3）。
  Widget _playBadge() => Positioned(
        top: 4,
        right: 4,
        child: Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppBrutal.blue,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: AppBrutal.ink,
              width: AppElevation.borderWidthHairline,
            ),
          ),
          child: const Icon(LucideIcons.play, size: 11, color: AppBrutal.onDark),
        ),
      );

  /// 选项标号角标：深块配白字（.impeccable.md §Design Principles 3）。
  Widget _optionBadge(BuildContext context, String label) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: app.accent,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: app.onAccent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 缩略图：图形轮廓（淡填充 + 墨黑描边）+ 初始对称轴虚线。
///
/// **只画，不判**：这里如果出现「✓ 轴对称」之类的标记，学生扫一眼画廊就拿到了
/// 答案，「点开亲手折」这个动作就废了（ADR-0061 §O 的教学意图）。
class _FigureThumbPainter extends CustomPainter {
  /// 归一化顶点（x/y ∈ 0..1）。
  final List<Offset> points;

  /// 初始对称轴角度（度）。画廊取图形库自己的默认值（箭头 = 0° 横轴）。
  final double axisAngle;

  const _FigureThumbPainter({required this.points, required this.axisAngle});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 3) return;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(points[i].dx * size.width, points[i].dy * size.height);
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
        ..color = AppBrutal.cyan.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppBrutal.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppElevation.borderWidthSm
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    // 对称轴画在最上层（与演示画布一致），虚线是「对称轴」的通用记法。
    final a = axisAngle * math.pi / 180;
    const c = Offset(0.5, 0.5);
    const l = 0.46;
    _dashed(
      canvas,
      size,
      Offset(c.dx - l * math.cos(a), c.dy - l * math.sin(a)),
      Offset(c.dx + l * math.cos(a), c.dy + l * math.sin(a)),
      AppBrutal.ink,
      AppElevation.borderWidthHairline,
    );
  }

  void _dashed(
    Canvas canvas,
    Size size,
    Offset p1,
    Offset p2,
    Color color,
    double width,
  ) {
    final a = Offset(p1.dx * size.width, p1.dy * size.height);
    final b = Offset(p2.dx * size.width, p2.dy * size.height);
    final len = (b - a).distance;
    if (len == 0) return;
    const dash = 6.0;
    const gap = 4.0;
    final u = (b - a) / len;
    final steps = (len / (dash + gap)).floor();
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < steps; i++) {
      final s = i * (dash + gap);
      canvas.drawLine(a + u * s, a + u * (s + dash), paint);
    }
  }

  @override
  bool shouldRepaint(_FigureThumbPainter old) =>
      old.axisAngle != axisAngle || old.points != points;
}
