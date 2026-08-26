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

/// 布置练习任务右栏：题型/学科/知识点/题数/年级表单 + 生成按钮。
class ParentTaskFormView extends ConsumerStatefulWidget {
  final void Function(TaskModel task) onNavigateToPractice;
  const ParentTaskFormView({super.key, required this.onNavigateToPractice});

  @override
  ConsumerState<ParentTaskFormView> createState() => _ParentTaskFormViewState();
}

class _ParentTaskFormViewState extends ConsumerState<ParentTaskFormView> {
  final _subjectCtrl = TextEditingController(text: '数学');
  final _kpCtrl = TextEditingController(text: '两位数加减法');
  final _countCtrl = TextEditingController(text: '5');
  String _selectedQtype = 'calc';
  int _selectedGrade = 2;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _kpCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  void _generate() {
    final selected = ref.read(selectedChildProvider);
    if (selected == null) {
      AppToast.show(context, '请先在侧栏选择娃娃');
      return;
    }
    ref.read(taskGenNotifierProvider.notifier).generate(
          childId: selected.id,
          subject: _subjectCtrl.text,
          grade: _selectedGrade,
          knowledgePoint: _kpCtrl.text,
          qtype: _selectedQtype,
          count: int.tryParse(_countCtrl.text) ?? 5,
        );
  }

  @override
  Widget build(BuildContext context) {
    final genState = ref.watch(taskGenNotifierProvider);

    ref.listen<TaskGenState>(taskGenNotifierProvider, (prev, next) {
      if (next is TaskGenSuccess) {
        AppToast.show(context, '已生成 ${next.task.count} 道题，可见答案用于核查');
        ref.read(taskGenNotifierProvider.notifier).reset();
        final selected = ref.read(selectedChildProvider);
        if (selected != null) {
          ref.read(progressNotifierProvider.notifier).load(selected.id);
          ref.read(masteryNotifierProvider.notifier).load(selected.id);
          ref.read(parentWrongQuestionsProvider.notifier).load(childId: selected.id);
        }
        widget.onNavigateToPractice(next.task);
      }
      if (next is TaskGenError) {
        AppToast.error(context, next.message);
      }
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
                      AppPickerField<String>(
                        label: '题型',
                        values: const ['calc', 'fill', 'choice', 'open'],
                        labels: const ['计算题', '填空题', '选择题', '应用题'],
                        value: _selectedQtype,
                        onChanged: (v) => setState(() => _selectedQtype = v),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(label: '学科', controller: _subjectCtrl),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(label: '知识点', controller: _kpCtrl),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              label: '题数',
                              controller: _countCtrl,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xl),
                          Expanded(
                            child: AppPickerField<int>(
                              label: '年级',
                              values: List.generate(9, (i) => i + 1),
                              labels: List.generate(9, (i) => '${i + 1}年级'),
                              value: _selectedGrade,
                              onChanged: (v) => setState(() => _selectedGrade = v),
                            ),
                          ),
                        ],
                      ),
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
}
