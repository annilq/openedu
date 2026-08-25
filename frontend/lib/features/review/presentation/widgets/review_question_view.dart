import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_option_tile.dart';

/// 复习页单题作答区：题干标签 + 选项/输入 + 提交。
/// 纯展示：选中态/答案/提交由调用方（屏幕 State）持有并回调。
class ReviewQuestionView extends StatelessWidget {
  final ReviewItemModel item;
  final String? selectedOption;
  final TextEditingController answerController;
  final bool submitting;
  final bool answerReady;
  final ValueChanged<String> onOptionTap;
  final VoidCallback onAnswerChanged;
  final VoidCallback onSubmit;

  const ReviewQuestionView({
    super.key,
    required this.item,
    required this.selectedOption,
    required this.answerController,
    required this.submitting,
    required this.answerReady,
    required this.onOptionTap,
    required this.onAnswerChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
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
                  AppTags.normal(item.subject),
                  AppTags.normal('${item.grade}年级'),
                  AppTags.info(item.knowledgePoint),
                  AppTags.warning('错过 ${item.wrongCount} 次'),
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
                child: Text(item.stem,
                    style: AppTheme.textOf(context).titleMedium),
              ),
              const SizedBox(height: AppSpacing.xl3),
              if (item.options != null && item.options!.isNotEmpty)
                ...item.options!.asMap().entries.map((e) => AppOptionTile(
                      index: e.key,
                      text: e.value,
                      selected: selectedOption == e.value,
                      disabled: submitting,
                      onTap: () => onOptionTap(e.value),
                    ))
              else
                AppTextField(
                  label: '你的答案',
                  controller: answerController,
                  hintText: '在此填写...',
                  enabled: !submitting,
                  onChanged: (_) => onAnswerChanged(),
                ),
              const SizedBox(height: AppSpacing.xl4),
              AppPrimaryButton(
                label: '提交复习',
                icon: LucideIcons.send,
                loadingLabel: '判题中…',
                loading: submitting,
                onPressed: answerReady ? onSubmit : null,
                height: 52,
                fullWidth: false,
              ),
              if (!answerReady && !submitting)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Center(
                    child: Text('请先给出你的答案',
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
