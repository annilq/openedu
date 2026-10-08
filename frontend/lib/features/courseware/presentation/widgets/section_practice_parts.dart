import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../domain/models/courseware_section.dart';

/// 课堂练习环节的辅助展示件（从 `section_practice.dart` 抽出，ADR-0058 P4：子件独立成文件）。
///
/// 三者均为纯展示、不依赖 `_SectionPracticeState`，故可独立成库，让主文件回到 400 行以内。
/// 命名加 `Practice` 前缀以避免与其它环节的同类件撞名。

class PracticeQuestionPrompt extends StatelessWidget {
  const PracticeQuestionPrompt({super.key, required this.segments});

  final List<CoursewareScriptSegment> segments;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return AppCard(
      margin: EdgeInsets.zero,
      color: app.semanticInfo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '课堂提问',
            style: text.labelSmall?.copyWith(color: app.semanticInfoFg),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (segments.isEmpty)
            Text(
              '请根据下面的练习向学生提问。',
              style: text.titleLarge?.copyWith(color: app.semanticInfoFg),
            )
          else
            for (final seg in segments)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  seg.text,
                  style: text.titleLarge?.copyWith(
                    color: app.semanticInfoFg,
                    fontWeight: seg.emphasis == CoursewareScriptEmphasis.bold
                        ? FontWeight.bold
                        : null,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class PracticeAction extends StatelessWidget {
  const PracticeAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.fill,
    this.foreground,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? fill;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final background = fill ?? app.cta;
    final color = foreground ?? app.onCta;
    return AppFocusableAction(
      onTap: onPressed,
      enabled: onPressed != null,
      semanticLabel: label,
      hoverHighlight: true,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Container(
          constraints: BoxConstraints(
            minWidth: AppLayout.tapTarget * 2,
            minHeight: AppControl.heightLgOf(context),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: app.outline,
              width: AppElevation.borderWidth,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: AppSpacing.xl, color: color),
              const SizedBox(width: AppSpacing.sm),
              Text(label, style: text.labelLarge?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class PracticeNotice extends StatelessWidget {
  const PracticeNotice({super.key, required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: error ? app.semanticError : app.semanticPositive,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: app.outline,
          width: AppElevation.borderWidthHairline,
        ),
      ),
      child: Text(
        message,
        style: AppTheme.textOf(context).bodyMedium?.copyWith(
          color: error ? app.semanticErrorFg : app.semanticPositiveFg,
        ),
      ),
    );
  }
}
