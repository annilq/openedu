import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';

/// AI 伴学页空态：引导孩子提问。
class TutorWelcomeHint extends StatelessWidget {
  const TutorWelcomeHint({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl3),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xl3),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.banner),
              border: Border.all(
                  color: scheme.outline, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: scheme.outline, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Icon(LucideIcons.sparkles,
                      size: 36, color: scheme.secondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('有问题就问 AI 老师吧',
                    textAlign: TextAlign.center,
                    style: text.titleLarge?.copyWith(
                      color: scheme.onSecondaryContainer,
                    )),
                const SizedBox(height: AppSpacing.sm),
                Text('只讲学习内容，其他问题不回答哦',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
