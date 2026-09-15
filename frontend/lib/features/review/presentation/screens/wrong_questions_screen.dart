import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/presentation/resource.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_motion.dart';
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
                ResourceIdle() ||
                ResourceLoading() =>
                  const AppLoading(message: '加载错题...'),
                ResourceError() => AppError(
                    message: state.message,
                    onRetry: () =>
                        ref.read(childWrongQuestionsProvider.notifier).load(),
                  ),
                ResourceLoaded() => (state.dataOrNull ?? const []).isEmpty
                    ? _buildEmptyView()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                            AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
                        itemCount: (state.dataOrNull ??
                                const <WrongQuestionModel>[])
                            .length,
                        // key 稳定 → PopIn 只对「新滑入」的行重放，复用行不闪。
                        itemBuilder: (ctx, i) => PopIn(
                          key: ValueKey<int>(i),
                          // 左侧学科色条由 Row(stretch) 撑满行高；行高随内容，
                          // ListView 内高度无界，须 IntrinsicHeight 给有界高度。
                          child: IntrinsicHeight(
                            child: _WrongQuestionCard(
                              item: (state.dataOrNull ??
                                  const <WrongQuestionModel>[])[i],
                            ),
                          ),
                        ),
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
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl2),
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
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(28),
                      // 色块 = 2px 墨黑描边 + 硬阴影（ADR-0044）。
                      border: Border.all(
                          color: AppBrutal.ink, width: AppElevation.borderWidth),
                      boxShadow: AppElevation.hard(),
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
      ),
    );
  }
}

/// 错题列表行：用 [AppCard.listRow]（1px 墨黑描边、无阴影）降噪，
/// 仅左侧 4px 学科色条 + 学科 chip 表达身份（不整行填充，ADR-0044）。
class _WrongQuestionCard extends StatelessWidget {
  final WrongQuestionModel item;
  const _WrongQuestionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final subjectKey = SubjectAccent.fromName(item.subject);
    final subjectColor = SubjectAccent.forContext(subjectKey, context).accent;
    return AppCard.listRow(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: subjectColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.stem,
                        style: AppTheme.textOf(context).titleSmall),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        // 学科三重编码 chip（色 + 几何标记 + 文字）。
                        AppTags.subject(subjectKey),
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
                                  style: AppTheme.textOf(context)
                                      .labelSmall
                                      ?.copyWith(
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
            ),
          ],
        ),
      ),
    );
  }
}
