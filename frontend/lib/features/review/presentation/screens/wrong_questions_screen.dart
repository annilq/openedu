import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../providers/review_notifier.dart';

String _fmtDate(DateTime? dt) {
  if (dt == null) return '—';
  final l = dt.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

/// 娃娃端错题本：v2 redesign - 用 AppTags 语义化、SectionTitle、空状态加图标。
class WrongQuestionsScreen extends ConsumerStatefulWidget {
  final bool showBack;
  const WrongQuestionsScreen({super.key, this.showBack = true});

  @override
  ConsumerState<WrongQuestionsScreen> createState() =>
      _WrongQuestionsScreenState();
}

class _WrongQuestionsScreenState extends ConsumerState<WrongQuestionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(childWrongQuestionsProvider.notifier).load();
    });
  }

  Future<void> _refresh() {
    return ref.read(childWrongQuestionsProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(childWrongQuestionsProvider);
    final scheme = AppTheme.colorsOf(context);

    return SizedBox.expand(
      child: ColoredBox(
        color: scheme.surface,
        child: Column(
          children: [
            AppTopBar(
              title: '我的错题本',
              showBack: widget.showBack,
              trailing: ShadButton.ghost(
                width: 40,
                height: 40,
                padding: EdgeInsets.zero,
                backgroundColor: const Color(0x00000000),
                hoverBackgroundColor: scheme.surfaceContainerHigh,
                pressedBackgroundColor: scheme.surfaceContainer,
                onPressed: _refresh,
                child: Icon(
                  LucideIcons.refreshCw,
                  color: scheme.onSurface,
                  size: 20,
                ),
              ),
            ),
            Expanded(
              child: switch (state) {
                WrongQuestionsInitial() ||
                WrongQuestionsLoading() =>
                  const AppLoading(message: '加载错题...'),
                WrongQuestionsError() => AppError(
                    message: state.message,
                    onRetry: () =>
                        ref.read(childWrongQuestionsProvider.notifier).load(),
                  ),
                WrongQuestionsLoaded() => state.items.isEmpty
                    ? _buildEmptyView()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                            AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
                        itemCount: state.items.length,
                        itemBuilder: (ctx, i) =>
                            _WrongQuestionCard(item: state.items[i]),
                      ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    final scheme = AppTheme.colorsOf(context);
    return Align(alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.banner),
              border: Border.all(color: scheme.outline, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  alignment: Alignment.center,
                  child: Icon(LucideIcons.badgeCheck,
                      size: 44, color: scheme.onTertiaryContainer),
                ),
                const SizedBox(height: AppSpacing.xl2),
                Text('还没有错题',
                    textAlign: TextAlign.start,
                    style: AppTheme.textOf(context).titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text('继续保持，做题仔细一点就不会错啦～',
                    textAlign: TextAlign.start,
                    style: AppTheme.textOf(context).bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WrongQuestionCard extends StatelessWidget {
  final WrongQuestionModel item;
  const _WrongQuestionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.stem, style: AppTheme.textOf(context).titleSmall),
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
                    style: AppTheme.textOf(context).labelSmall),
                if (item.dueAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('下次复习：${_fmtDate(item.dueAt)}',
                        style: AppTheme.textOf(context).labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            )),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
