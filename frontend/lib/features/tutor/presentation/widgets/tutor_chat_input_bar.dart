import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';

/// AI 伴学底部输入栏：知识点输入（选填）+ 问题多行输入 + 发送按钮。
class TutorChatInputBar extends StatelessWidget {
  final TextEditingController questionController;
  final TextEditingController knowledgePointController;
  final bool sending;
  final VoidCallback onSend;

  const TutorChatInputBar({
    super.key,
    required this.questionController,
    required this.knowledgePointController,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl2, AppSpacing.sm, AppSpacing.xl2, 0),
          child: ShadInput(
            controller: knowledgePointController,
            style: text.bodyMedium?.copyWith(color: scheme.onSurface),
            placeholder: Text('相关知识点（选填）',
                style: text.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            cursorColor: scheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            leading: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Icon(LucideIcons.lightbulb,
                  color: scheme.onSurfaceVariant, size: 20),
            ),
            decoration: ShadDecoration(
              color: scheme.surfaceContainerLow,
              border: ShadBorder.all(
                color: scheme.outline,
                width: 1,
                radius: BorderRadius.circular(AppRadius.input),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ShadInput(
                    controller: questionController,
                    enabled: !sending,
                    minLines: 1,
                    maxLines: 4,
                    style: text.bodyLarge?.copyWith(color: scheme.onSurface),
                    placeholder: Text('输入你的学习问题…',
                        style: text.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    cursorColor: scheme.primary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    leading: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      child: Icon(LucideIcons.pencil,
                          color: scheme.onSurfaceVariant, size: 20),
                    ),
                    decoration: ShadDecoration(
                      color: scheme.surfaceContainerLow,
                      border: ShadBorder.all(
                        color: scheme.outline,
                        width: 1,
                        radius: BorderRadius.circular(AppRadius.input),
                      ),
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: AppPrimaryButton(
                    label: '发送',
                    icon: LucideIcons.send,
                    loadingLabel: '思考中',
                    loading: sending,
                    onPressed: onSend,
                    height: 52,
                    fullWidth: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
