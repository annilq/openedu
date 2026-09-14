import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../provider/assistant_notifier.dart';
import 'assistant_message_list.dart';

/// 全局悬浮 AI 助手宿主：把 `child`（如 HomeScreen）包进 Stack，右上角常驻一个
/// 悬浮按钮，点击展开对话面板。
///
/// 角色门（ADR-0036）：只对**家长端**挂载。娃娃端改用整页
/// `AssistantChatPage`（导航页签），避免同一个 AI 出现两个入口。
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
              child:
                  AssistantChatPanel(onClose: () => setState(() => _open = false)),
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
///
/// 消息渲染委托 [AssistantMessageList]——与整页 `AssistantChatPage` 共用同一实现
/// （ADR-0036），保证题卡 / 安全标记 / 复制的行为在两个形态下一致。
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
                : AssistantMessageList(
                    messages: messages,
                    controller: _scroll,
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
