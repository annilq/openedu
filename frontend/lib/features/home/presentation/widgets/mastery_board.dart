import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../providers/home_notifier.dart';

/// 知识点掌握度看板（家长 / 娃娃共用）。
///
/// 进度条与行首色点按学科色着色（ADR-0014 学科色消费），掌握等级用语义徽章
/// 保留「薄弱 / 待加强」警示。娃端通过 [isChild] 切换第一人称文案。
class MasteryBoard extends ConsumerWidget {
  final bool isChild;
  const MasteryBoard({super.key, this.isChild = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = AppTheme.colorsOf(context);
    final state = ref.watch(masteryNotifierProvider);
    return switch (state) {
      MasteryInitial() ||
      MasteryLoading() =>
        const AppLoading.skeletonInline(skeletonLines: 3),
      MasteryError() => AppError(message: state.message),
      MasteryLoaded() => state.mastery.items.isEmpty
          ? AppCard(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 220;
                  final iconBox = Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    alignment: Alignment.center,
                    child: Icon(LucideIcons.lightbulb,
                        size: 28, color: scheme.onTertiaryContainer),
                  );
                  final texts = Column(
                    crossAxisAlignment: narrow
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      Text(isChild ? '你还没有作答记录' : '还没有作答记录',
                          style: AppTheme.textOf(context).titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isChild ? '去做几道题，看看你掌握了什么吧～' : '先布置任务吧～',
                        style: AppTheme.textOf(context).bodyMedium,
                        textAlign: narrow ? TextAlign.center : TextAlign.start,
                      ),
                    ],
                  );
                  if (narrow) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        iconBox,
                        const SizedBox(height: AppSpacing.md),
                        texts,
                      ],
                    );
                  }
                  return Row(children: [
                    iconBox,
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(child: texts),
                  ]);
                },
              ),
            )
          : AppCard(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: AppTheme.textOf(context).bodyLarge,
                      children: [
                        TextSpan(text: isChild ? '你已掌握 ' : '已掌握 '),
                        TextSpan(
                          text: '${state.mastery.masteredCount}',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: ' / ${state.mastery.totalKnowledgePoints} 个知识点',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: state.mastery.items
                        .map((m) => m.subject)
                        .toSet()
                        .map((s) => AppTags.subject(
                              SubjectAccent.fromName(s),
                              label: s,
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ...state.mastery.items.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _MasteryBar(item: m),
                      )),
                ],
              ),
            ),
    };
  }
}

/// 掌握度等级 → 语义徽章（保留「薄弱 / 待加强」的警示信号；
/// 进度条与行首色点改由学科色着色，见 [_MasteryBar]）。
Widget _levelBadge(String level) {
  switch (level) {
    case '已掌握':
    case '较扎实':
      return AppBadge.successChip(level);
    case '薄弱':
    case '待加强':
      return AppBadge.warningChip(level);
    default:
      return AppBadge.infoChip(level);
  }
}

class _MasteryBar extends StatelessWidget {
  final KnowledgeMasteryModel item;
  const _MasteryBar({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    // 学科色：进度条 + 行首色点均按学科着色（ADR-0014 学科色消费）。
    final sc =
        SubjectAccent.forContext(SubjectAccent.fromName(item.subject), context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final subjectRow = Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: sc.accent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('${item.subject} · ${item.knowledgePoint}',
                    style: AppTheme.textOf(context).bodyMedium),
              ),
            ]);
            final trailing = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${item.score.round()}分',
                    style: AppTheme.textOf(context).bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
                const SizedBox(width: AppSpacing.md),
                _levelBadge(item.level),
              ],
            );
            if (constraints.maxWidth < 300) {
              // 窄卡：分数与等级徽章换到第二行，避免固定尾列溢出。
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  subjectRow,
                  const SizedBox(height: AppSpacing.xs),
                  trailing,
                ],
              );
            }
            return Row(children: [
              Expanded(child: subjectRow),
              const SizedBox(width: AppSpacing.md),
              trailing,
            ]);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        AppProgressBar(
          value: (item.score / 100).clamp(0.0, 1.0),
          height: 10,
          color: sc.accent,
          trackColor: scheme.surfaceSunken,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          item.activeWrong > 0
              ? '正确率 ${(item.accuracy * 100).round()}% · 有 ${item.activeWrong} 题待复习'
              : '正确率 ${(item.accuracy * 100).round()}% · 无待复习错题',
          style: AppTheme.textOf(context).bodySmall,
        ),
      ],
    );
  }
}
