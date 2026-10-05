import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/providers/voice_session_provider.dart';
import '../../../../shared/domain/voice_input.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_content_frame.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/app_voice_button.dart';

/// 助手底部输入栏：多行问题输入 + 语音 + 发送（ADR-0036 单入口的唯一输入区）。
///
/// 从 [AssistantChatPage] 里拆出来（ADR-0058 §1：一个文件只暴露一个公开物）——
/// 该页原本 557 行、已登记在文件规模棘轮基线里，语音输入（ADR-0063）要往输入区加
/// 麦按钮与录音态状态，直接堆进页面会把基线推得更高。拆出来后语音相关的状态与
/// 控件都长在本文件里，主页面不新增一个字段。
///
/// 旧的「相关知识点（选填）」输入框已删除——它对应的字段没进请求体，是死 UI。
class AssistantInputBar extends ConsumerStatefulWidget {
  const AssistantInputBar({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  ConsumerState<AssistantInputBar> createState() => _AssistantInputBarState();
}

class _AssistantInputBarState extends ConsumerState<AssistantInputBar> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// 静音阈值按角色分档（ADR-0063 §6）：儿童说话停顿多，阈值要放宽。
  ///
  /// 角色直接读 [UserModeScope] 而不从页面传参——助手整页已 473 行并登记在
  /// 文件规模棘轮基线里（ADR-0058，只许下调），为一个新增参数把它顶到 479 会
  /// 撞棘轮；而「当前是谁在用」本就是全局信号，不该逐层透传。
  Duration _silenceTimeoutOf(BuildContext context) =>
      UserModeScope.of(context) == AppUserMode.parent
          ? VoiceSilence.adult
          : VoiceSilence.child;

  void _startVoice() {
    // 上一轮还在思考时不许起新会话：转写会写进同一个输入框，与流式回答抢内容。
    if (widget.sending) return;
    ref.read(voiceSessionProvider.notifier).start(
          baseText: widget.controller.text,
          silenceTimeout: _silenceTimeoutOf(context),
        );
  }

  void _stopVoice() => ref.read(voiceSessionProvider.notifier).stop();

  void _cancelVoice() => ref.read(voiceSessionProvider.notifier).cancel();

  /// 「重说」（ADR-0063 §7）：清空草稿重新录制。
  ///
  /// 一二年级儿童识字量有限，看到转错的「三分之二」改不出来——「落草稿可改」对他们
  /// 是伪能力，所以主行动是整句重说，而不是让用户去编辑。
  void _respeak() {
    widget.controller.clear();
    ref.read(voiceSessionProvider.notifier).start(
          baseText: '',
          silenceTimeout: _silenceTimeoutOf(context),
        );
  }

  void _send() {
    // 草稿已发走，会话状态要跟着清，否则「重说」会挂在上一条已发送的文本上。
    ref.read(voiceSessionProvider.notifier).clearDraft();
    widget.onSend();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final session = ref.watch(voiceSessionProvider);

    // 转写结果直接写进输入框本身（ADR-0063 §4）：不用浮层气泡——浮层会与气泡列表
    // 抢视觉焦点，且停止后还要再做一次「搬到输入框」的动作。
    ref.listen(voiceSessionProvider.select((s) => s.draft), (_, next) {
      _applyDraft(next);
    });
    // 失败必须出声：语音输入最大的风险是静默失败（门禁不过 / 没听清 / 权限被拒）。
    ref.listen(voiceSessionProvider.select((s) => s.failure), (_, next) {
      if (next != null) AppToast.show(context, next.message);
    });
    // 停止后焦点回输入框、光标置于末尾，可直接回车发送。
    ref.listen(voiceSessionProvider.select((s) => s.listening), (prev, next) {
      if (prev == true && next == false && widget.controller.text.isNotEmpty) {
        _focusNode.requestFocus();
      }
    });

    return SafeArea(
      top: false,
      // 与消息列表同宽同轴：助手整页可能 push 在壳外（家长端），不套上限的话大屏下
      // 输入框会横贯全屏、气泡却收在中间一列。
      child: AppContentFrame(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ShadInput(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  enabled: !widget.sending,
                  minLines: 1,
                  maxLines: 4,
                  style: text.bodyLarge?.copyWith(color: scheme.onSurface),
                  placeholder: Text('输入你的学习问题…',
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  cursorColor: scheme.primary,
                  // 单行高度取「主行动档」，与右侧发送按钮同档：两者是同一组
                  // 控件，必须同高。此前输入框靠 `vertical: 14` 撑到 51px、按钮
                  // 硬编码 52、再用 `Padding(bottom: 2)` 手工找平——三个魔数互相
                  // 追着补。现在高度由同一令牌决定，竖向 padding 只负责多行时的
                  // 呼吸感（8+单行+8 = 37 < 48，单行仍是精确的 48，多行按内容增高）。
                  constraints: BoxConstraints(
                      minHeight: AppControl.heightLgOf(context)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(LucideIcons.pencil,
                        color: scheme.onSurfaceVariant, size: 20),
                  ),
                  // 麦按钮与「重说」都收在输入框尾部：与输入共用一行，不额外占
                  // 宽度、不引入新的纵向层。门禁不放行时整个 trailing 为 null。
                  trailing: _trailing(session),
                  decoration: ShadDecoration(
                    disableSecondaryBorder: true,
                    color: scheme.surfaceContainerLow,
                    border: ShadBorder.all(
                      color: scheme.outline,
                      width: 1,
                      radius: BorderRadius.circular(AppRadius.input),
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              AppPrimaryButton(
                label: '发送',
                icon: LucideIcons.send,
                loadingLabel: '思考中',
                loading: widget.sending,
                onPressed: _send,
                height: AppControl.heightLgOf(context),
                fullWidth: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _trailing(VoiceSessionState session) {
    final children = <Widget>[
      if (session.spoken && !session.listening && !widget.sending)
        AppTextAction(label: '重说', onPressed: _respeak),
      if (session.voiceVisible)
        AppVoiceButton(
          visible: true,
          listening: session.listening,
          onStart: _startVoice,
          onStop: _stopVoice,
          onCancel: _cancelVoice,
        ),
    ];
    if (children.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  void _applyDraft(String value) {
    if (widget.controller.text == value) return;
    widget.controller.text = value;
    widget.controller.selection = TextSelection.collapsed(offset: value.length);
  }
}
