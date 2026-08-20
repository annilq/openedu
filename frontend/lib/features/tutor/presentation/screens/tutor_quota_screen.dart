import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../providers/tutor_notifier.dart';

/// 家长端：AI 使用管控设置页（T10，故事 23/26）。
///
/// 三项管控（整体覆盖保存，留空 = 不限制该 item）：
/// - 每日提问条数上限（默认走全局 50 次）
/// - 每日使用时长上限（分钟，按服务端累计答疑耗时）
/// - 允许提问的学科（多选，全不选 = 不限）
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

  /// 首次加载成功后把已有配置回填到表单。
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
    // 非空但非法的数字输入不静默忽略，明确提示
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
      // 同步刷新用量展示（限额变了，剩余量随之变化）
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
    final quotaState = ref.watch(tutorQuotaNotifierProvider(widget.childId));
    final usageState = ref.watch(tutorUsageNotifierProvider(widget.childId));

    // 配置加载成功后回填表单（仅首次）
    ref.listen<TutorQuotaState>(
      tutorQuotaNotifierProvider(widget.childId),
      (prev, next) {
        if (next is TutorQuotaLoaded) _syncForm(next.quota);
      },
    );

    return Scaffold(
      appBar: AppBar(title: Text('${widget.childName} · AI 使用管控')),
      body: switch (quotaState) {
        TutorQuotaInitial() || TutorQuotaLoading() => const Center(
            child: CircularProgressIndicator(),
          ),
        TutorQuotaError() => Center(child: Text(quotaState.message)),
        TutorQuotaLoaded() => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildUsageCard(usageState),
              const SizedBox(height: 24),
              _buildForm(context),
              const SizedBox(height: 8),
              Text(
                '提示：0 表示今日禁用 AI 答疑；留空表示不限制（次数留空走全局默认上限）。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
      },
    );
  }

  Widget _buildUsageCard(TutorUsageState usageState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日已用', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            switch (usageState) {
              TutorUsageLoaded() => Text(
                  '提问 ${usageState.usage.asksToday}'
                  '${usageState.usage.askLimit != null ? ' / ${usageState.usage.askLimit} 次' : ' 次'}'
                  '　·　时长 ${(usageState.usage.usedSeconds / 60).toStringAsFixed(1)}'
                  '${usageState.usage.minutesLimit != null ? ' / ${usageState.usage.minutesLimit} 分钟' : ' 分钟'}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              TutorUsageError() => Text(usageState.message),
              _ => const Text('…'),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _askLimitCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每日提问上限（次，留空不限）',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minutesLimitCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每日使用时长上限（分钟，留空不限）',
              ),
            ),
            const SizedBox(height: 16),
            Text('允许提问的学科（不选 = 不限）',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _subjects
                  .map((s) => FilterChip(
                        label: Text(s),
                        selected: _selectedSubjects.contains(s),
                        onSelected: (v) => setState(() {
                          v ? _selectedSubjects.add(s)
                            : _selectedSubjects.remove(s);
                        }),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
