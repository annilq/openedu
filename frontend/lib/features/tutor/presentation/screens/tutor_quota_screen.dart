import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
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
      AppToast.show(context, '上限必须是数字（留空表示不限制）');
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
      AppToast.show(context, '已保存 AI 使用管控');
    } else {
      AppToast.error(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final quotaState = ref.watch(tutorQuotaNotifierProvider(widget.childId));
    final usageState = ref.watch(tutorUsageNotifierProvider(widget.childId));

    ref.listen<TutorQuotaState>(
      tutorQuotaNotifierProvider(widget.childId),
      (prev, next) {
        if (next is TutorQuotaLoaded) _syncForm(next.quota);
      },
    );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        middle: Text('${widget.childName} · AI 使用管控'),
      ),
      child: switch (quotaState) {
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
                            Icon(CupertinoIcons.info_circle,
                                size: 20,
                                color: scheme.onSecondaryContainer),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                '提示：0 表示今日禁用 AI 答疑；留空表示不限制（次数留空走全局默认上限）。',
                                style: text.labelSmall?.copyWith(
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
                        child: CupertinoButton.filled(
                          borderRadius:
                              BorderRadius.circular(AppRadius.button),
                          onPressed: _saving ? null : _save,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _saving
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CupertinoActivityIndicator(
                                          color: scheme.onPrimary, radius: 8),
                                    )
                                  : Icon(CupertinoIcons.checkmark,
                                      size: 18, color: scheme.onPrimary),
                              const SizedBox(width: 8),
                              Text(
                                _saving ? '保存中…' : '保存设置',
                                style: text.labelLarge
                                    ?.copyWith(color: scheme.onPrimary),
                              ),
                            ],
                          ),
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
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      margin: const EdgeInsets.symmetric(vertical: 6),
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
                child: Icon(CupertinoIcons.chart_bar,
                    size: 22, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text('今日已用', style: text.titleSmall),
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
                  style: text.bodyLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              TutorUsageError() => Text(usageState.message,
                  style: TextStyle(color: scheme.error)),
              _ => Text('今日用量加载中…',
                  style: text.bodyMedium),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CupertinoTextField(
            controller: _askLimitCtrl,
            keyboardType: TextInputType.number,
            placeholder: '每日提问上限（次，留空不限）',
            placeholderStyle:
                text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            style: text.bodyMedium,
            prefix: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Icon(CupertinoIcons.list_number,
                  color: scheme.onSurfaceVariant, size: 20),
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: scheme.outline, width: 1),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          CupertinoTextField(
            controller: _minutesLimitCtrl,
            keyboardType: TextInputType.number,
            placeholder: '每日使用时长上限（分钟，留空不限）',
            placeholderStyle:
                text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            style: text.bodyMedium,
            prefix: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Icon(CupertinoIcons.timer,
                  color: scheme.onSurfaceVariant, size: 20),
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: scheme.outline, width: 1),
            ),
          ),
          const SizedBox(height: AppSpacing.xl2),
          Text('允许提问的学科（不选 = 不限）',
              style: text.titleSmall),
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
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 1.5 : 0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(CupertinoIcons.checkmark,
                    size: 18, color: scheme.onPrimaryContainer),
              ),
            Text(label,
                style: text.labelMedium?.copyWith(
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}