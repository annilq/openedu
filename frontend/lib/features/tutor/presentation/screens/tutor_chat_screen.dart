import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../providers/tutor_notifier.dart';
import '../widgets/tutor_chat_input_bar.dart';
import '../widgets/tutor_message_list.dart';
import '../widgets/tutor_welcome_hint.dart';

/// 娃娃端 AI 伴学答疑页。v2 redesign：
/// - 学科/年级选择合并为单行紧凑布局（标签内联 + 值，降低头部垂直占用）
/// - 知识点输入框取消 isCollapsed，使用主题高度
/// - 输入框取消自定义 OutlineInputBorder，复用全局主题
/// - 气泡背景：孩子问 = 植物绿容器，AI 答 = 米色+1px 描边（区分）
/// - "内容安全"字样改用 tertiaryContainer（暖色警告容器）
class TutorChatScreen extends ConsumerStatefulWidget {
  final UserModel user;
  final bool showBack;
  const TutorChatScreen({super.key, required this.user, this.showBack = true});

  @override
  ConsumerState<TutorChatScreen> createState() => _TutorChatScreenState();
}

class _TutorChatScreenState extends ConsumerState<TutorChatScreen> {
  final _questionCtrl = TextEditingController();
  final _kpCtrl = TextEditingController();
  String _subject = '数学';
  late int _grade;
  bool _sending = false;
  final ScrollController _scrollCtrl = ScrollController();

  static const _subjects = ['数学', '语文', '英语'];

  @override
  void initState() {
    super.initState();
    _grade = widget.user.grade ?? 2;
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _kpCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _questionCtrl.text.trim();
    if (question.isEmpty || _sending) return;
    if (ref.read(tutorNotifierProvider) is TutorLoading) return;
    final req = TutorAskReq(
      subject: _subject,
      grade: _grade,
      knowledgePoint: _kpCtrl.text.trim(),
      question: question,
    );
    _questionCtrl.clear();
    setState(() => _sending = true);
    // v1 Genkit 流式答疑：逐 token 回传，防重入由 notifier 内部 _submitting 保证。
    await ref.read(tutorNotifierProvider.notifier).askStream(req);
    if (!mounted) return;
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tutorNotifierProvider);
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);

    // 流式产出时自动滚到底部（逐 token 更新）。
    ref.listen<TutorState>(tutorNotifierProvider, (prev, next) {
      if (next is TutorInitial) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          );
        }
      });
    });

    final messages = switch (state) {
      TutorInitial() => const <TutorMessage>[],
      TutorLoading(:final messages) => messages,
      TutorLoaded(:final messages) => messages,
    };
    final streaming = state is TutorLoading;
    final lastAiEmpty = messages.isNotEmpty &&
        messages.last.role == 'ai' &&
        messages.last.text.isEmpty;
    final showThinking = streaming && lastAiEmpty;

    return SizedBox.expand(
      child: ColoredBox(
        color: scheme.surface,
        child: Column(
          children: [
            AppTopBar(title: '问 AI 老师', showBack: widget.showBack),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('学科', style: text.titleSmall),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: ShadSelect<String>(
                            initialValue: _subject,
                            onChanged: (v) {
                              if (v != null) setState(() => _subject = v);
                            },
                            selectedOptionBuilder: (context, selected) => Text(
                              selected,
                              style: text.bodyMedium
                                  ?.copyWith(color: scheme.onSurface),
                            ),
                            options: [
                              for (final s in _subjects)
                                ShadOption<String>(
                                  value: s,
                                  child: Text(
                                    s,
                                    style: text.bodyMedium
                                        ?.copyWith(color: scheme.onSurface),
                                  ),
                                ),
                            ],
                            placeholder: Text(
                              '请选择',
                              style: text.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            decoration: ShadDecoration(
                              disableSecondaryBorder: true,
                              color: scheme.surfaceRaised,
                              border: ShadBorder.all(
                                color: scheme.outline,
                                width: 1,
                                radius: BorderRadius.circular(AppRadius.input),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('年级', style: text.titleSmall),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.input),
                              border:
                                  Border.all(color: scheme.outline, width: 1),
                            ),
                            child: Text(
                              '$_grade年级',
                              style: text.bodyMedium
                                  ?.copyWith(color: scheme.onSurface),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(height: 1, color: scheme.outline),
            Expanded(
              child: messages.isEmpty && !streaming
                  ? const TutorWelcomeHint()
                  : TutorMessageList(
                      messages: messages,
                      scrollController: _scrollCtrl,
                      thinking: showThinking,
                    ),
            ),
            TutorChatInputBar(
              questionController: _questionCtrl,
              knowledgePointController: _kpCtrl,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}
