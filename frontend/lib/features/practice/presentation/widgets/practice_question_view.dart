import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_motion.dart';
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
    final q = question;
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
            constraints: const BoxConstraints(maxWidth: 820),
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
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                // 左侧学科色条靠 Row(stretch) 撑满卡片高度；题干高度随内容，
                // 必须用 IntrinsicHeight 给 Row 一个有界高度，否则在无界滚动区里崩。
                IntrinsicHeight(child: stemBlock),
                const SizedBox(height: AppSpacing.xxl),
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
                const SizedBox(height: AppSpacing.xl2),
                AppPrimaryButton(
                  label: preview ? (isLast ? '已是最后一题' : '下一题') : '提交答案',
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
      ),
    );
  }
}
