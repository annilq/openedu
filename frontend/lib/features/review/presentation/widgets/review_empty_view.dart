import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';

/// 复习页空态：今天没有到期错题。
class ReviewEmptyView extends StatelessWidget {
  const ReviewEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl3),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xl4),
            decoration: BoxDecoration(
              color: scheme.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.banner),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  alignment: Alignment.center,
                  child: Icon(LucideIcons.sparkles,
                      size: 48, color: scheme.onTertiaryContainer),
                ),
                const SizedBox(height: AppSpacing.xl2),
                Text('今天没有要复习的题',
                    textAlign: TextAlign.center,
                    style: AppTheme.textOf(context).headlineMedium),
                const SizedBox(height: AppSpacing.sm),
                Text('把错题复习掉，就能记得更牢～',
                    textAlign: TextAlign.center,
                    style: AppTheme.textOf(context).bodyMedium),
                const SizedBox(height: AppSpacing.xl4),
                AppPrimaryButton(
                  label: '返回',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
