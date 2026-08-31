import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../providers/tutor_notifier.dart';
import '../widgets/tutor_quota_form.dart';
import '../widgets/tutor_usage_card.dart';

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

  void _toggleSubject(String s) {
    setState(() {
      if (_selectedSubjects.contains(s)) {
        _selectedSubjects.remove(s);
      } else {
        _selectedSubjects.add(s);
      }
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

    return SizedBox.expand(
      child: ColoredBox(
        color: scheme.surface,
        child: Column(
          children: [
            AppTopBar(
              title: '${widget.childName} · AI 使用管控',
              showBack: true,
            ),
            Expanded(
              child: switch (quotaState) {
                TutorQuotaInitial() || TutorQuotaLoading() =>
                  const AppLoading(message: '加载设置...'),
                TutorQuotaError() => AppError(
                    message: quotaState.message,
                    onRetry: () {
                      ref
                          .read(
                              tutorQuotaNotifierProvider(widget.childId).notifier)
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
                              TutorUsageCard(usageState: usageState),
                              const SizedBox(height: AppSpacing.xl3),
                              TutorQuotaForm(
                                askLimitCtrl: _askLimitCtrl,
                                minutesLimitCtrl: _minutesLimitCtrl,
                                selectedSubjects: _selectedSubjects,
                                onToggleSubject: _toggleSubject,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: scheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(LucideIcons.info,
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
                              AppPrimaryButton(
                                label: '保存设置',
                                icon: LucideIcons.check,
                                loadingLabel: '保存中…',
                                loading: _saving,
                                onPressed: _save,
                                height: 52,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}
