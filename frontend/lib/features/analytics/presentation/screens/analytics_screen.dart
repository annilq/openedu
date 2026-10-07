import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_chip.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_section_title.dart';
import '../../domain/models/analytics_models.dart';
import '../providers/analytics_notifier.dart';
import '../providers/analytics_notifier_provider.dart';

/// 学情统计页（ticket 12，消费 ticket 11 的三个聚合端点）。
///
/// 作用域三态（全体学生 / 单个班级 / 单个学生）+ 四维（学科 / 年级 / 学期 / 知识点）
/// 切换即并行重取三份聚合；边界口径严格对照 ADR-0070：
/// - 孤儿错题（原题被硬删）以「未知」分组显式标注数量，不混入任何有效分组；
/// - 空学期由后端收敛为「整学年」，界面原样展示；
/// - 「年级」维度明确标注为**题目的年级**（非学生所在年级），与其余维度清晰区分。
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 仅首屏初次加载；重访若已是 Loaded/Error 则复用，错误态由重试按钮触发。
      final s = ref.read(analyticsNotifierProvider);
      if (s is AnalyticsInitial) {
        ref.read(analyticsNotifierProvider.notifier).init();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analyticsNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(state: state),
        Expanded(
          child: state is AnalyticsLoaded
              ? _LoadedBody(
                  state: state,
                  notifier: ref.read(analyticsNotifierProvider.notifier),
                )
              : _CenterState(state: state),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final AnalyticsState state;
  const _Header({required this.state});

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final scheme = AppTheme.colorsOf(context);
    final total = state is AnalyticsLoaded
        ? (state as AnalyticsLoaded).students.length
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: Row(
        children: [
          Text('学情统计', style: text.titleLarge),
          const SizedBox(width: AppSpacing.sm),
          if (total != null)
            AppBadge(
              label: '$total 名学生',
              background: scheme.surfaceSunken,
              foreground: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

/// 加载 / 错误 / 空 态的居中展示。
class _CenterState extends StatelessWidget {
  final AnalyticsState state;
  const _CenterState({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state is AnalyticsLoading || state is AnalyticsInitial) {
      return const Center(child: AppLoading());
    }
    if (state is AnalyticsError) {
      return Center(
        child: AppError(
          message: (state as AnalyticsError).message,
          onRetry: () {},
        ),
      );
    }
    return const Center(
      child: AppEmptyState(
        icon: LucideIcons.barChart3,
        title: '暂无数据',
        message: '派发并作答任务后，这里会汇总错题、正确率与掌握度。',
      ),
    );
  }
}

class _LoadedBody extends StatelessWidget {
  final AnalyticsLoaded state;
  final AnalyticsNotifier notifier;
  const _LoadedBody({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.lg),
      children: [
        _Controls(
          state: state,
          onScope: notifier.setScope,
          onDimension: notifier.setDimension,
          onClass: notifier.setClass,
          onStudent: notifier.setStudent,
        ),
        const SizedBox(height: AppSpacing.md),
        _WrongDistributionCard(resp: state.wrong),
        const SizedBox(height: AppSpacing.md),
        _AccuracyCard(resp: state.accuracy),
        const SizedBox(height: AppSpacing.md),
        _MasteryCard(resp: state.mastery),
      ],
    );
  }
}

/// 控制条：作用域三态 + 条件选择器 + 四维切换。
class _Controls extends StatelessWidget {
  final AnalyticsLoaded state;
  final void Function(String) onScope;
  final void Function(String) onDimension;
  final void Function(String?) onClass;
  final void Function(String?) onStudent;

  const _Controls({
    required this.state,
    required this.onScope,
    required this.onDimension,
    required this.onClass,
    required this.onStudent,
  });

  static const _scopes = [
    ('all', '全体学生'),
    ('class', '单个班级'),
    ('student', '单个学生'),
  ];
  static const _dims = [
    ('subject', '学科'),
    ('grade', '年级'),
    ('semester', '学期'),
    ('knowledge_point', '知识点'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle('统计范围'),
          _ChipRow(
            options: _scopes,
            selected: state.scope,
            onTap: onScope,
          ),
          if (state.scope == 'class') ...[
            const SizedBox(height: AppSpacing.sm),
            AppPickerField<String>(
              label: '选择班级',
              values: state.classes.map((c) => c.id).toList(),
              labels: state.classes.map((c) => '${c.name}（${c.studentCount}人）').toList(),
              value: state.classId,
              placeholder: '选择班级',
              onChanged: (v) => onClass(v),
            ),
          ] else if (state.scope == 'student') ...[
            const SizedBox(height: AppSpacing.sm),
            AppPickerField<String>(
              label: '选择学生',
              values: state.students.map((s) => s.id).toList(),
              labels:
                  state.students.map((s) => '${s.displayName}（${s.username}）').toList(),
              value: state.studentId,
              placeholder: '选择学生',
              onChanged: (v) => onStudent(v),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          SectionTitle('分组维度'),
          _ChipRow(
            options: _dims,
            selected: state.dimension,
            onTap: onDimension,
          ),
          if (state.dimension == 'grade') ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '年级按「题目」归类（即试卷所属年级），非学生当前所在年级。',
              style: AppTheme.textOf(context)
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单选 chip 行（作用域 / 维度共用）。[options] 为 (value, label) 元组列表。
class _ChipRow extends StatelessWidget {
  final List<(String, String)> options;
  final String selected;
  final void Function(String) onTap;

  const _ChipRow({
    required this.options,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: AppChip(
                label: label,
                selected: selected == value,
                onTap: () => onTap(value),
              ),
            ),
        ],
      ),
    );
  }
}

/// 错题分布卡片。
class _WrongDistributionCard extends StatelessWidget {
  final WrongDistributionResp resp;
  const _WrongDistributionCard({required this.resp});

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final scheme = AppTheme.colorsOf(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            '错题分布',
            trailing: AppBadge(
              label: '共 ${resp.total} 道',
              background: scheme.surfaceSunken,
              foreground: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '活跃 ${resp.totalActive} · 已毕业 ${resp.totalGraduated}',
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (resp.groups.isEmpty && resp.orphanCount == 0)
            _EmptyHint(text: '本范围暂无错题。')
          else
            for (final g in resp.groups)
              _MetricRow(
                label: g.group,
                value: '${g.active + g.graduated} 道',
                caption: '活跃 ${g.active} / 已毕业 ${g.graduated}',
              ),
          if (resp.orphanCount > 0)
            _MetricRow(
              label: '未知（原题已删除）',
              value: '${resp.orphanCount} 道',
              caption: '孤儿错题，无法归入任何分组',
              warn: true,
            ),
        ],
      ),
    );
  }
}

/// 正确率卡片。
class _AccuracyCard extends StatelessWidget {
  final AccuracyResp resp;
  const _AccuracyCard({required this.resp});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            '正确率',
            trailing: AppBadge(
              label: '练习+复习',
              background: scheme.surfaceSunken,
              foreground: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (resp.groups.isEmpty && resp.orphanCount == 0)
            _EmptyHint(text: '本范围暂无作答记录。')
          else
            for (final g in resp.groups)
              _MetricRow(
                label: g.group,
                value: _pct(g.overall.accuracy),
                caption:
                    '练习 ${_pct(g.practice.accuracy)} · 复习 ${_pct(g.review.accuracy)}',
              ),
          if (resp.orphanCount > 0)
            _MetricRow(
              label: '未知（原题已删除）',
              value: '—',
              caption: '孤儿作答 ${resp.orphanCount} 条，无法归入任何分组',
              warn: true,
            ),
        ],
      ),
    );
  }
}

/// 掌握度卡片。
class _MasteryCard extends StatelessWidget {
  final MasteryResp resp;
  const _MasteryCard({required this.resp});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            '掌握度',
            trailing: AppBadge(
              label: '已掌握 ${resp.masteredCount}/${resp.totalKnowledgePoints}',
              background: scheme.surfaceSunken,
              foreground: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (resp.items.isEmpty && resp.orphanCount == 0)
            _EmptyHint(text: '本范围暂无知识点掌握数据。')
          else
            for (final it in resp.items)
              _MetricRow(
                label: it.knowledgePoint,
                value: it.level.isEmpty ? _pct(it.accuracy) : it.level,
                caption:
                    '得分 ${it.score.toStringAsFixed(1)} · 活跃错题 ${it.activeWrong}',
              ),
          if (resp.orphanCount > 0)
            _MetricRow(
              label: '未知（原题已删除）',
              value: '—',
              caption: '孤儿错题 ${resp.orphanCount} 条，无法归入任何知识点',
              warn: true,
            ),
        ],
      ),
    );
  }
}

/// 单行指标：标签 + 主值 + 副说明。
class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final bool warn;

  const _MetricRow({
    required this.label,
    required this.value,
    required this.caption,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final scheme = AppTheme.colorsOf(context);
    final valueColor = warn ? scheme.error : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard.listRow(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: text.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Text(
              value,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        text,
        style: AppTheme.textOf(context)
            .labelSmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

String _pct(double v) => '${(v * 100).round()}%';
