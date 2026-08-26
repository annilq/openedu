import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../review/presentation/providers/review_notifier.dart';
import '../../providers/selected_child_provider.dart';

/// 家长错题本右栏：查看选中娃娃的错题列表。
class ParentWrongQuestionsView extends ConsumerWidget {
  const ParentWrongQuestionsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedChildProvider);
    if (selected == null) return _emptyState(context);

    final state = ref.watch(parentWrongQuestionsProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl4),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('错题本'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: switch (state) {
                  WrongQuestionsInitial() || WrongQuestionsLoading() =>
                    const AppLoading(message: '加载错题...'),
                  WrongQuestionsError() => AppError(message: state.message),
                  WrongQuestionsLoaded() => state.items.isEmpty
                      ? AppCard(
                          padding: const EdgeInsets.all(AppSpacing.xl3),
                          child: Center(
                            child: Text('暂无错题，继续保持～',
                                style: AppTheme.textOf(context).bodyLarge),
                          ),
                        )
                      : AppCard(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: state.items
                                .map((item) => _ParentWrongCard(item: item))
                                .toList(),
                          ),
                        ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Center(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Icon(LucideIcons.bookOpen, size: 28,
                  color: scheme.onErrorContainer),
            ),
            const SizedBox(width: AppSpacing.xl),
            Text('请先在侧栏选择娃娃',
                style: AppTheme.textOf(context).bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _ParentWrongCard extends StatelessWidget {
  final WrongQuestionModel item;
  const _ParentWrongCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.stem, style: AppTheme.textOf(context).bodyLarge),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppTags.normal(item.knowledgePoint),
              AppTags.warning('错过 ${item.wrongCount} 次'),
              AppTags.info('复习阶段 ${item.reviewStage}'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.checkCircle2, size: 20,
                    color: scheme.onTertiaryContainer),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '标准答案：${item.answer ?? '—'}',
                    style: AppTheme.textOf(context).bodyMedium?.copyWith(
                      color: scheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (item.explanation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text('解析：${item.explanation}',
                  style: AppTheme.textOf(context).bodyMedium),
            ),
          const SizedBox(height: AppSpacing.md),
          Container(width: double.infinity, height: 1, color: scheme.outlineVariant),
        ],
      ),
    );
  }
}
