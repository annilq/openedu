import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../providers/review_notifier.dart';

String _fmtDate(DateTime? dt) {
  if (dt == null) return '—';
  final l = dt.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

/// 娃娃端错题本：v2 redesign - 用 AppTags 语义化、SectionTitle、空状态加图标。
class WrongQuestionsScreen extends ConsumerStatefulWidget {
  const WrongQuestionsScreen({super.key});

  @override
  ConsumerState<WrongQuestionsScreen> createState() => _WrongQuestionsScreenState();
}

class _WrongQuestionsScreenState extends ConsumerState<WrongQuestionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(childWrongQuestionsProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(childWrongQuestionsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('我的错题本')),
      body: switch (state) {
        WrongQuestionsInitial() || WrongQuestionsLoading() =>
          const AppLoading(message: '加载错题...'),
        WrongQuestionsError() => AppError(
            message: state.message,
            onRetry: () => ref.read(childWrongQuestionsProvider.notifier).load(),
          ),
        WrongQuestionsLoaded() => state.items.isEmpty
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl3),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.xl4),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadius.banner),
                        border: Border.all(color: scheme.outline, width: 1),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            alignment: Alignment.center,
                            child: Icon(Icons.verified_outlined,
                                size: 44,
                                color: scheme.onTertiaryContainer),
                          ),
                          const SizedBox(height: AppSpacing.xl2),
                          Text('还没有错题',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: AppSpacing.xs),
                          Text('继续保持，做题仔细一点就不会错啦～',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : RefreshIndicator(
                color: scheme.primary,
                backgroundColor: scheme.surfaceContainerLow,
                onRefresh: () =>
                    ref.read(childWrongQuestionsProvider.notifier).load(),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl4),
                  itemCount: state.items.length,
                  itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: _WrongQuestionCard(item: state.items[i]),
                  ),
                ),
              ),
      },
    );
  }
}

class _WrongQuestionCard extends StatelessWidget {
  final WrongQuestionModel item;
  const _WrongQuestionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.stem, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppTags.normal(item.subject),
                AppTags.info(item.knowledgePoint),
                AppTags.warning('错过 ${item.wrongCount} 次'),
                AppTags.normal('复习阶段 ${item.reviewStage}'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('最近答错：${_fmtDate(item.firstWrongAt)}',
                      style: Theme.of(context).textTheme.labelSmall),
                  if (item.dueAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('下次复习：${_fmtDate(item.dueAt)}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              )),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
