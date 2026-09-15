import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../provider/assistant_notifier.dart';
import '../widgets/assistant_message_list.dart';

/// AI 单入口整页形态（ADR-0036 / ADR-0047）：**双端唯一的助手页面**。
///
/// - 娃娃端：导航空壳的「问 AI 老师」页签（[showBack] = false）；
/// - 家长端：浮动按钮 push 出来的整页（[showBack] = true，[isParent] = true）。
///
/// 两端共用同一 [assistantNotifierProvider] 与同一 [AssistantMessageList]——同一个 AI
/// 能力、同一份会话、同一套渲染，只用 [isParent] 切换标题与空态引导的口径。
///
/// 本页可能经 `Navigator.push` 打开（家长端），此时它**不在导航壳的宽度兜底范围内**
/// （ADR-0045），所以整页自带 `contentWide` 上限：消息列表与输入栏同宽同轴，大屏下
/// 不会出现「气泡收在中间一列、输入框横贯全屏」的错位。
///
/// 收敛前的旧 `TutorChatScreen` 自带 `TutorNotifier` 与学科/年级/知识点三个控件，
/// 但请求体只发 `message`：控件不生效、DATA 帧被丢弃、会话与悬浮助手互不可见。
/// 这三处已随本次收敛一并消除。
class AssistantChatPage extends ConsumerStatefulWidget {
  final bool showBack;

  /// 家长形态：标题与空态引导按家长口径渲染。
  ///
  /// 家长能出题 / 查任务 / 查学情，娃娃端只暴露伴学答疑（后端
  /// `AgentRuntime.visible_businesses(role)` 是唯一真相源），所以「只讲学习内容」这句
  /// 边界提示不能照搬给家长。
  final bool isParent;

  const AssistantChatPage({
    super.key,
    this.showBack = false,
    this.isParent = false,
  });

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
            AppTopBar(
              title: widget.isParent ? 'AI 学习助手' : '问 AI 老师',
              showBack: widget.showBack,
            ),
            Expanded(
              // 宽度上限 + 贴顶：**不用 `Center`**——它连竖向一起居中，消息少时整列
              // 气泡浮在屏幕中间，与本仓「内容贴顶自然布局」的口径冲突（ADR-0045）。
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: AppLayout.contentWide),
                  child: messages.isEmpty
                      ? _WelcomeHint(isParent: widget.isParent)
                      : AssistantMessageList(
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

/// 空态引导：告诉使用者这个入口能问什么、边界在哪。
///
/// 文案按角色分叉（见 [AssistantChatPage.isParent]）：娃娃端强调「只讲学习内容」的
/// 边界，家长端强调「能出题 / 查任务 / 看学情」的能力。
class _WelcomeHint extends StatelessWidget {
  final bool isParent;

  const _WelcomeHint({required this.isParent});

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
            constraints: const BoxConstraints(maxWidth: AppLayout.contentEmpty),
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
                  Text(isParent ? '一句话就能布置任务' : '有问题就问 AI 老师吧',
                      textAlign: TextAlign.start,
                      style: text.titleLarge?.copyWith(
                        color: scheme.onSurface,
                      )),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                      isParent
                          ? '可以出题、查任务、看错题与掌握度'
                          : '只讲学习内容，其他问题不回答哦',
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
      // 与消息列表同宽同轴：本页可能 push 在壳外（家长端），不套上限的话大屏下
      // 输入框会横贯全屏、气泡却收在中间一列。
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.contentWide),
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
                    decoration: ShadDecoration(
                      disableSecondaryBorder: true,
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
                AppPrimaryButton(
                  label: '发送',
                  icon: LucideIcons.send,
                  loadingLabel: '思考中',
                  loading: sending,
                  onPressed: onSend,
                  height: AppControl.heightLgOf(context),
                  fullWidth: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
