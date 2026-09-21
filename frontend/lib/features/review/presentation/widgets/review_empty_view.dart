import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_card.dart';

/// 复习页空态：今天没有到期错题。
class ReviewEmptyView extends StatelessWidget {
  /// 「返回」的出口，由组合根注入。
  ///
  /// 与 `ReviewScreen.onExit` 同一条理由：本页挂在壳的页签里、不在 push 路由上，
  /// 自己 `Navigator.pop` 会把根导航栈弹空（白屏 + `_history.isNotEmpty` 断言）。
  /// 没注入时退回 `maybePop`（无可 pop 路由即 no-op）。
  final VoidCallback? onBack;

  const ReviewEmptyView({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.contentEmpty),
          child: PopIn(
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(32),
                      // 色块 = 2px 墨黑描边 + 硬阴影（ADR-0044）。
                      border: Border.all(
                          color: AppBrutal.ink, width: AppElevation.borderWidth),
                      boxShadow: AppElevation.hard(),
                    ),
                    alignment: Alignment.center,
                    child: Icon(LucideIcons.sparkles,
                        size: 48, color: scheme.onTertiaryContainer),
                  ),
                  const SizedBox(height: AppSpacing.xl2),
                  Text('今天没有要复习的题',
                      textAlign: TextAlign.start,
                      style: AppTheme.textOf(context).headlineMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text('把错题复习掉，就能记得更牢～',
                      textAlign: TextAlign.start,
                      style: AppTheme.textOf(context).bodyMedium),
                  const SizedBox(height: AppSpacing.xl4),
                  AppPrimaryButton(
                    label: '返回',
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
