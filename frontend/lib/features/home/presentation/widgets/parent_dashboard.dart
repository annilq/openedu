import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../children/domain/providers/children_provider.dart';
import '../../../children/presentation/providers/children_notifier.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../../../tutor/presentation/providers/tutor_notifier.dart';
import '../../../tutor/presentation/screens/tutor_quota_screen.dart';
import '../providers/home_notifier.dart';

/// 家长端首页：娃娃列表 + 生成任务表单 + 进度看板
class ParentDashboard extends ConsumerStatefulWidget {
  final UserModel user;
  final void Function(TaskModel task) onNavigateToPractice;

  const ParentDashboard({
    super.key,
    required this.user,
    required this.onNavigateToPractice,
  });

  @override
  ConsumerState<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends ConsumerState<ParentDashboard> {
  final _subjectCtrl = TextEditingController(text: '数学');
  final _kpCtrl = TextEditingController(text: '两位数加减法');
  final _countCtrl = TextEditingController(text: '5');
  String _selectedQtype = 'calc';
  String _selectedChildId = '';
  int _selectedGrade = 2;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _kpCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  void _generate() {
    final childrenState = ref.read(childrenNotifierProvider);
    if (childrenState is! ChildrenLoaded || childrenState.children.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建娃娃账号')),
      );
      return;
    }
    if (_selectedChildId.isEmpty) {
      _selectedChildId = childrenState.children.first.id;
    }
    ref.read(taskGenNotifierProvider.notifier).generate(
          childId: _selectedChildId,
          subject: _subjectCtrl.text,
          grade: _selectedGrade,
          knowledgePoint: _kpCtrl.text,
          qtype: _selectedQtype,
          count: int.tryParse(_countCtrl.text) ?? 5,
        );
  }

  void _selectChild(String id, int grade) {
    setState(() {
      _selectedChildId = id;
      _selectedGrade = grade;
    });
    ref.read(progressNotifierProvider.notifier).load(id);
    ref.read(masteryNotifierProvider.notifier).load(id);
    ref.read(parentWrongQuestionsProvider.notifier).load(childId: id);
    ref.read(tutorLogsNotifierProvider.notifier).load(childId: id);
    ref.read(tutorQuotaNotifierProvider(id).notifier).load(childId: id);
    ref.read(tutorUsageNotifierProvider(id).notifier).load(childId: id);
  }

  @override
  Widget build(BuildContext context) {
    final childrenState = ref.watch(childrenNotifierProvider);
    final genState = ref.watch(taskGenNotifierProvider);

    // 监听生成结果
    ref.listen<TaskGenState>(taskGenNotifierProvider, (prev, next) {
      if (next is TaskGenSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已生成 ${next.task.count} 道题，可见答案用于核查')),
        );
        ref.read(taskGenNotifierProvider.notifier).reset();
        // 刷新进度
        if (_selectedChildId.isNotEmpty) {
          ref.read(progressNotifierProvider.notifier).load(_selectedChildId);
          ref.read(masteryNotifierProvider.notifier).load(_selectedChildId);
          ref.read(parentWrongQuestionsProvider.notifier)
              .load(childId: _selectedChildId);
        }
      }
      if (next is TaskGenError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.message)),
        );
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // —— 娃娃列表 ——
          Text('我的娃娃', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildChildrenSection(childrenState),

          const SizedBox(height: 32),

          // —— 生成任务表单 ——
          Text('布置练习任务', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _buildGenForm(childrenState),

          if (genState is TaskGenLoading)
            const Padding(padding: EdgeInsets.all(16), child: AppLoading()),

          const SizedBox(height: 32),

          // —— 进度看板 ——
          if (_selectedChildId.isNotEmpty) _buildProgressSection(),

          const SizedBox(height: 32),

          // —— 掌握度看板 ——
          if (_selectedChildId.isNotEmpty) _buildMasterySection(),

          const SizedBox(height: 32),

          // —— 错题本 ——
          if (_selectedChildId.isNotEmpty) _buildParentWrongSection(),

          const SizedBox(height: 32),

          // —— AI 答疑日志（家长可查，F-305）——
          if (_selectedChildId.isNotEmpty) _buildTutorLogsSection(),

          const SizedBox(height: 32),

          // —— AI 使用管控（T10，故事 23/26）——
          if (_selectedChildId.isNotEmpty) _buildTutorQuotaSection(),
        ],
      ),
    );
  }

  Widget _buildChildrenSection(ChildrenState state) {
    return switch (state) {
      ChildrenInitial() || ChildrenLoading() => const AppLoading(message: '加载娃娃...'),
      ChildrenError() => AppError(
          message: state.message,
          onRetry: () => ref.read(childrenNotifierProvider.notifier).loadChildren(),
        ),
      ChildrenLoaded() => state.children.isEmpty
          ? const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('还没有娃娃账号\n在下方注册一个娃娃账号'),
              ),
            )
          : Wrap(
              spacing: 12,
              runSpacing: 12,
              children: state.children.map((c) {
                final isSelected = _selectedChildId == c.id;
                return ChoiceChip(
                  label: Text('${c.displayName} · ${c.grade ?? '?'}年级'),
                  selected: isSelected,
                  onSelected: (_) => _selectChild(c.id, c.grade ?? 2),
                );
              }).toList(),
            ),
    };
  }

  Widget _buildGenForm(ChildrenState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedQtype,
              decoration: const InputDecoration(labelText: '题型'),
              items: const [
                DropdownMenuItem(value: 'calc', child: Text('计算题')),
                DropdownMenuItem(value: 'fill', child: Text('填空题')),
                DropdownMenuItem(value: 'choice', child: Text('选择题')),
                DropdownMenuItem(value: 'open', child: Text('应用题')),
              ],
              onChanged: (v) => setState(() => _selectedQtype = v ?? 'calc'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subjectCtrl,
              decoration: const InputDecoration(labelText: '学科'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _kpCtrl,
              decoration: const InputDecoration(labelText: '知识点'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _countCtrl,
                    decoration: const InputDecoration(labelText: '题数'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedGrade,
                    decoration: const InputDecoration(labelText: '年级'),
                    items: List.generate(9, (i) => i + 1)
                        .map((g) => DropdownMenuItem(
                              value: g,
                              child: Text('$g年级'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedGrade = v ?? 2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _generate,
                child: const Text('生成任务'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    final progState = ref.watch(progressNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('学习进度', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        switch (progState) {
          ProgressInitial() || ProgressLoading() =>
            const AppLoading(message: '加载进度...'),
          ProgressError() => AppError(message: progState.message),
          ProgressLoaded() => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _stat('总题数', '${progState.progress.total}'),
                    _stat('答对', '${progState.progress.correct}'),
                    _stat('正确率', '${(progState.progress.accuracy * 100).round()}%'),
                    _stat('连续打卡', '${progState.progress.streakDays}天'),
                  ],
                ),
              ),
            ),
        },
      ],
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  // —— 掌握度看板 ——
  Widget _buildMasterySection() {
    final state = ref.watch(masteryNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('知识点掌握度', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        switch (state) {
          MasteryInitial() || MasteryLoading() =>
            const AppLoading(message: '加载掌握度...'),
          MasteryError() => AppError(message: state.message),
          MasteryLoaded() => state.mastery.items.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('还没有作答记录，先布置任务吧'),
                  ),
                )
              : Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已掌握 ${state.mastery.masteredCount} / ${state.mastery.totalKnowledgePoints} 个知识点',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 16),
                        ...state.mastery.items
                            .map((m) => _MasteryBar(item: m)),
                      ],
                    ),
                  ),
                ),
        },
      ],
    );
  }

  // —— 家长错题本 ——
  Widget _buildParentWrongSection() {
    final state = ref.watch(parentWrongQuestionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('错题本', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        switch (state) {
          WrongQuestionsInitial() || WrongQuestionsLoading() =>
            const AppLoading(message: '加载错题...'),
          WrongQuestionsError() => AppError(message: state.message),
          WrongQuestionsLoaded() => state.items.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('暂无错题'),
                  ),
                )
              : Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: state.items
                          .map((item) => _ParentWrongCard(item: item))
                          .toList(),
                    ),
                  ),
                ),
        },
      ],
    );
  }

  // —— AI 答疑日志（家长可查，F-305）——
  Widget _buildTutorLogsSection() {    final state = ref.watch(tutorLogsNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI 答疑记录', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        switch (state) {
          TutorLogsInitial() || TutorLogsLoading() =>
            const AppLoading(message: '加载答疑记录...'),
          TutorLogsError() => AppError(message: state.message),
          TutorLogsLoaded() => state.logs.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('这个娃娃还没有问过 AI 老师'),
                  ),
                )
              : Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: state.logs
                          .map((log) => _TutorLogCard(log: log))
                          .toList(),
                    ),
                  ),
                ),
        },
      ],
    );
  }

  // —— AI 使用管控（T10，故事 23/26）——
  Widget _buildTutorQuotaSection() {
    final quotaState = ref.watch(tutorQuotaNotifierProvider(_selectedChildId));
    final usageState = ref.watch(tutorUsageNotifierProvider(_selectedChildId));

    // 取当前选中娃娃的昵称做设置页标题
    final childrenState = ref.read(childrenNotifierProvider);
    String childName = '';
    if (childrenState is ChildrenLoaded) {
      for (final c in childrenState.children) {
        if (c.id == _selectedChildId) childName = c.displayName;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child:
                  Text('AI 使用管控', style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TutorQuotaScreen(
                    childId: _selectedChildId,
                    childName: childName,
                  ),
                ),
              ),
              child: const Text('设置'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  switch (quotaState) {
                    TutorQuotaLoaded() => _quotaSummary(quotaState.quota),
                    TutorQuotaError() => '加载失败：${quotaState.message}',
                    _ => '加载中…',
                  },
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  switch (usageState) {
                    TutorUsageLoaded() => _usageSummary(usageState.usage),
                    TutorUsageError() => '用量加载失败',
                    _ => '今日用量加载中…',
                  },
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _quotaSummary(TutorQuotaModel quota) {
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

  String _usageSummary(TutorUsageModel usage) {
    final minutes = (usage.usedSeconds / 60).toStringAsFixed(1);
    final asks = usage.askLimit != null
        ? '${usage.asksToday}/${usage.askLimit} 次'
        : '${usage.asksToday} 次';
    final time = usage.minutesLimit != null
        ? '$minutes/${usage.minutesLimit} 分钟'
        : '$minutes 分钟';
    return '今日已用：提问 $asks · 时长 $time';
  }
}

class _MasteryBar extends StatelessWidget {
  final KnowledgeMasteryModel item;
  const _MasteryBar({required this.item});

  Color get _levelColor => switch (item.level) {
        '已掌握' => Colors.green,
        '较扎实' => Colors.lightGreen,
        '巩固中' => Colors.blue,
        '薄弱' => Colors.orange,
        '待加强' => Colors.red,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${item.subject} · ${item.knowledgePoint}',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              Text('${item.score.round()}分',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 8),
              Chip(
                label: Text(item.level),
                labelStyle: TextStyle(
                    color: Colors.white, fontSize: 12),
                backgroundColor: _levelColor,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (item.score / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              color: _levelColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.activeWrong > 0
                ? '正确率 ${(item.accuracy * 100).round()}% · 有 ${item.activeWrong} 题待复习'
                : '正确率 ${(item.accuracy * 100).round()}% · 无待复习错题',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ParentWrongCard extends StatelessWidget {
  final WrongQuestionModel item;
  const _ParentWrongCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.stem, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Chip(label: Text(item.knowledgePoint)),
              Chip(label: Text('错过 ${item.wrongCount} 次')),
              Chip(label: Text('复习阶段 ${item.reviewStage}')),
            ],
          ),
          const SizedBox(height: 8),
          Text('标准答案：${item.answer ?? '—'}',
              style: const TextStyle(color: Colors.green)),
          if (item.explanation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('解析：${item.explanation}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}

class _TutorLogCard extends StatelessWidget {
  final TutorLogModel log;
  const _TutorLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('问：${log.question}',
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
              Chip(
                label: Text(log.blocked ? '已拦截' : '正常'),
                labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                backgroundColor: log.blocked ? Colors.orange : Colors.green,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('答：${log.answer}', style: Theme.of(context).textTheme.bodyMedium),
          const Divider(height: 24),
        ],
      ),
    );
  }
}
