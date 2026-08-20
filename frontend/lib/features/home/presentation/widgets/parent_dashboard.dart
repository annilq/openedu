import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../children/domain/providers/children_provider.dart';
import '../../../children/presentation/providers/children_notifier.dart';
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
                  onSelected: (_) {
                    setState(() {
                      _selectedChildId = c.id;
                      _selectedGrade = c.grade ?? 2;
                    });
                    ref.read(progressNotifierProvider.notifier).load(c.id);
                  },
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
              value: _selectedQtype,
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
                    value: _selectedGrade,
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
}
