import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import 'app_motion.dart';

/// 做题完成卡：内置 [ResultTone] 分档、icon、正确率、进度条（practice/review 逐行一致）。
///
/// 差异由插槽承载：[title]、[subtitle]（主行 bodyLarge）、可选 [note]（次行 bodySmall）、
/// [trailing]（底部按钮）、可选 [overlay]（背景层，如彩带）、[animate]（是否 [PopIn] 入场）。
class AppQuizResultCard extends StatelessWidget {
  final int correct;
  final int total;
  final String title;
  final String subtitle;
  final String? note;
  final Widget trailing;
  final Widget? overlay;
  final bool animate;

  const AppQuizResultCard({
    super.key,
    required this.correct,
    required this.total,
    required this.title,
    required this.subtitle,
    this.note,
    required this.trailing,
    this.overlay,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final accuracy = total > 0 ? (correct / total * 100).round() : 0;
    final tone = switch (accuracy) {
      >= 90 => ResultTone.positive,
      >= 70 => ResultTone.warm,
      >= 40 => ResultTone.alert,
      _ => ResultTone.neutral,
    };
    final (iconBg, iconFg, iconData) = switch (tone) {
      ResultTone.positive => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          LucideIcons.award
        ),
      ResultTone.warm => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          LucideIcons.thumbsUp
        ),
      ResultTone.alert => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          LucideIcons.barChart3
        ),
      ResultTone.neutral => (
          scheme.surfaceSunken,
          scheme.onSurface,
          LucideIcons.checkCircle2
        ),
    };

    Widget card = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            decoration: BoxDecoration(
              color: scheme.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.banner),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(36),
                  ),
                  alignment: Alignment.center,
                  child: Icon(iconData, size: 56, color: iconFg),
                ),
                const SizedBox(height: AppSpacing.xl2),
                Text(title, style: text.headlineMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle, style: text.bodyLarge),
                if (note != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(note!, style: text.bodySmall),
                ],
                const SizedBox(height: AppSpacing.xl3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 12,
                    child: AppProgressBar(
                      value: total > 0 ? (correct / total).clamp(0.0, 1.0) : 0,
                      height: 12,
                      color: scheme.primary,
                      trackColor: scheme.surfaceSunken,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl4),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
    if (animate) card = PopIn(child: card);
    if (overlay != null) {
      return Stack(
        children: [Positioned.fill(child: overlay!), card],
      );
    }
    return card;
  }
}
