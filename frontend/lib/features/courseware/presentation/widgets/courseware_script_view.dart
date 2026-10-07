import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../domain/models/courseware_section.dart';

/// 话术段列表渲染（ADR-0067 第二轮 T02）：逐段投射到提问卡，重点（加粗 / 高亮）照渲染。
///
/// 演示页主区与练习提问卡共用，保证「多段 + 重点」两处视觉一致。空列表返回零尺寸
/// 占位，调用方自己决定是否显示降级文案。
class CoursewareScriptSegmentsView extends StatelessWidget {
  const CoursewareScriptSegmentsView({
    super.key,
    required this.segments,
    this.baseStyle,
  });

  final List<CoursewareScriptSegment> segments;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final base = baseStyle ?? text.titleMedium ?? text.bodyMedium!;
    if (segments.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final seg in segments)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text.rich(
              TextSpan(text: seg.text, style: _style(seg.emphasis, base, app)),
            ),
          ),
      ],
    );
  }

  TextStyle _style(CoursewareScriptEmphasis e, TextStyle base, AppColors app) {
    switch (e) {
      case CoursewareScriptEmphasis.bold:
        return base.copyWith(fontWeight: FontWeight.bold);
      case CoursewareScriptEmphasis.highlight:
        // 高亮 = 主色文字 + 淡主色底，投影时一眼看到要点（不引入新渲染引擎）。
        return base.copyWith(
          color: app.primary,
          backgroundColor: app.primary.withValues(alpha: 0.15),
          fontWeight: FontWeight.w600,
        );
      case CoursewareScriptEmphasis.none:
        return base;
    }
  }
}
