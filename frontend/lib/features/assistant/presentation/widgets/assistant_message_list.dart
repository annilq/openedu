import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_markdown.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../domain/assistant_card.dart';
import '../provider/assistant_notifier.dart';
import 'assistant_cards.dart';

/// 统一的 AI 消息列表渲染（ADR-0036 单入口 / ADR-0042 卡片协议）。
///
/// 悬浮面板 [AssistantChatPanel] 与整页 [AssistantChatPage] 共用本组件，
/// 保证两个形态对卡片、`blocked`、复制按钮的渲染行为完全一致——收敛前整页只渲染
/// 纯文本、静默吞掉 DATA 帧，是「两份渲染」的直接后果。
///
/// 一条 AI 消息的构成（自上而下）：文本气泡 → 结构化卡片（气泡**外侧**）
/// → 复制按钮 → 安全提示。卡片不进气泡：卡片自带 surface 底与描边，
/// 套进气泡是双层容器。
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

  /// 气泡与卡片共用的宽度上限：屏宽 × [maxWidthFactor]，再夹一个像素上限，
  /// 避免平板上过宽（1400px 屏 × 0.7 = 980px 一行太长）。
  BoxConstraints _constraints(BuildContext context) => BoxConstraints(
        maxWidth: math.min(
          MediaQuery.of(context).size.width * maxWidthFactor,
          AssistantMessageList._maxBubbleWidthPx,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final isUser = message.role == 'user';
    final cards = message.cards ?? const <AssistantCard>[];
    // 用户气泡只有文本；AI 气泡里「正文 / 思考中」进气泡，卡片落到气泡外侧。
    final showBubble = message.text.isNotEmpty || message.thinking;
    final copyText = _copyText(message, cards);

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showBubble)
          ConstrainedBox(
            constraints: _constraints(context),
            child: AppCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              color: isUser ? scheme.primary : scheme.surfaceContainerLow,
              child: _BubbleBody(message: message, scheme: scheme, text: text),
            ),
          ),
        if (cards.isNotEmpty)
          ConstrainedBox(
            constraints: _constraints(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0 || showBubble) const SizedBox(height: AppSpacing.sm),
                  PopIn(
                    key: ValueKey<int>(i),
                    child: AssistantCardTile(card: cards[i]),
                  ),
                ],
              ],
            ),
          ),
        // 复制入口只挂在 AI 回复上：用户自己的提问没有复制价值，占位「思考中」
        // 气泡也没有内容可复制。卡片算内容——有卡无文（引用查询结果时很常见）
        // 也要能复制，所以判据是「正文或卡片非空」。
        if (!isUser && !message.thinking && copyText.isNotEmpty)
          Padding(
            padding:
                const EdgeInsets.only(top: AppSpacing.xs2, left: AppSpacing.xs),
            child: _CopyButton(text: copyText),
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

/// 复制到剪贴板的正文：消息文本 + 各卡片的纯文本（[cardPlainText]）。
///
/// 卡片与文本之间空一行分隔，粘进聊天框/笔记仍然可读。
String _copyText(AssistantMessage message, List<AssistantCard> cards) => <String>[
      if (message.text.isNotEmpty) message.text,
      for (final card in cards) cardPlainText(card),
    ].where((part) => part.trim().isNotEmpty).join('\n\n');

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
    // 用户消息是纯文本，气泡底色为 primary、文字 onPrimary，不走 Markdown；
    // AI 消息（bubble 底色 surfaceContainerLow、文字 onSurface）走 Markdown 渲染。
    if (message.role == 'user') {
      return Text(
        message.text,
        style: text.bodyMedium?.copyWith(
          color: scheme.onPrimary,
          height: 1.55,
        ),
      );
    }
    return AppMarkdown(message.text);
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
