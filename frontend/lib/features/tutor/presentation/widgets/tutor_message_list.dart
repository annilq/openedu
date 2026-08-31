import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../providers/tutor_notifier.dart';

/// AI 伴学对话区：[thinking] 时末尾追加「AI 老师正在思考…」占位气泡。
class TutorMessageList extends StatelessWidget {
  final List<TutorMessage> messages;
  final ScrollController scrollController;
  final bool thinking;

  const TutorMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    this.thinking = false,
  });

  static const _thinkingBubble = TutorMessage(
    role: 'ai',
    text: 'AI 老师正在思考…',
  );

  @override
  Widget build(BuildContext context) {
    final items = thinking ? [...messages, _thinkingBubble] : messages;
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.md),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _MessageBubble(message: items[i]),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final TutorMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final m = message;
    final isChild = m.role == 'child';
    return Align(
      alignment: isChild ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(AppSpacing.md),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isChild
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.bubble),
          border: Border.all(
            color: isChild
                ? scheme.outline
                : scheme.outline,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.text,
                style: text.bodyMedium?.copyWith(
                  color: isChild
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                  height: 1.55,
                )),
            if (m.blocked)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.shieldCheck,
                          size: 14, color: scheme.onErrorContainer),
                      const SizedBox(width: 4),
                      Text('已启用内容安全保护',
                          style: text.labelSmall?.copyWith(
                              color: scheme.onErrorContainer,
                              fontWeight: FontWeight.w600)),
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
