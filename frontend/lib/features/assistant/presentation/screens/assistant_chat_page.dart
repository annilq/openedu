import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../provider/assistant_notifier.dart';
import '../widgets/assistant_message_list.dart';

/// AI 单入口整页形态（ADR-0036）：娃娃端「问 AI 老师」页签。
///
/// 与家长端悬浮面板 [AssistantChatPanel] 共用同一 [assistantNotifierProvider] 与
/// 同一 [AssistantMessageList]——同一个 AI 能力、同一份会话、同一套渲染。
///
/// 收敛前的旧 `TutorChatScreen` 自带 `TutorNotifier` 与学科/年级/知识点三个控件，
/// 但请求体只发 `message`：控件不生效、DATA 帧被丢弃、会话与悬浮助手互不可见。
/// 这三处已随本次收敛一并消除。
class AssistantChatPage extends ConsumerStatefulWidget {
  final bool showBack;

  const AssistantChatPage({super.key, this.showBack = false});

  @override
  ConsumerState<AssistantChatPage> createState() => _AssistantChatPageState();
}

class _AssistantChatPageState extends ConsumerState<AssistantChatPage> {
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

    final messages = switch (state) {
      AssistantActive(:final messages) => messages,
      _ => const <AssistantMessage>[],
    };
    final streaming = state is AssistantActive && state.streaming;

    // 流式产出时自动滚到底部（逐帧更新）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });

    return SizedBox.expand(
      child: ColoredBox(
        color: scheme.surface,
        child: Column(
          children: [
            AppTopBar(title: '问 AI 老师', showBack: widget.showBack),
            Expanded(
              child: messages.isEmpty
                  ? const _WelcomeHint()
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: AssistantMessageList(
                          messages: messages,
                          controller: _scroll,
                        ),
                      ),
                    ),
            ),
            Container(height: 1, color: scheme.outline),
            _InputBar(controller: _ctrl, sending: streaming, onSend: _send),
          ],
        ),
      ),
    );
  }
}

/// 空态引导：告诉孩子这个入口能问什么、边界在哪。
class _WelcomeHint extends StatelessWidget {
  const _WelcomeHint();

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return PopIn(
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AppCard(
              margin: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 空态图标块：yellow 亮块 + 墨黑字（13.25:1），新粗野撞色强调件。
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppBrutal.yellow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppBrutal.ink, width: AppElevation.borderWidth),
                      boxShadow: AppElevation.hard(),
                    ),
                    alignment: Alignment.center,
                    child: Icon(LucideIcons.sparkles,
                        size: 36, color: AppBrutal.ink),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('有问题就问 AI 老师吧',
                      textAlign: TextAlign.start,
                      style: text.titleLarge?.copyWith(
                        color: scheme.onSurface,
                      )),
                  const SizedBox(height: AppSpacing.sm),
                  Text('只讲学习内容，其他问题不回答哦',
                      textAlign: TextAlign.start,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部输入栏：多行问题输入 + 发送。
///
/// 旧的「相关知识点（选填）」输入框已删除——它对应的字段没进请求体，是死 UI。
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
    final text = AppTheme.textOf(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ShadInput(
                controller: controller,
                enabled: !sending,
                minLines: 1,
                maxLines: 4,
                style: text.bodyLarge?.copyWith(color: scheme.onSurface),
                placeholder: Text('输入你的学习问题…',
                    style: text.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                cursorColor: scheme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                leading: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: Icon(LucideIcons.pencil,
                      color: scheme.onSurfaceVariant, size: 20),
                ),
                decoration: ShadDecoration(
                  color: scheme.surfaceContainerLow,
                  border: ShadBorder.all(
                    color: scheme.outline,
                    width: 1,
                    radius: BorderRadius.circular(AppRadius.input),
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: AppPrimaryButton(
                label: '发送',
                icon: LucideIcons.send,
                loadingLabel: '思考中',
                loading: sending,
                onPressed: onSend,
                height: 52,
                fullWidth: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
