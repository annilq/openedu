import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_option_tile.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_tags.dart';
import '../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';
import '../../../../shared/utils/option_text.dart';
import '../../../../shared/utils/question_labels.dart';

/// 做题页单题作答区：题干标签 + 选项/输入 + 提交。
/// 纯展示：选中态/答案/提交由调用方（屏幕 State）持有并回调。
class PracticeQuestionView extends StatelessWidget {
  final QuestionModel question;
  final TaskModel task;
  final Set<String> selectedOptions;
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
    required this.selectedOptions,
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
    final q = question;
    final scene = q.sceneSpec;
    final hasFigureGroup = scene != null &&
        scene['optionGroup'] is Map &&
        ((scene['optionGroup']['items'] as List?)?.isNotEmpty ?? false);
    final total = task.questions.length;
    final currentIndex = task.questions.indexOf(q);
    final isLast = currentIndex < 0 || currentIndex >= total - 1;

    // 学科色条：左侧撞色块 + 学科 chip 三重编码（math■ / chinese● / english▲）。
    final subjectKey = SubjectAccent.fromName(q.subject);
    final subjectColor = SubjectAccent.forContext(subjectKey, context).accent;

    // 题干区：AppCard（2px 墨黑描边 + 硬阴影）承载，左侧 6px 学科撞色条作强调件（< 40% 面积）。
    final stemBlock = AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: subjectColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(q.stem,
                    style: AppTheme.textOf(context).titleMedium),
              ),
            ),
          ],
        ),
      ),
    );

    // 切换题目时 key 变化 → 重新挂载 → 弹簧入场（PopIn，非 easeOutBack）。
    return PopIn(
      key: ValueKey<String>(q.id),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.contentReading),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    // ADR-0004：学科下沉到题，从当前题取字段；chip 自带色 + 几何标记。
                    if (q.subject.isNotEmpty)
                      AppTags.subject(SubjectAccent.fromName(q.subject)),
                    if (q.grade > 0) AppTags.normal('${q.grade}年级'),
                    if (q.knowledgePoint.isNotEmpty)
                      AppTags.info(q.knowledgePoint),
                    AppTags.normal(qtypeLabelWithJudge(q.qtype, q.options)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                // 左侧学科色条靠 Row(stretch) 撑满卡片高度；题干高度随内容，
                // 必须用 IntrinsicHeight 给 Row 一个有界高度，否则在无界滚动区里崩。
                IntrinsicHeight(child: stemBlock),
                const SizedBox(height: AppSpacing.xxl),
                // 几何选项组（ADR-0061 §O）：选择题每个选项本身是一个图形（如「下列图形
                // 哪个是轴对称」）时，把题干下方的选项组渲染成每个图形一个可交互场景，
                // 与下方可点选的 A/B/C/D 选项卡对应。无选项组时整块跳过。
                if (hasFigureGroup)
                  ...[
                    SceneInterpreter(
                      kind: (scene['kind'] as String?) ?? 'reflection',
                      spec: scene,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                // 选择题按 qtype 走选项卡片（ADR-0004：qtype ∈ {choice,fill,calc,open}）。
                // 只有 choice 且有有效选项才渲染选项，其余（填空/计算/应用）走输入框——
                // 这样「选择题渲染成文本框」的退化被根因拦在落库前（后端 TASK_CHOICE_NO_OPTIONS），
                // 前端此处只在选项确实可用时才切到选择模式。
                if (q.qtype == 'choice' &&
                    q.options != null &&
                    q.options!.isNotEmpty)
                  ...q.options!.asMap().entries.map((e) => AppOptionTile(
                        index: e.key,
                        text: cleanOptionText(e.value),
                        selected: selectedOptions.contains(e.value),
                        multi: q.multi,
                        onTap: () => onOptionTap(e.value),
                      ))
                else
                  AppTextField(
                    label: '你的答案',
                    controller: answerController,
                    hintText: '在此填写...',
                    onChanged: (_) => onAnswerChanged(),
                  ),
                const SizedBox(height: AppSpacing.xl2),
                AppPrimaryButton(
                  label: preview ? (isLast ? '已是最后一题' : '下一题') : '提交答案',
                  icon: preview ? LucideIcons.arrowRight : LucideIcons.send,
                  onPressed: preview
                      ? (isLast ? null : onNext)
                      : (answerReady ? onSubmit : null),
                  height: AppControl.heightLgOf(context),
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
      ),
    );
  }
}
