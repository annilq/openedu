import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/utils/question_labels.dart';
import '../../../../shared/widgets/app_tags.dart';
import '../../domain/assistant_card.dart';
import '../../domain/card_payload.dart';
import 'assistant_card_header.dart';
import 'assistant_reasoning_disclosure.dart';

/// 题目卡（question）：学科 / 年级 / 题型 / 难度 + 题干 + 选项 + 答案 + 解析 +
/// 出题思路。
///
/// 左侧学科色条由外层 `Row(stretch)` 撑满卡片高度——卡片高度随内容，消息流内
/// 高度无界，故调用点须包 `IntrinsicHeight` 给 Row 一个有界高度。
class AssistantQuestionCard extends StatelessWidget {
  final AssistantCard card;

  const AssistantQuestionCard({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final raw = card.rawPayload;
    final subject = cardStr(raw['subject']);
    final hasSubject = subject.isNotEmpty;
    // 学科色条颜色：色相只是三重编码（ADR-0044）中的一重，chip 另带几何标记。
    final subjectColor = hasSubject
        ? SubjectAccent.forContext(SubjectAccent.fromName(subject), context).accent
        : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasSubject)
          Container(
            width: 6,
            margin: const EdgeInsets.only(right: AppSpacing.md),
            decoration: BoxDecoration(
              color: subjectColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AssistantCardHeader(
                title: '题目',
                kind: AssistantCardKind.question,
              ),
              const SizedBox(height: AppSpacing.sm),
              _QuestionBody(
                subject: subject,
                grade: cardInt(raw['grade']),
                qtype: cardStr(raw['qtype']),
                difficulty: cardStr(raw['difficulty']),
                stem: cardStr(raw['stem']),
                options: raw['options'] is List
                    ? (raw['options'] as List)
                        .map(cardStr)
                        .where((o) => o.isNotEmpty)
                        .toList()
                    : const <String>[],
                answer: cardStr(raw['answer']),
                explanation: cardStr(raw['explanation']),
                reasoning: cardStr(raw['reasoning']),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 题目正文：标签行 → 题干 → 选项 → 答案 → 解析 → 出题思路。
///
/// 与左侧色条、卡头分开，是因为色条要撑满整卡高度、卡头是跨卡片共用的，
/// 只有这一段是题卡独有的内容。
class _QuestionBody extends StatelessWidget {
  final String subject;
  final int grade;
  final String qtype;
  final String difficulty;
  final String stem;
  final List<String> options;
  final String answer;
  final String explanation;
  final String reasoning;

  const _QuestionBody({
    required this.subject,
    required this.grade,
    required this.qtype,
    required this.difficulty,
    required this.stem,
    required this.options,
    required this.answer,
    required this.explanation,
    required this.reasoning,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            if (subject.isNotEmpty)
              AppTags.subject(SubjectAccent.fromName(subject), label: subject),
            if (grade > 0) AppTags.normal('$grade 年级'),
            if (qtype.isNotEmpty) AppTags.normal(qtypeLabel(qtype)),
            if (difficulty.isNotEmpty)
              AppTags.normal(difficultyLabel(difficulty)),
          ],
        ),
        if (stem.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            stem,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.5,
            ),
          ),
        ],
        if (options.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _QuestionOptions(options: options),
        ],
        if (answer.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _QuestionAnswerLine(answer: answer),
        ],
        if (explanation.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '解析：$explanation',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (reasoning.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          AssistantReasoningDisclosure(reasoning: reasoning),
        ],
      ],
    );
  }
}

/// 选项列表：`A.` / `B.` … 序号取自位置，不受选项文本影响。
class _QuestionOptions extends StatelessWidget {
  final List<String> options;

  const _QuestionOptions({required this.options});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${String.fromCharCode(65 + i)}.',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    options[i],
                    style: text.bodySmall?.copyWith(color: scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 答案行。走语义 positive 前景，与「解析」的中性灰区分开——
/// 答案是要被一眼看到的信息，解析是补充。
class _QuestionAnswerLine extends StatelessWidget {
  final String answer;

  const _QuestionAnswerLine({required this.answer});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.checkCircle2, size: 15, color: scheme.semanticPositiveFg),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '答案：$answer',
            style: text.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.semanticPositiveFg,
            ),
          ),
        ),
      ],
    );
  }
}
