import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/presentation/resource.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../providers/home_notifier.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_progress_bar.dart';
import '../../../../shared/widgets/app_tags.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/presentation/shell_navigation.dart';
import '../../../../shared/widgets/subject_mark_icon.dart';
import '../providers/task_form_prefill.dart';

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
    final mastery = state.dataOrNull;
    return switch (state) {
      ResourceError() => AppError(message: state.errorOrNull ?? ''),
      _ when mastery == null =>
        const AppLoading.skeletonInline(skeletonLines: 3),
      _ => mastery.items.isEmpty
          ? AppCard(
              child: AppEmptyState.inline(
                icon: LucideIcons.lightbulb,
                title: isChild ? '你还没有作答记录' : '还没有作答记录',
                message: isChild ? '去做几道题，看看你掌握了什么吧～' : '先布置任务吧～',
              ),
            )
          : AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: AppTheme.textOf(context).bodyLarge,
                      children: [
                        TextSpan(text: isChild ? '你已掌握 ' : '已掌握 '),
                        TextSpan(
                          text: '${mastery.masteredCount}',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: ' / ${mastery.totalKnowledgePoints} 个知识点',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: mastery.items
                        .map((m) => m.subject)
                        .toSet()
                        .map((s) => AppTags.subject(
                              SubjectAccent.fromName(s),
                              label: s,
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ...mastery.items.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _MasteryBar(
                          item: m,
                          // 反馈边入口（ADR-0060 D1）：仅家长、且仅当该知识点有活跃
                          // 错题时，提供「就这个知识点出题」——把薄弱点直接喂回出题。
                          onGenerate: (!isChild && m.activeWrong > 0)
                              ? () {
                                  ref
                                      .read(taskFormPrefillProvider.notifier)
                                      .state = TaskFormPrefill(
                                    knowledgePoint: m.knowledgePoint,
                                    weakExampleIds:
                                        m.representativeWrongQuestionIds,
                                  );
                                  ref
                                      .read(shellNavigationProvider.notifier)
                                      .request(ShellDestination.parentCreateTask);
                                }
                              : null,
                        ),
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
  // 反馈边入口（ADR-0060 D1）：点击跳到出题表单并预填本知识点 + 代表错题。
  // 仅在家长端且有活跃错题时由父级传入（见 [MasteryBoard]）。
  final VoidCallback? onGenerate;
  const _MasteryBar({required this.item, this.onGenerate});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    // 学科色：进度条 + 行首标记均按学科着色（ADR-0014 学科色消费）。
    final subjectKey = SubjectAccent.fromName(item.subject);
    final sc = SubjectAccent.forContext(subjectKey, context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final subjectRow = Row(children: [
              // 行首标记走 [SubjectMarkIcon]（数学■ / 语文● / 英语▲）而非纯色圆点。
              // 同一行里进度条已按学科着色（见下方 AppProgressBar），再放一个纯色点
              // 就是「两条颜色通道、零形状通道」——红绿色盲下语文(coral)与英语(yellow)
              // 同属暖色系会趋同（.impeccable.md §Design Principles 4）。
              // 尺寸 10 与原先的色点一致：改的是编码方式，不是版式。
              SubjectMarkIcon(
                mark: subjectKey.mark,
                color: sc.accent,
                size: 10,
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
        if (onGenerate != null)
          Align(
            alignment: Alignment.centerRight,
            child: AppTextAction(
              label: '就这个出题',
              semanticLabel: '就${item.knowledgePoint}出题',
              onPressed: onGenerate,
            ),
          ),
      ],
    );
  }
}
