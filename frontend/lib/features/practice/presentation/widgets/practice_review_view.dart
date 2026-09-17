import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_content_frame.dart';
import '../../../../shared/widgets/app_motion.dart';
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
          child: AppContentFrame(
            // 底部行动条刻意留在框外——它该通栏，不该跟着内容一起缩进。
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                  AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
              children: [
                // 汇总头：AppCard（2px 墨黑描边 + 硬阴影）+ 弹簧入场。
                PopIn(
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl2),
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
                // 错峰：key 稳定 → PopIn 不重用重建，列表刷新时不会重放弹簧。
                ...wrongQuestions.asMap().entries.map(
                      (e) => PopIn(
                        key: ValueKey<int>(e.key),
                        // 左侧学科色条由 Row(stretch) 撑满行高；ListView 内高度无界，
                        // 须 IntrinsicHeight 给 Row 一个有界高度。
                        child: IntrinsicHeight(
                          child: _WrongToFixCard(
                            question: e.value,
                            onCorrect: () => onCorrect(e.value.id),
                          ),
                        ),
                      ),
                    ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '提示：能当场订正的尽量订正；实在不要再提交，错题会自动进入复习计划。',
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        // 底部最终提交：纸底 + 2px 墨黑顶边（行动条，非内容卡）。
        Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md,
              AppSpacing.lg, AppSpacing.xl2),
          decoration: BoxDecoration(
            color: AppBrutal.paper,
            border: Border(
              top: BorderSide(
                  color: AppBrutal.ink, width: AppElevation.borderWidth),
            ),
          ),
          child: AppPrimaryButton(
            label: '完成打卡 · 进入复习',
            icon: LucideIcons.checkCircle2,
            onPressed: onCommit,
            height: AppControl.heightLgOf(context),
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
    // 学科色条：左侧 6px 撞色块作强调件，叠加学科 chip 三重编码（色 + 几何标记 + 文字）。
    final subjectKey = SubjectAccent.fromName(question.subject);
    final subjectColor = SubjectAccent.forContext(subjectKey, context).accent;
    // 密集列表行：AppCard.listRow（1px 墨黑描边、无阴影，降噪，ADR-0044）。
    return AppCard.listRow(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: subjectColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
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
                          AppTags.subject(
                              SubjectAccent.fromName(question.subject)),
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
                        // 行内次要行动：不传 height → 走标准档，与同行其他控件同高。
                        fullWidth: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
