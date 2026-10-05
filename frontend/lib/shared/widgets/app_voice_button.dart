import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import 'app_focusable_action.dart';

/// 语音输入麦按钮（ADR-0063 §5）：移动端**长按说话**，桌面端**点按切换**。
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

  /// 上滑多少像素算取消（微信的肌肉记忆）。
  static const double cancelDragDistance = 32;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final scheme = AppTheme.colorsOf(context);
    final hold = holdToTalk ?? _platformPrefersHold;
    return AppFocusableAction(
      // 键盘 Enter / Space 也走这一条：桌面点按与键盘激活是同一语义。
      onTap: listening ? onStop : onStart,
      semanticLabel: listening ? '停止语音输入' : '语音输入',
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
          width: AppControl.heightOf(context),
          height: AppControl.heightOf(context),
          decoration: BoxDecoration(
            // 录音态复用既有「激活」语义（accent），不新造一套颜色（ADR-0063 §4）。
            color: listening ? scheme.accent : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: listening ? scheme.accent : scheme.outline,
              width: AppElevation.borderWidthHairline,
            ),
          ),
          child: Icon(
            listening ? LucideIcons.micVocal : LucideIcons.mic,
            size: 18,
            color: listening ? scheme.onAccent : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  static bool get _platformPrefersHold =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
}
