import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_option_tile.dart';

/// 做题页单题作答区：题干标签 + 选项/输入 + 提交。
/// 纯展示：选中态/答案/提交由调用方（屏幕 State）持有并回调。
class PracticeQuestionView extends StatelessWidget {
  final QuestionModel question;
  final TaskModel task;
  final String? selectedOption;
  final TextEditingController answerController;
  final bool answerReady;
  final ValueChanged<String> onOptionTap;
  final VoidCallback onAnswerChanged;
  final VoidCallback onSubmit;

  const PracticeQuestionView({
    super.key,
    required this.question,
    required this.task,
    required this.selectedOption,
    required this.answerController,
    required this.answerReady,
    required this.onOptionTap,
    required this.onAnswerChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final q = question;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  // ADR-0004：学科下沉到题，从当前题取字段。
                  if (q.subject.isNotEmpty)
                    AppTags.subject(SubjectAccent.fromName(q.subject)),
                  if (q.grade > 0) AppTags.normal('${q.grade}年级'),
                  if (q.knowledgePoint.isNotEmpty)
                    AppTags.info(q.knowledgePoint),
                ],
              ),
              const SizedBox(height: AppSpacing.xl3),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.xl2),
                decoration: BoxDecoration(
                  color: scheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadius.banner),
                ),
                child: Text(q.stem, style: AppTheme.textOf(context).titleMedium),
              ),
              const SizedBox(height: AppSpacing.xl3),
              if (q.options != null && q.options!.isNotEmpty)
                ...q.options!.asMap().entries.map((e) => AppOptionTile(
                      index: e.key,
                      text: e.value,
                      selected: selectedOption == e.value,
                      onTap: () => onOptionTap(e.value),
                    ))
              else
                AppTextField(
                  label: '你的答案',
                  controller: answerController,
                  hintText: '在此填写...',
                  onChanged: (_) => onAnswerChanged(),
                ),
              const SizedBox(height: AppSpacing.xl4),
              AppPrimaryButton(
                label: '提交答案',
                icon: LucideIcons.send,
                onPressed: answerReady ? onSubmit : null,
                height: 52,
                fullWidth: false,
              ),
              if (!answerReady)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Center(
                    child: Text('请先选择或输入答案再提交',
                        style: AppTheme.textOf(context).labelSmall),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
