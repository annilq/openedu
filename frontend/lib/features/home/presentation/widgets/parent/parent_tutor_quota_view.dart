import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../children/domain/providers/children_provider.dart';
import '../../../../children/presentation/providers/children_notifier.dart';
import '../../../../tutor/presentation/providers/tutor_notifier.dart';
import '../../../../tutor/presentation/screens/tutor_quota_screen.dart';
import '../../providers/selected_child_provider.dart';

/// AI 使用管控右栏视图（T10，故事 23/26）。
class ParentTutorQuotaView extends ConsumerWidget {
  const ParentTutorQuotaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedChildProvider);
    if (selected == null) {
      return _emptyState(context, ref);
    }

    final scheme = AppTheme.colorsOf(context);
    final quotaState = ref.watch(tutorQuotaNotifierProvider(selected.id));
    final usageState = ref.watch(tutorUsageNotifierProvider(selected.id));

    final childrenState = ref.watch(childrenNotifierProvider);
    String childName = '';
    if (childrenState is ChildrenLoaded) {
      for (final c in childrenState.children) {
        if (c.id == selected.id) childName = c.displayName;
      }
    }

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
              SectionTitle('AI 使用管控',
                  trailing: ShadButton.ghost(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TutorQuotaScreen(
                          childId: selected.id,
                          childName: childName,
                        ),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.slidersHorizontal, size: 20),
                        SizedBox(width: AppSpacing.xs),
                        Text('设置'),
                      ],
                    ),
                  )),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Icon(LucideIcons.timer,
                            size: 24, color: scheme.onSecondaryContainer),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              switch (quotaState) {
                                TutorQuotaLoaded() =>
                                  quotaSummary(quotaState.quota),
                                TutorQuotaError() =>
                                  '加载失败：${quotaState.message}',
                                _ => '加载中…',
                              },
                              style: AppTheme.textOf(context).bodyMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs2),
                            Text(
                              switch (usageState) {
                                TutorUsageLoaded() =>
                                  usageSummary(usageState.usage),
                                TutorUsageError() => '用量加载失败',
                                _ => '今日用量加载中…',
                              },
                              style: AppTheme.textOf(context).bodySmall,
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
      ),
    );
  }

  Widget _emptyState(BuildContext context, WidgetRef ref) {
    final scheme = AppTheme.colorsOf(context);
    return Center(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.xl3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Icon(LucideIcons.timer,
                  size: 28, color: scheme.onSecondaryContainer),
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

/// 额度摘要文本（家长端 + selected_child_provider 共用）。
String quotaSummary(TutorQuotaModel quota) {
  final parts = <String>[];
  parts.add(quota.dailyAskLimit != null
      ? '每日提问上限 ${quota.dailyAskLimit} 次'
      : '每日提问按全局默认上限');
  parts.add(quota.dailyMinutesLimit != null
      ? '时长上限 ${quota.dailyMinutesLimit} 分钟'
      : '时长不限');
  parts.add(quota.allowedSubjects != null && quota.allowedSubjects!.isNotEmpty
      ? '仅允许 ${quota.allowedSubjects!.join('、')}'
      : '学科不限');
  return parts.join(' · ');
}

/// 用量摘要文本（家长端 + selected_child_provider 共用）。
String usageSummary(TutorUsageModel usage) {
  final minutes = (usage.usedSeconds / 60).toStringAsFixed(1);
  final asks = usage.askLimit != null
      ? '${usage.asksToday}/${usage.askLimit} 次'
      : '${usage.asksToday} 次';
  final time = usage.minutesLimit != null
      ? '$minutes/${usage.minutesLimit} 分钟'
      : '$minutes 分钟';
  return '今日已用：提问 $asks · 时长 $time';
}
