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

  /// 输入区当前是「键盘」还是「语音」（微信式切换）。
  ///
  /// 为什么是**两种互斥模式**而不是「输入框旁边挂一个麦按钮」：后者把两种输入
  /// 挤在同一行，麦按钮只能做成 40px 的小图标——学生手指点不准，而真正的语音
  /// 输入需要一块能按住的大靶面。切成模式后，语音态下整条输入区都是「按住 说话」。
  bool _voiceMode = false;

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

  /// 静音阈值按角色分档（ADR-0063 §6）：学生说话停顿多，阈值要放宽。
  ///
  /// 角色直接读 [UserModeScope] 而不从页面传参——助手整页已 473 行并登记在
  /// 文件规模棘轮基线里（ADR-0058，只许下调），为一个新增参数把它顶到 479 会
  /// 撞棘轮；而「当前是谁在用」本就是全局信号，不该逐层透传。
  Duration _silenceTimeoutOf(BuildContext context) =>
      UserModeScope.of(context) == AppUserMode.teacher
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

  /// 键盘 / 语音两种模式互换（微信式）。
  ///
  /// 图标表示**当前**模式：键盘态显示键盘、语音态显示麦——点它就是要换成另一种。
  void _toggleMode() {
    if (widget.sending) return;
    final toVoice = !_voiceMode;
    setState(() => _voiceMode = toVoice);
    if (toVoice) {
      // 语音态下输入框整个被「按住 说话」取代，键盘留着只会挡住这块靶面。
      _focusNode.unfocus();
    } else {
      if (ref.read(voiceSessionProvider).listening) _stopVoice();
      _focusNode.requestFocus();
    }
  }

  /// 「重说」（ADR-0063 §7）：清空草稿重新录制。
  ///
  /// 一二年级学生识字量有限，看到转错的「三分之二」改不出来——「落草稿可改」对他们
  /// 是伪能力，所以主行动是整句重说，而不是让用户去编辑。
  void _respeak() {
    widget.controller.clear();
    // 重说就是要重新录：顺手切到语音态，否则用户点的「重说」会把界面留在键盘态，
    // 而录音已经在跑，看起来像点了个没反应的按钮。
    if (!_voiceMode) {
      setState(() => _voiceMode = true);
      _focusNode.unfocus();
    }
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

    // 门禁不放行时不允许停在语音态：探测是异步的，可能先按 `denied` 放过、随后
    // 才定成 `unsupported`，这里按最新结果兜住，避免留一块点不动的「按住 说话」。
    final voiceMode = _voiceMode && session.voiceVisible;

    return SafeArea(
      top: false,
      // 与消息列表同宽同轴：助手整页可能 push 在壳外（教师端），不套上限的话大屏下
      // 输入框会横贯全屏、气泡却收在中间一列。
      child: AppContentFrame(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: voiceMode ? _holdToTalk(session) : _inputField(scheme, text),
              ),
              const SizedBox(width: AppSpacing.md),
              // 「重说」只在键盘态出现：语音态的输入区已经是「按住 说话」，
              // 再挂一个文字按钮会把这条靶面挤窄。
              if (!voiceMode &&
                  session.spoken &&
                  !session.listening &&
                  !widget.sending) ...[
                AppTextAction(label: '重说', onPressed: _respeak),
                const SizedBox(width: AppSpacing.sm),
              ],
              // 模式切换按钮。门禁不放行时**整个不渲染**（ADR-0063 §2）——不是渲染
              // 一个禁用图标，那会让人反复去点。
              if (session.voiceVisible)
                AppIconAction(
                  icon: voiceMode ? LucideIcons.mic : LucideIcons.keyboard,
                  semanticLabel:
                      voiceMode ? '当前语音输入，点此切回键盘' : '切换到语音输入',
                  onPressed: _toggleMode,
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

  /// 语音态：整条输入区就是「按住 说话」。
  ///
  /// 草稿直接显示在这条上，用户不必先切回键盘才知道听到了什么。
  Widget _holdToTalk(VoiceSessionState session) => AppVoiceButton(
        visible: true,
        expanded: true,
        listening: session.listening,
        label: session.draft,
        onStart: _startVoice,
        onStop: _stopVoice,
        onCancel: _cancelVoice,
      );

  /// 键盘态的输入框。`scheme` / `text` 由调用方传入——本方法在 build 之外，够不到
  /// build 里的局部变量。
  Widget _inputField(AppColors scheme, AppText text) => ShadInput(
        controller: widget.controller,
        focusNode: _focusNode,
        enabled: !widget.sending,
        minLines: 1,
        maxLines: 4,
        style: text.bodyLarge?.copyWith(color: scheme.onSurface),
        placeholder: Text('输入你的学习问题…',
            style:
                text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        cursorColor: scheme.primary,
        // 单行高度取「主行动档」，与右侧发送按钮同档：两者是同一组控件，必须同高。
        // 此前输入框靠 `vertical: 14` 撑到 51px、按钮硬编码 52、再用
        // `Padding(bottom: 2)` 手工找平——三个魔数互相追着补。现在高度由同一令牌
        // 决定，竖向 padding 只负责多行时的呼吸感（8+单行+8 = 37 < 48，单行仍是
        // 精确的 48，多行按内容增高）。
        constraints:
            BoxConstraints(minHeight: AppControl.heightLgOf(context)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Icon(LucideIcons.pencil,
              color: scheme.onSurfaceVariant, size: 20),
        ),
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
      );

  void _applyDraft(String value) {
    if (widget.controller.text == value) return;
    widget.controller.text = value;
    widget.controller.selection = TextSelection.collapsed(offset: value.length);
  }
}
