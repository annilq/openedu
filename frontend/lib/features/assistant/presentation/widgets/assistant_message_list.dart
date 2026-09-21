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
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_card.dart';

/// 统一的 AI 消息列表渲染（ADR-0036 单入口 / ADR-0042 卡片协议）。
///
/// 助手整页 [AssistantChatPage]（娃娃端页签 / 家长端浮球打开的都是它）渲染本组件，
/// 保证两个角色对卡片、`blocked`、复制按钮的渲染行为完全一致——收敛前悬浮面板与整页
/// 各写一份渲染，整页只渲染纯文本、静默吞掉 DATA 帧，是「两份渲染」的直接后果。
///
/// 一条 AI 消息的构成（自上而下）：文本气泡 → 结构化卡片（气泡**外侧**）
/// → 复制按钮 → 安全提示。卡片不进气泡：卡片自带 surface 底与描边，
/// 套进气泡是双层容器。
class AssistantMessageList extends StatelessWidget {
  final List<AssistantMessage> messages;
  final ScrollController? controller;

  /// 气泡最大宽度占屏幕比例；实际再夹一个像素上限，避免平板上气泡过宽。
  final double maxBubbleWidthFactor;

  /// 卡片动作出口（引导卡用），透传给 [AssistantCardTile]。
  ///
  /// 由页面注入：同一条卡片在家长端是 push 的整页、在娃娃端是壳内页签，
  /// 「动作之后怎么走」只有宿主知道（见 `assistant_chat_page.dart`）。
  final void Function(AssistantCardAction action)? onCardAction;

  static const double _maxBubbleWidthPx = 760;

  const AssistantMessageList({
    super.key,
    required this.messages,
    this.controller,
    this.maxBubbleWidthFactor = 0.7,
    this.onCardAction,
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
        onCardAction: onCardAction,
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final AssistantMessage message;
  final double maxWidthFactor;
  final void Function(AssistantCardAction action)? onCardAction;

  const _Bubble({
    required this.message,
    required this.maxWidthFactor,
    this.onCardAction,
  });

  /// 气泡与卡片共用的宽度上限：可用宽度 × [maxWidthFactor]，再夹一个像素上限，
  /// 避免平板上过宽（1400px 屏 × 0.7 = 980px 一行太长）。
  ///
  /// 取**可用宽度**（[LayoutBuilder] 的 `constraints.maxWidth`）而非屏宽（ADR-0045）：
  /// 消息列表可能落在 master-detail 的窄栏里，按屏宽算会宽过所在容器。
  static BoxConstraints _constraintsFor(
    BoxConstraints available,
    double maxWidthFactor,
  ) =>
      BoxConstraints(
        maxWidth: math.min(
          available.maxWidth * maxWidthFactor,
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

    return LayoutBuilder(
      builder: (context, available) {
        final constraints = _constraintsFor(available, maxWidthFactor);
        return Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showBubble)
              ConstrainedBox(
                constraints: constraints,
                child: AppCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  color: isUser ? scheme.primary : scheme.surfaceContainerLow,
                  child:
                      _BubbleBody(message: message, scheme: scheme, text: text),
                ),
              ),
            if (cards.isNotEmpty)
              ConstrainedBox(
                constraints: constraints,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0 || showBubble)
                        const SizedBox(height: AppSpacing.sm),
                      PopIn(
                        key: ValueKey<int>(i),
                        // 同一条消息的多张卡必须错峰：默认弹簧是同一条，
                        // 齐步起跳就是 app_motion.dart 开头点名要消灭的「齐步走」。
                        // 夹到第 5 张为止——再往后延迟已经超过人的感知窗口，
                        // 排队等待只会显得卡。
                        delay: AppMotion.interaction * math.min(i, 4),
                        child: AssistantCardTile(
                          card: cards[i],
                          onAction: onCardAction,
                        ),
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
                padding: const EdgeInsets.only(
                    top: AppSpacing.xs2, left: AppSpacing.xs),
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
      },
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
      // 阶段文案：后端编排帧（路由 / 工具调用）到达时替换静态「思考中…」，
      // 让用户看到推进（AiTextFold.stage）。帧未到或无阶段时回退默认文案。
      final label = message.stage.isEmpty ? '思考中…' : message.stage;
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
          // 阶段**切换**而不是「第一次出现」才是常态：一次问答里路由帧、每个工具
          // 调用帧都会改写它（「正在检索错题」→「正在汇总」）。直接换文本是硬切，
          // 恰恰把「又推进了一步」读成了闪烁。换成淡入 + 轻微上浮，推进变成可见的。
          //
          // key 必须绑文本：AnimatedSwitcher 靠 key 判别「换了一个孩子」，
          // 用 const key 会让整段动画静默失效。
          AnimatedSwitcher(
            duration: reducedMotionOf(context) ? Duration.zero : AppMotion.state,
            switchInCurve: AppCurves.state,
            switchOutCurve: AppCurves.state,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.22),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              label,
              key: ValueKey<String>(label),
              style: text.bodySmall,
            ),
          ),
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
    // 「No Material widget found」。走 [AppIconAction]——图标按钮的唯一出口，
    // 自带焦点树 / 悬停底色 / Enter 激活。
    //
    // 收敛前是裸 `GestureDetector`：键盘永远 Tab 不到，且命中区只有 ~23×19，
    // 低于 `.impeccable.md` §Accessibility 的 32px 下限；平板上尤其难点。
    return AppIconAction(
      icon: _copied ? LucideIcons.check : LucideIcons.copy,
      iconSize: 15,
      color: _copied ? scheme.primary : scheme.onSurfaceVariant,
      onPressed: _copy,
      semanticLabel: _copied ? '已复制' : '复制这条回复',
    );
  }
}
