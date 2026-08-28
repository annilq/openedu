import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../providers/home_notifier.dart';
import '../../providers/selected_child_provider.dart';
import '../../../../review/presentation/providers/review_notifier.dart';

/// 布置练习任务右栏：多学科行表单 + 一键均分 + 生成（ADR-0004）。
/// R3：生成成功后不直接跳娃娃练习页，回调 `onNavigateToReview` 进草稿审核页。
class ParentTaskFormView extends ConsumerStatefulWidget {
  final void Function(TaskModel task) onNavigateToReview;
  const ParentTaskFormView({super.key, required this.onNavigateToReview});

  @override
  ConsumerState<ParentTaskFormView> createState() => _ParentTaskFormViewState();
}

/// 一行学科规格（学科 + 知识点 + 题型 + 难度 + 题量 + 年级）。
class _SpecRow {
  final TextEditingController subject;
  final TextEditingController knowledgePoint;
  final TextEditingController count;
  String qtype = 'calc';
  int grade = 2;

  _SpecRow({
    String? subject,
    String? knowledgePoint,
    String? count,
  })  : subject = TextEditingController(text: subject ?? '数学'),
        knowledgePoint =
            TextEditingController(text: knowledgePoint ?? '两位数加减法'),
        count = TextEditingController(text: count ?? '5');

  void dispose() {
    subject.dispose();
    knowledgePoint.dispose();
    count.dispose();
  }

  TaskSpecModel toSpec() => TaskSpecModel(
        subject: subject.text,
        grade: grade,
        knowledgePoint: knowledgePoint.text,
        qtype: qtype,
        count: int.tryParse(count.text) ?? 1,
      );
}

class _ParentTaskFormViewState extends ConsumerState<ParentTaskFormView> {
  final List<_SpecRow> _rows = [_SpecRow()];
  final _totalCtrl = TextEditingController(text: '10');
  final _titleCtrl = TextEditingController(text: '今日练习');

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _totalCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_SpecRow(
        subject: '语文',
        knowledgePoint: '字词积累',
      )));

  void _removeRow(int i) => setState(() {
        if (_rows.length > 1) {
          _rows[i].dispose();
          _rows.removeAt(i);
        }
      });

  /// 一键均分（ADR-0004 D5）：总题数按当前行数等分，余数给前几行。
  void _evenSplit() {
    final total = int.tryParse(_totalCtrl.text) ?? 10;
    final n = _rows.length;
    if (n == 0) return;
    final base = total ~/ n;
    final extra = total % n;
    setState(() {
      for (var i = 0; i < n; i++) {
        _rows[i].count.text = (base + (i < extra ? 1 : 0)).toString();
      }
    });
  }

  void _generate() {
    final selected = ref.read(selectedChildProvider);
    if (selected == null) {
      AppToast.show(context, '请先在侧栏选择娃娃');
      return;
    }
    final specs = _rows.map((r) => r.toSpec()).toList();
    if (specs.any((s) => s.subject.isEmpty || s.knowledgePoint.isEmpty)) {
      AppToast.show(context, '学科与知识点不能为空');
      return;
    }
    if (specs.any((s) => s.count < 1)) {
      AppToast.show(context, '每行题数至少为 1');
      return;
    }
    ref.read(taskGenNotifierProvider.notifier).generate(
          childId: selected.id,
          title: _titleCtrl.text,
          specs: specs,
        );
  }

  @override
  Widget build(BuildContext context) {
    final genState = ref.watch(taskGenNotifierProvider);

    ref.listen<TaskGenState>(taskGenNotifierProvider, (prev, next) {
      // 推迟到下一帧：避免在 build 阶段同步弹 toast + 跳转，
      // 导致 widget tree 在 shadcn_ui toast SlideEffect 动画中途销毁，
      // padding 计算拿到 NaN 触发 isNonNegative 断言。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (next is TaskGenSuccess) {
          AppToast.show(context, '已生成 ${next.task.questions.length} 道题');
          ref.read(taskGenNotifierProvider.notifier).reset();
          final selected = ref.read(selectedChildProvider);
          if (selected != null) {
            ref.read(progressNotifierProvider.notifier).load(selected.id);
            ref.read(masteryNotifierProvider.notifier).load(selected.id);
            ref
                .read(parentWrongQuestionsProvider.notifier)
                .load(childId: selected.id);
          }
          widget.onNavigateToReview(next.task);
        }
        if (next is TaskGenError) {
          AppToast.error(context, next.message);
        }
      });
    });

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
              const SectionTitle('布置练习任务'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(label: '试卷标题', controller: _titleCtrl),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              label: '总题数',
                              controller: _totalCtrl,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          TextButton(
                            onPressed: _evenSplit,
                            child: const Text('一键均分'),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          TextButton(
                            onPressed: _addRow,
                            child: const Text('+ 加学科'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ...List.generate(_rows.length, _buildRow),
                      const SizedBox(height: AppSpacing.xl),
                      if (genState is TaskGenLoading)
                        const AppLoading()
                      else
                        AppPrimaryButton(label: '生成任务', onPressed: _generate),
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

  Widget _buildRow(int i) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: AppTextField(label: '学科', controller: _rows[i].subject),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 3,
              child: AppTextField(
                  label: '知识点', controller: _rows[i].knowledgePoint),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: AppPickerField<String>(
                label: '题型',
                values: const ['calc', 'fill', 'choice', 'open'],
                labels: const ['计算', '填空', '选择', '应用'],
                value: _rows[i].qtype,
                onChanged: (v) => setState(() => _rows[i].qtype = v),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: AppTextField(
                label: '题数',
                controller: _rows[i].count,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: AppPickerField<int>(
                label: '年级',
                values: List.generate(9, (j) => j + 1),
                labels: List.generate(9, (j) => '${j + 1}年级'),
                value: _rows[i].grade,
                onChanged: (v) => setState(() => _rows[i].grade = v),
              ),
            ),
            if (_rows.length > 1) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => _removeRow(i),
                tooltip: '删除该行',
              ),
            ],
          ],
        ),
      );
}
