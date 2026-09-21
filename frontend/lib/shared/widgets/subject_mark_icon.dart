import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// 学科几何标记图标（实心，自绘）。
///
/// 自绘而非用图标字体：lucide 的 square/circle/triangle 是**描边**图标，
/// 在 9-12px 尺寸下描边糊成一团，形状辨识度反而不如实心块。
class SubjectMarkIcon extends StatelessWidget {
  final SubjectMark mark;
  final double size;
  final Color color;

  const SubjectMarkIcon({
    super.key,
    required this.mark,
    this.size = 10,
    this.color = AppBrutal.ink,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _SubjectMarkPainter(mark: mark, color: color),
      );
}

class _SubjectMarkPainter extends CustomPainter {
  final SubjectMark mark;
  final Color color;
  const _SubjectMarkPainter({required this.mark, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    switch (mark) {
      case SubjectMark.square:
        canvas.drawRect(Offset.zero & size, paint);
      case SubjectMark.circle:
        canvas.drawCircle(size.center(Offset.zero), size.width / 2, paint);
      case SubjectMark.triangle:
        canvas.drawPath(
          Path()
            ..moveTo(size.width / 2, 0)
            ..lineTo(size.width, size.height)
            ..lineTo(0, size.height)
            ..close(),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_SubjectMarkPainter oldDelegate) =>
      oldDelegate.mark != mark || oldDelegate.color != color;
}
