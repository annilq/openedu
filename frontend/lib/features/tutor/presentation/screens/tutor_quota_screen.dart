import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../providers/tutor_notifier.dart';

/// 家长端：AI 使用管控设置页。
/// v2 redesign：统一使用 AppLoading / AppError、用 AppTags 替代 FilterChip 的默认样式、
/// 空状态友好、SectionTitle 章节头。
class TutorQuotaScreen extends ConsumerStatefulWidget {
  final String childId;
  final String childName;

  const TutorQuotaScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  ConsumerState<TutorQuotaScreen> createState() => _TutorQuotaScreenState();
}

class _TutorQuotaScreenState extends ConsumerState<TutorQuotaScreen> {
  static const _subjects = ['数学', '语文', '英语'];

  final _askLimitCtrl = TextEditingController();
  final _minutesLimitCtrl = TextEditingController();
  final Set<String> _selectedSubjects = {};
  bool _saving = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(tutorQuotaNotifierProvider(widget.childId).notifier)
          .load(childId: widget.childId);
      ref
          .read(tutorUsageNotifierProvider(widget.childId).notifier)
          .load(childId: widget.childId);
    });
  }

  @override
  void dispose() {
    _askLimitCtrl.dispose();
    _minutesLimitCtrl.dispose();
    super.dispose();
  }

  void _syncForm(TutorQuotaModel quota) {
    if (_initialized) return;
    _initialized = true;
    setState(() {
      _askLimitCtrl.text = quota.dailyAskLimit?.toString() ?? '';
      _minutesLimitCtrl.text = quota.dailyMinutesLimit?.toString() ?? '';
      _selectedSubjects
        ..clear()
        ..addAll(quota.allowedSubjects ?? const []);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final askText = _askLimitCtrl.text.trim();
    final minutesText = _minutesLimitCtrl.text.trim();
    final askLimit = askText.isEmpty ? null : int.tryParse(askText);
    final minutesLimit =
        minutesText.isEmpty ? null : int.tryParse(minutesText);
    if ((askText.isNotEmpty && askLimit == null) ||
        (minutesText.isNotEmpty && minutesLimit == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('上限必须是数字（留空表示不限制）')),
      );
      return;
    }
    setState(() => _saving = true);
    final req = TutorQuotaUpdateReq(
      dailyAskLimit: askLimit,
      dailyMinutesLimit: minutesLimit,
      allowedSubjects:
          _selectedSubjects.isEmpty ? null : _selectedSubjects.toList(),
    );
    final error = await ref
        .read(tutorQuotaNotifierProvider(widget.childId).notifier)
        .save(childId: widget.childId, req: req);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      ref
          .read(tutorUsageNotifierProvider(widget.childId).notifier)
          .load(childId: widget.childId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存 AI 使用管控')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quotaState = ref.watch(tutorQuotaNotifierProvider(widget.childId));
    final usageState = ref.watch(tutorUsageNotifierProvider(widget.childId));

    ref.listen<TutorQuotaState>(
      tutorQuotaNotifierProvider(widget.childId),
      (prev, next) {
        if (next is TutorQuotaLoaded) _syncForm(next.quota);
      },
    );

    return Scaffold(
      appBar: AppBar(title: Text('${widget.childName} · AI 使用管控')),
      body: switch (quotaState) {
        TutorQuotaInitial() || TutorQuotaLoading() =>
          const AppLoading(message: '加载设置...'),
        TutorQuotaError() => AppError(
            message: quotaState.message,
            onRetry: () {
              ref
                  .read(tutorQuotaNotifierProvider(widget.childId).notifier)
                  .load(childId: widget.childId);
            },
          ),
        TutorQuotaLoaded() => ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl4),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildUsageCard(usageState),
                      const SizedBox(height: AppSpacing.xl3),
                      _buildForm(context),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 20,
                                color: scheme.onSecondaryContainer),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                '提示：0 表示今日禁用 AI 答疑；留空表示不限制（次数留空走全局默认上限）。',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                        color: scheme.onSecondaryContainer,
                                        fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl2),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.2, color: Colors.white),
                                )
                              : const Icon(Icons.save_rounded, size: 20),
                          label: Text(_saving ? '保存中…' : '保存设置'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      },
    );
  }

  Widget _buildUsageCard(TutorUsageState usageState) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.insights_rounded,
                      size: 22, color: scheme.onSecondaryContainer),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text('今日已用',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.only(left: 52),
              child: switch (usageState) {
                TutorUsageLoaded() => Text(
                    '提问 ${usageState.usage.asksToday}'
                    '${usageState.usage.askLimit != null ? ' / ${usageState.usage.askLimit} 次' : ' 次'}'
                    '　·　时长 ${(usageState.usage.usedSeconds / 60).toStringAsFixed(1)}'
                    '${usageState.usage.minutesLimit != null ? ' / ${usageState.usage.minutesLimit} 分钟' : ' 分钟'}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                TutorUsageError() => Text(usageState.message,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                _ => Text('今日用量加载中…',
                    style: Theme.of(context).textTheme.bodyMedium),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _askLimitCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每日提问上限（次，留空不限）',
                prefixIcon: Icon(Icons.format_list_numbered_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _minutesLimitCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每日使用时长上限（分钟，留空不限）',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.xl2),
            Text('允许提问的学科（不选 = 不限）',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _subjects.map((s) {
                final selected = _selectedSubjects.contains(s);
                return _SubjectToggle(
                  label: s,
                  selected: selected,
                  onTap: () => setState(() {
                    selected
                        ? _selectedSubjects.remove(s)
                        : _selectedSubjects.add(s);
                  }),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SubjectToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: selected ? 1.5 : 0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.check_rounded,
                      size: 18, color: scheme.onPrimaryContainer),
                ),
              Text(label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      )),
            ],
          ),
        ),
      ),
    );
  }
}
