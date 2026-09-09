import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../provider/assistant_notifier.dart';

/// 全局悬浮 AI 助手宿主：把 `child`（如 HomeScreen）包进 Stack，右上角常驻一个
/// 悬浮按钮，点击展开对话面板。家长 / 娃娃端通用——角色由后端 JWT 解析。
class FloatingAssistant extends StatelessWidget {
  final Widget child;

  const FloatingAssistant({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        const _AssistantOverlay(),
      ],
    );
  }
}

class _AssistantOverlay extends StatefulWidget {
  const _AssistantOverlay();

  @override
  State<_AssistantOverlay> createState() => _AssistantOverlayState();
}

class _AssistantOverlayState extends State<_AssistantOverlay> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (_open)
          Positioned(
            right: AppSpacing.lg,
            bottom: 88,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 380,
                maxHeight: 540,
              ),
              child: AssistantChatPanel(onClose: () => setState(() => _open = false)),
            ),
          ),
        Positioned(
          right: AppSpacing.lg,
          bottom: AppSpacing.lg,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                _open ? Icons.close : Icons.smart_toy_outlined,
                color: scheme.onPrimary,
                size: 26,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 助手对话面板（含消息列表 + 输入框）。状态由 [assistantNotifierProvider] 驱动。
class AssistantChatPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const AssistantChatPanel({super.key, required this.onClose});

  @override
  ConsumerState<AssistantChatPanel> createState() => _AssistantChatPanelState();
}

class _AssistantChatPanelState extends ConsumerState<AssistantChatPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    ref.read(assistantNotifierProvider.notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantNotifierProvider);
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);

    final messages = switch (state) {
      AssistantActive(:final messages) => messages,
      _ => const <AssistantMessage>[],
    };
    final streaming = state is AssistantActive && state.streaming;

    // 新消息自动滚到底部。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: scheme.outline, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          _Header(onClose: widget.onClose),
          const Divider(height: 1),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      '问我任何学习问题：\n出题、查任务、答疑…',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: messages.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) =>
                        _Bubble(message: messages[i], scheme: scheme, text: text),
                  ),
          ),
          const Divider(height: 1),
          _InputBar(
            controller: _ctrl,
            sending: streaming,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.smart_toy_outlined, color: scheme.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text('AI 学习助手', style: text.titleSmall),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Icon(Icons.close, color: scheme.onSurfaceVariant, size: 18),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: ShadInput(
              controller: controller,
              placeholder: const Text('说点什么…'),
              onSubmitted: (_) => onSend(),
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
          const SizedBox(width: AppSpacing.sm),
          ShadButton(
            onPressed: sending ? null : onSend,
            child: const Icon(Icons.send, size: 18),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final AssistantMessage message;
  final AppColors scheme;
  final AppText text;

  const _Bubble({
    required this.message,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isUser ? scheme.primary : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: isUser
                ? null
                : Border.all(color: scheme.outline, width: 1),
          ),
          child: _BubbleBody(message: message, scheme: scheme, text: text),
        ),
        if (message.blocked)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4),
            child: Text(
              '内容安全限制',
              style: text.labelSmall?.copyWith(color: scheme.error),
            ),
          ),
      ],
    );
  }
}

class _BubbleBody extends StatelessWidget {
  final AssistantMessage message;
  final AppColors scheme;
  final AppText text;

  const _BubbleBody({
    required this.message,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    if (message.thinking) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('思考中…', style: text.bodySmall),
        ],
      );
    }
    final children = <Widget>[
      if (message.text.isNotEmpty)
        Text(
          message.text,
          style: text.bodyMedium?.copyWith(
            color: message.role == 'user' ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      if (message.cards != null && message.cards!.isNotEmpty)
        ...message.cards!.map(
          (c) => _CardTile(card: c, scheme: scheme, text: text),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _CardTile extends StatelessWidget {
  final Map<String, dynamic> card;
  final AppColors scheme;
  final AppText text;

  const _CardTile({
    required this.card,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final subject = card['subject']?.toString() ?? '';
    final stem = card['stem']?.toString() ?? '';
    final type = card['type']?.toString() ?? '';
    if (stem.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: scheme.outline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subject.isNotEmpty || type.isNotEmpty)
            Text(
              [subject, type].where((e) => e.isNotEmpty).join(' · '),
              style: text.labelSmall?.copyWith(color: scheme.primary),
            ),
          const SizedBox(height: 2),
          Text(stem, style: text.bodySmall),
        ],
      ),
    );
  }
}
