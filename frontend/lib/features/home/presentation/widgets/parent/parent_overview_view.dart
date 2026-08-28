import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../providers/home_notifier.dart';
import '../../providers/selected_child_provider.dart';

/// 家长概览右栏：学习进度 + 知识点掌握度。
class ParentOverviewView extends ConsumerWidget {
  const ParentOverviewView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedChildProvider);
    if (selected == null) return _emptyState(context);

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
              const SectionTitle('学习进度'),
              _buildProgress(context, ref),
              const SizedBox(height: AppSpacing.xl3),
              const SectionTitle('知识点掌握度'),
              _buildMastery(context, ref),
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
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Icon(LucideIcons.layoutDashboard,
                  size: 28, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: AppSpacing.xl),
            Text('请先在侧栏选择娃娃',
                style: AppTheme.textOf(context).bodyLarge),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context, WidgetRef ref) {
    final progState = ref.watch(progressNotifierProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: switch (progState) {
        ProgressInitial() || ProgressLoading() =>
          const AppLoading.skeletonInline(skeletonLines: 2),
        ProgressError() => AppError(message: progState.message),
        ProgressLoaded() => AppCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 560;
                return Wrap(
                  runSpacing: AppSpacing.xl2,
                  spacing: AppSpacing.md,
                  children: [
                    _StatCard(label: '总题数',
                        value: '${progState.progress.total}',
                        wide: wide, icon: LucideIcons.listOrdered),
                    _StatCard(label: '答对',
                        value: '${progState.progress.correct}',
                        wide: wide, icon: LucideIcons.checkCircle2),
                    _StatCard(label: '正确率',
                        value: '${(progState.progress.accuracy * 100).round()}%',
                        wide: wide, icon: LucideIcons.barChart3,
                        tone: _Tone.positive),
                    _StatCard(label: '连续打卡',
                        value: '${progState.progress.streakDays}天',
                        wide: wide, icon: LucideIcons.flame,
                        tone: _Tone.warm),
                  ],
                );
              },
            ),
          ),
      },
    );
  }

  Widget _buildMastery(BuildContext context, WidgetRef ref) {
    final scheme = AppTheme.colorsOf(context);
    final state = ref.watch(masteryNotifierProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: switch (state) {
        MasteryInitial() || MasteryLoading() =>
          const AppLoading.skeletonInline(skeletonLines: 3),
        MasteryError() => AppError(message: state.message),
        MasteryLoaded() => state.mastery.items.isEmpty
          ? AppCard(
              padding: const EdgeInsets.all(AppSpacing.xl3),
              child: Row(children: [
                Container(width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Icon(LucideIcons.lightbulb, size: 28,
                      color: scheme.onTertiaryContainer),
                ),
                const SizedBox(width: AppSpacing.xl),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('还没有作答记录',
                        style: AppTheme.textOf(context).titleSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text('先布置任务吧～',
                        style: AppTheme.textOf(context).bodyMedium),
                  ],
                )),
              ]),
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
                        const TextSpan(text: '已掌握 '),
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
                  const SizedBox(height: AppSpacing.xl),
                  ...state.mastery.items.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _MasteryBar(item: m),
                  )),
                ],
              ),
            ),
      },
    );
  }
}

// —— 私有组件 ——

enum _Tone { neutral, positive, warm, alert }

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool wide;
  final IconData icon;
  final _Tone tone;
  const _StatCard({
    required this.label, required this.value, required this.wide,
    required this.icon, this.tone = _Tone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final (bg, fg) = switch (tone) {
      _Tone.positive => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _Tone.warm => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _Tone.alert => (scheme.errorContainer, scheme.onErrorContainer),
      _Tone.neutral => (scheme.surfaceSunken, scheme.onSurface),
    };
    return Container(
      width: wide ? null : 160,
      constraints: wide
        ? BoxConstraints(
            minWidth: 140,
            maxWidth: (MediaQuery.of(context).size.width -
                AppSpacing.xl2 * 2 - AppSpacing.lg * 2 - AppSpacing.md * 3) / 4,
          )
        : null,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: scheme.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: fg),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(value,
            style: AppTheme.textOf(context).headlineMedium?.copyWith(
              color: scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: AppTheme.textOf(context).bodySmall),
        ],
      ),
    );
  }
}

enum _MasteryLevel { mastered, solid, learning, weak, needWork, unknown }

class _MasteryBar extends StatelessWidget {
  final KnowledgeMasteryModel item;
  const _MasteryBar({required this.item});

  (_MasteryLevel, Color, Color) _mappingOf(AppColors scheme) {
    switch (item.level) {
      case '已掌握': return (_MasteryLevel.mastered, scheme.primary, scheme.tertiaryContainer);
      case '较扎实': return (_MasteryLevel.solid, scheme.tertiary, scheme.primaryContainer);
      case '巩固中': return (_MasteryLevel.learning, scheme.primary, scheme.surfaceSunken);
      case '薄弱': return (_MasteryLevel.weak, scheme.secondary, scheme.secondaryContainer);
      case '待加强': return (_MasteryLevel.needWork, scheme.error, scheme.errorContainer);
      default: return (_MasteryLevel.unknown, scheme.onSurfaceVariant, scheme.surfaceSunken);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final (_, fgColor, _) = _mappingOf(scheme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text('${item.subject} · ${item.knowledgePoint}',
              style: AppTheme.textOf(context).bodyMedium)),
          const SizedBox(width: AppSpacing.md),
          Text('${item.score.round()}分',
            style: AppTheme.textOf(context).bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
          const SizedBox(width: AppSpacing.md),
          AppBadge.infoChip(item.level),
        ]),
        const SizedBox(height: AppSpacing.sm),
        AppProgressBar(
          value: (item.score / 100).clamp(0.0, 1.0),
          height: 10, color: fgColor, trackColor: scheme.surfaceSunken,
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
