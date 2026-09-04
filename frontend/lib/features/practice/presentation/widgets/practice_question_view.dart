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

  /// 家长只读预览模式：隐藏提交，改为本地「下一题」翻页（不写作答记录）。
  final bool preview;

  /// 只读预览下的翻页回调（交互态为 null）。
  final VoidCallback? onNext;

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
    this.preview = false,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final q = question;
    final total = task.questions.length;
    final currentIndex = task.questions.indexOf(q);
    final isLast = currentIndex < 0 || currentIndex >= total - 1;
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
                label: preview
                    ? (isLast ? '已是最后一题' : '下一题')
                    : '提交答案',
                icon: preview ? LucideIcons.arrowRight : LucideIcons.send,
                onPressed: preview
                    ? (isLast ? null : onNext)
                    : (answerReady ? onSubmit : null),
                height: 52,
                fullWidth: false,
              ),
              if (!preview && !answerReady)
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
