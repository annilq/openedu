import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import 'app_focusable_action.dart';

/// 语音输入按钮（ADR-0063 §5）：移动端**长按说话**，桌面端**点按切换**。
///
/// 两种形态：
/// - 默认：方形图标按钮，收在输入框尾部等「就地」位置；
/// - [expanded]：全宽「按住 说话」条，整个输入区都变成它（微信式，见
///   `AssistantInputBar` 的语音模式）。
///
/// 为什么是同一个组件而不是两个：两种形态共用同一套状态语义（受控 listening）、
/// 同一套手势（长按 / 上滑取消）与同一套配色，拆成两个组件只会让「桌面档点按」
/// 这类契约被实现两遍、且容易在其中一遍里漏掉。
///
/// 这是三端唯一该分叉的地方——底层可用性本就不一致，统一的是契约（转写流进输入框、
/// 落草稿不自动发送）而不是手势。
///
/// 组件本身**不知道 assistant 存在**，也不认识 `speech_to_text`：只接收状态与回调，
/// 因此能在脱离真实麦克风的测试里被驱动。
class AppVoiceButton extends StatelessWidget {
  const AppVoiceButton({
    super.key,
    required this.visible,
    required this.listening,
    required this.onStart,
    required this.onStop,
    required this.onCancel,
    this.holdToTalk,
    this.expanded = false,
    this.label,
  });

  /// 门禁是否放行。为 false 时**根本不渲染**、不占位、不留空隙（ADR-0063 §2）。
  ///
  /// 为什么不渲染一个禁用按钮：禁用的麦克风图标会让人反复点它，把「这个平台没有
  /// 语音」变成「这个 App 坏了」。
  final bool visible;

  final bool listening;

  /// 开始听（长按按下 / 桌面点按）。
  final VoidCallback onStart;

  /// 松手 / 再点一次。
  final VoidCallback onStop;

  /// 放弃本次（上滑取消）。
  final VoidCallback onCancel;

  /// 是否走「长按说话」。不传时按 [defaultTargetPlatform] 判定：触屏端长按，
  /// 桌面端点按（鼠标长按在触控板上别扭，且 hold 手势在桌面端没有触觉反馈，
  /// 用户不知道「松早了没」）。
  final bool? holdToTalk;

  /// 全宽「按住 说话」形态（微信式）：整个输入区换成这一条。
  final bool expanded;

  /// [expanded] 形态下的文案。转写出的草稿就显示在这里，用户不用先切回键盘
  /// 才知道听到了什么；[listening] 时统一显示「松开 完成」。
  final String? label;

  /// 上滑多少像素算取消（微信的肌肉记忆）。
  static const double cancelDragDistance = 32;

  /// 录音中的文案。
  ///
  /// ⚠️ 不是「松开 发送」：ADR-0063 §4 定的是转写落草稿、**由用户确认后才发送**，
  /// 中文数学术语 ASR 错得离谱，松手即发会白烧一次模型往返。文案必须说真话。
  static const String listeningLabel = '松开 完成';

  static const String idleLabel = '按住 说话';

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final hold = holdToTalk ?? _platformPrefersHold;
    final semantics = listening ? '停止语音输入' : '语音输入';

    return AppFocusableAction(
      // 键盘 Enter / Space / 桌面点按都走这一条。
      //
      // ⚠️ 触屏档（hold=true）这里必须是 null：否则手指**点一下**就会开始录音，
      // 与「长按说话」的肌肉记忆打架——口袋里、讲台上误触一次就是一段废转写。
      // 触屏档只认长按，桌面档才点按即说。
      onTap: hold ? null : (listening ? onStop : onStart),
      semanticLabel: semantics,
      hoverHighlight: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 只声明长按，不声明 onTap：tap 由外层 [AppFocusableAction] 处理，
        // 两层不抢同一个手势。
        onLongPressStart: hold ? (_) => onStart() : null,
        onLongPressEnd: hold ? (_) => onStop() : null,
        onLongPressCancel: hold ? onCancel : null,
        onLongPressMoveUpdate: hold
            ? (details) {
                if (details.offsetFromOrigin.dy <= -cancelDragDistance) {
                  onCancel();
                }
              }
            : null,
        child: AnimatedContainer(
          duration: reducedMotionOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 140),
          // 展开态不设 width：宽度交给外层 Expanded，撑满输入区；这里设死宽度
          // 反而会在窄屏下溢出。
          width: expanded ? null : AppControl.heightOf(context),
          height: expanded
              ? AppControl.heightLgOf(context)
              : AppControl.heightOf(context),
          decoration: BoxDecoration(
            // 录音态复用既有「激活」语义（accent），不新造一套颜色（ADR-0063 §4）。
            color: listening ? scheme.accent : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(
                expanded ? AppRadius.input : AppRadius.chip),
            border: Border.all(
              color: listening ? scheme.accent : scheme.outline,
              width: AppElevation.borderWidthHairline,
            ),
          ),
          child: expanded
              ? _expandedContent(scheme, text)
              : Icon(
                  listening ? LucideIcons.micVocal : LucideIcons.mic,
                  size: 18,
                  color: listening ? scheme.onAccent : scheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }

  Widget _expandedContent(AppColors scheme, AppText? text) {
    final draft = label?.trim() ?? '';
    // 一旦听到了东西就显示**它**，而不是固定文案：录音中能实时看到转写，比一块写着
    // 「松开 完成」的死板按钮有用得多（中文数学术语错得离谱，用户要能当场发现）。
    final shown = draft.isNotEmpty
        ? draft
        : (listening ? listeningLabel : idleLabel);
    final color = listening ? scheme.onAccent : scheme.onSurface;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(listening ? LucideIcons.micVocal : LucideIcons.mic,
            size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        // 草稿可能很长：单行截断，不把输入区撑成多行（高度跳变比截断更难受）。
        Flexible(
          child: Text(
            shown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (text?.bodyMedium ?? const TextStyle())
                .copyWith(color: color),
          ),
        ),
      ],
    );
  }

  static bool get _platformPrefersHold =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
}
