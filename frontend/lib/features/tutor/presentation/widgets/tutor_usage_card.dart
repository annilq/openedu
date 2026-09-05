import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../providers/tutor_notifier.dart';

/// 家长端 AI 用量卡：今日已用提问次数与时长。
class TutorUsageCard extends StatelessWidget {
  final TutorUsageState usageState;
  const TutorUsageCard({super.key, required this.usageState});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.barChart3,
                    size: 22, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text('今日已用', style: text.titleSmall)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: switch (usageState) {
              TutorUsageLoaded(:final usage) => Text(
                  '提问 ${usage.asksToday}'
                  '${usage.askLimit != null ? ' / ${usage.askLimit} 次' : ' 次'}'
                  '　·　时长 ${(usage.usedSeconds / 60).toStringAsFixed(1)}'
                  '${usage.minutesLimit != null ? ' / ${usage.minutesLimit} 分钟' : ' 分钟'}',
                  style: text.bodyLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              TutorUsageError(:final message) =>
                Text(message, style: TextStyle(color: scheme.error)),
              _ => Text('今日用量加载中…', style: text.bodyMedium),
            },
          ),
        ],
      ),
    );
  }
}
