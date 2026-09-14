import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../provider/assistant_notifier.dart';

/// 统一的 AI 消息列表渲染（ADR-0036 单入口）。
///
/// 悬浮面板 [AssistantChatPanel] 与整页 [AssistantChatPage] 共用本组件，
/// 保证两个形态对 `cards`（题卡/任务卡）、`blocked`、复制按钮的渲染行为完全一致
/// —— 收敛前整页只渲染纯文本、静默吞掉 DATA 帧，是「两份渲染」的直接后果。
class AssistantMessageList extends StatelessWidget {
  final List<AssistantMessage> messages;
  final ScrollController? controller;

  /// 气泡最大宽度占屏幕比例；实际再夹一个像素上限，避免平板上气泡过宽。
  final double maxBubbleWidthFactor;

  static const double _maxBubbleWidthPx = 760;

  const AssistantMessageList({
    super.key,
    required this.messages,
    this.controller,
    this.maxBubbleWidthFactor = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) => _Bubble(
        message: messages[i],
        maxWidthFactor: maxBubbleWidthFactor,
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final AssistantMessage message;
  final double maxWidthFactor;

  const _Bubble({required this.message, required this.maxWidthFactor});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final isUser = message.role == 'user';
    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(
            maxWidth: math.min(
              MediaQuery.of(context).size.width * maxWidthFactor,
              AssistantMessageList._maxBubbleWidthPx,
            ),
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
        // 复制入口只挂在 AI 回复上：用户自己的提问没有复制价值，占位「思考中」
        // 气泡也没有正文可复制。
        if (!isUser && !message.thinking && message.text.isNotEmpty)
          Padding(
            padding:
                const EdgeInsets.only(top: AppSpacing.xs2, left: AppSpacing.xs),
            child: _CopyButton(text: message.text),
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
            height: 1.55,
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

/// AI 消息下方的「复制」图标按钮：把消息正文写入系统剪贴板。
///
/// 单独抽成 StatefulWidget 而非内联闭包：[Clipboard.setData] 是异步的，必须在
/// await 之后确认 `mounted` 再取 context 弹 Toast，否则触发
/// `use_build_context_synchronously`。复制成功后图标短暂切成对勾，给一次就地反馈
/// （Toast 浮在面板底部，视线常不在此处）。
class _CopyButton extends StatefulWidget {
  final String text;
  const _CopyButton({required this.text});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    AppToast.show(context, '已复制');
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    // 不用 InkWell：本 App 根是 CupertinoApp，子树内没有 Material 祖先，会抛
    // 「No Material widget found」。沿用仓库既有的 GestureDetector 写法。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _copy,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs2,
        ),
        child: Icon(
          _copied ? LucideIcons.check : LucideIcons.copy,
          size: 15,
          color: _copied ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
