import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/figures.dart';
import '../../../../shared/domain/models/quiz_option.dart';
import '../../../../shared/domain/scene_spec.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/utils/option_text.dart';
import '../../../../shared/utils/question_labels.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../../../shared/widgets/app_tags.dart';
import '../../../../shared/widgets/scene_interpreter/reflection_figure_gallery.dart';
import '../../../../shared/widgets/scene_interpreter/reflection_scene_data.dart';
import '../../../../shared/widgets/scene_interpreter/reflection_scene_dialog.dart';
import '../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';
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
    // 判断题标记（ADR-0089）：题卡连答案一起落对话历史，前端据此先收起答案，
    // 待学生作答、伴学答疑判对错后再按需揭示。
    final isJudge = raw['judge'] == true;
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
                // 选项走 QuizOption.parseList（ADR-0102）：后端下发的是选项**对象**
                // `{text, figure?}`，用 cardStr 逐条转字符串会把 dict 渲染成
                // 「{text: 房子, figure: {...}}」——图形永远出不来。tolerant parse
                // 同时兼容旧的纯字符串选项（老会话回放）。
                options: QuizOption.parseList(raw['options']) ??
                    const <QuizOption>[],
                answer: cardStr(raw['answer']),
                explanation: cardStr(raw['explanation']),
                reasoning: cardStr(raw['reasoning']),
                sceneSpec: raw['scene_spec'] is Map
                    ? Map<String, dynamic>.from(raw['scene_spec'] as Map)
                    : null,
                isJudge: isJudge,
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
/// 判断题（ADR-0089，`judge: true`）默认收起答案 / 解析 / 出题思路，只露出「显示答案」
/// 按钮——题卡连答案一起落对话历史，学生先作答、由伴学答疑判对错，再按需揭示。
/// 非判断题照常即时展示答案。
///
/// 与左侧色条、卡头分开，是因为色条要撑满整卡高度、卡头是跨卡片共用的，
/// 只有这一段是题卡独有的内容。
class _QuestionBody extends StatefulWidget {
  final String subject;
  final int grade;
  final String qtype;
  final String difficulty;
  final String stem;
  final List<QuizOption> options;
  final String answer;
  final String explanation;
  final String reasoning;
  final Map<String, dynamic>? sceneSpec;
  final bool isJudge;

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
    this.sceneSpec,
    required this.isJudge,
  });

  @override
  State<_QuestionBody> createState() => _QuestionBodyState();
}

class _QuestionBodyState extends State<_QuestionBody> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    // 场景规格经唯一解析入口（ADR-0091）：能解析出类型才渲染交互讲解。
    final spec = widget.sceneSpec == null
        ? null
        : SceneSpec.tryParse(widget.sceneSpec!);
    final hasScene = spec != null;
    // 判断题未揭示前收起答案/解析/出题思路；已揭示或非判断题 → 全量展示。
    final showAnswer = _revealed || !widget.isJudge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            if (widget.subject.isNotEmpty)
              AppTags.subject(SubjectAccent.fromName(widget.subject), label: widget.subject),
            if (widget.grade > 0) AppTags.normal('${widget.grade} 年级'),
            if (widget.qtype.isNotEmpty) AppTags.normal(qtypeLabel(widget.qtype)),
            if (widget.difficulty.isNotEmpty)
              AppTags.normal(difficultyLabel(widget.difficulty)),
          ],
        ),
        if (widget.stem.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            widget.stem,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.5,
            ),
          ),
        ],
        if (widget.options.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _QuestionOptions(options: widget.options),
        ],
        // 判断题待判定：先作答再揭示——未揭示时只给揭示入口与轻提示。
        if (widget.isJudge && !_revealed) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '请判断「对」或「错」后回答，判完再点这里核对。',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          AppTextAction(
            label: '显示答案',
            onPressed: () => setState(() => _revealed = true),
          ),
        ],
        if (showAnswer && widget.answer.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _QuestionAnswerLine(answer: widget.answer),
        ],
        if (showAnswer && widget.explanation.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '解析：${widget.explanation}',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (showAnswer && widget.reasoning.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          AssistantReasoningDisclosure(reasoning: widget.reasoning),
        ],
        if (hasScene) ...[
          const SizedBox(height: AppSpacing.md),
          AppTags.info('交互讲解'),
          const SizedBox(height: AppSpacing.sm),
          SceneInterpreter(spec: spec),
        ],
      ],
    );
  }
}

/// 选项列表：`A.` / `B.` … 序号取自位置，不受选项文本影响。
///
/// 选项带图形（ADR-0102）时右侧渲染行内缩略图，点缩略图打开对折演示——与练习页
/// `AppOptionTile` 同一套视觉语言；助手题卡不参与作答，故整条不可点（只有缩略图可点）。
class _QuestionOptions extends StatelessWidget {
  final List<QuizOption> options;

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
              crossAxisAlignment: CrossAxisAlignment.center,
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
                    cleanOptionText(options[i].text),
                    style: text.bodySmall?.copyWith(color: scheme.onSurface),
                  ),
                ),
                if (options[i].figure != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _OptionFigureTile(figure: options[i].figure!),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 选项行内图形缩略图：点它打开对折演示（只画，不判——ADR-0061 §O）。
class _OptionFigureTile extends StatelessWidget {
  final FigureShape figure;

  const _OptionFigureTile({required this.figure});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    const size = 52.0;
    final points = <Offset>[
      for (final v in figure.vertices) Offset(v.x, v.y),
    ];
    // 可点区一律 AppFocusableAction（ADR-0046）：裸 GestureDetector 不进焦点树，
    // 桌面端 Tab 跳不到、Enter 点不动，而 flutter analyze 照不出来。
    return AppFocusableAction(
      semanticLabel: '查看${figure.label}的对折演示',
      borderRadius: BorderRadius.circular(AppRadius.sm),
      hoverHighlight: true,
      // 与练习页 AppOptionTile 同一入口：弹出完整对折演示（不是静态图）。
      onTap: () => ReflectionSceneDialog.show(
        context,
        data: ReflectionSceneData(
          points: points,
          edges: figure.edges,
          figureLabel: cleanOptionText(figure.label),
        ),
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: scheme.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
        child: CustomPaint(
          // 竖轴对称轴是 reflection kind 的外壳初值（ADR-0083 决策 5）。
          painter: FigureThumbPainter(points: points, axisAngle: 90),
        ),
      ),
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
