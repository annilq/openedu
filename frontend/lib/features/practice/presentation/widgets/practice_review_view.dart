import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../widgets/practice_done_view.dart';

/// 提交后的订正阶段：汇总正确率 + 列出待订正错题 + 当场订正入口。
/// 无错题时复用 [PracticeDoneView] 成功态；有错题时提供「去订正」与最终「完成打卡」。
class PracticeReviewView extends StatelessWidget {
  final TaskModel task;
  final Map<String, AnswerResultModel> results;
  final ValueChanged<String> onCorrect;
  final VoidCallback onCommit;

  const PracticeReviewView({
    super.key,
    required this.task,
    required this.results,
    required this.onCorrect,
    required this.onCommit,
  });

  int get correctCount => results.values.where((r) => r.correct).length;
  int get total => task.questions.length;
  List<QuestionModel> get wrongQuestions => task.questions
      .where((q) => results[q.id]?.correct == false)
      .toList();

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);

    if (wrongQuestions.isEmpty) {
      // 全部答对（含订正后）：成功态。
      return PracticeDoneView(
        correct: correctCount,
        total: total,
        onCheckin: onCommit,
      );
    }

    final accuracy = total > 0 ? (correctCount / total * 100).round() : 0;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
            children: [
              // 汇总头
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl2),
                decoration: BoxDecoration(
                  color: scheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadius.banner),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('提交完成，看看哪里错了',
                        style: text.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '$correctCount / $total 正确 · 正确率 $accuracy%',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppProgressBar(
                      value: total > 0 ? correctCount / total : 0,
                      height: 10,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl2),
              // 待订正列表
              Row(
                children: [
                  Icon(LucideIcons.pencilLine,
                      size: 18, color: scheme.error),
                  const SizedBox(width: AppSpacing.sm),
                  Text('需要订正的题（${wrongQuestions.length}）',
                      style: text.titleSmall),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ...wrongQuestions.map((q) => _WrongToFixCard(
                    question: q,
                    onCorrect: () => onCorrect(q.id),
                  )),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '提示：能当场订正的尽量订正；实在不会再提交，错题会自动进入复习计划。',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        // 底部最终提交
        Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md,
              AppSpacing.lg, AppSpacing.xl2),
          decoration: BoxDecoration(
            color: scheme.surfaceRaised,
            border: Border(top: BorderSide(color: scheme.outline, width: 1)),
          ),
          child: AppPrimaryButton(
            label: '完成打卡 · 进入复习',
            icon: LucideIcons.checkCircle2,
            onPressed: onCommit,
            height: 52,
          ),
        ),
      ],
    );
  }
}

class _WrongToFixCard extends StatelessWidget {
  final QuestionModel question;
  final VoidCallback onCorrect;

  const _WrongToFixCard({required this.question, required this.onCorrect});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.stem,
            style: AppTheme.textOf(context).titleSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (question.subject.isNotEmpty)
                AppTags.subject(SubjectAccent.fromName(question.subject)),
              if (question.knowledgePoint.isNotEmpty)
                AppTags.info(question.knowledgePoint),
              AppTags.warning('待订正'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: AppPrimaryButton(
              label: '去订正',
              icon: LucideIcons.pencil,
              onPressed: onCorrect,
              height: 40,
              fullWidth: false,
            ),
          ),
        ],
      ),
    );
  }
}
