import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../providers/tutor_notifier.dart';

/// 娃娃端 AI 伴学答疑页。v2 redesign：
/// - 学科/年级选择统一使用自研组件（AppPickerField / 独立静态年级框）
/// - 知识点输入框取消 isCollapsed，使用主题高度
/// - 输入框取消自定义 OutlineInputBorder，复用全局主题
/// - 气泡背景：孩子问 = 植物绿容器，AI 答 = 米色+1px 描边（区分）
/// - "内容安全"字样改用 tertiaryContainer（暖色警告容器）
class TutorChatScreen extends ConsumerStatefulWidget {
  final UserModel user;
  const TutorChatScreen({super.key, required this.user});

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
    await ref.read(tutorNotifierProvider.notifier).ask(req);
    if (!mounted) return;
    setState(() => _sending = false);
    // 自动滚到底
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tutorNotifierProvider);
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: const Text('问 AI 老师')),
      child: Column(
        children: [
          // 学科 / 年级选择：统一扁平输入风格
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppPickerField<String>(
                    label: '学科',
                    values: _subjects,
                    labels: _subjects,
                    value: _subject,
                    onChanged: (v) => setState(() => _subject = v),
                  ),
                ),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('年级', style: text.titleSmall),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius:
                              BorderRadius.circular(AppRadius.input),
                          border:
                              Border.all(color: scheme.outline, width: 1),
                        ),
                        child: Text('$_grade年级', style: text.bodyLarge),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(height: 1, color: scheme.outline),
          // 对话区
          Expanded(
            child: switch (state) {
              TutorInitial() => _welcomeHint(),
              TutorLoading(:final messages) =>
                _messageList(context, messages, thinking: true),
              TutorLoaded(:final messages) => messages.isEmpty
                  ? _welcomeHint()
                  : _messageList(context, messages),
            },
          ),
          // 知识点 + 提问输入
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl2, AppSpacing.sm, AppSpacing.xl2, 0),
            child: CupertinoTextField(
              controller: _kpCtrl,
              placeholder: '相关知识点（选填）',
              placeholderStyle: text.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              style: text.bodyMedium,
              prefix: Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Icon(CupertinoIcons.lightbulb,
                    color: scheme.onSurfaceVariant, size: 20),
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(color: scheme.outline, width: 1),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: _questionCtrl,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      style: text.bodyLarge,
                      placeholder: '输入你的学习问题…',
                      placeholderStyle: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      prefix: Padding(
                        padding: const EdgeInsets.only(left: 16, right: 8),
                        child: Icon(CupertinoIcons.pencil,
                            color: scheme.onSurfaceVariant, size: 20),
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius:
                            BorderRadius.circular(AppRadius.input),
                        border: Border.all(color: scheme.outline, width: 1),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: CupertinoButton.filled(
                      borderRadius:
                          BorderRadius.circular(AppRadius.button),
                      onPressed: _sending ? null : _send,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _sending
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CupertinoActivityIndicator(
                                      color: scheme.onPrimary, radius: 8),
                                )
                              : Icon(CupertinoIcons.paperplane_fill,
                                  size: 18, color: scheme.onPrimary),
                          const SizedBox(width: 8),
                          Text(
                            _sending ? '思考中' : '发送',
                            style: text.labelLarge
                                ?.copyWith(color: scheme.onPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcomeHint() {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl3),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xl3),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.banner),
              border: Border.all(
                  color: scheme.secondary.withValues(alpha: 0.2), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: scheme.outline, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Icon(CupertinoIcons.sparkles,
                      size: 36, color: scheme.secondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('有问题就问 AI 老师吧',
                    textAlign: TextAlign.center,
                    style: text.titleLarge?.copyWith(
                      color: scheme.onSecondaryContainer,
                    )),
                const SizedBox(height: AppSpacing.sm),
                Text('只讲学习内容，其他问题不回答哦',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSecondaryContainer.withValues(alpha: 0.85),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _messageList(
    BuildContext context,
    List<TutorMessage> messages, {
    bool thinking = false,
  }) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final items = thinking ? [...messages, _thinkingBubble] : messages;
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.md),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final m = items[i];
        final isChild = m.role == 'child';
        return Align(
          alignment:
              isChild ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(AppSpacing.md),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            decoration: BoxDecoration(
              color: isChild
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.bubble),
              border: Border.all(
                color: isChild
                    ? scheme.primary.withValues(alpha: 0.35)
                    : scheme.outline,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.text,
                    style: text.bodyMedium?.copyWith(
                      color: isChild
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                      height: 1.55,
                    )),
                if (m.blocked)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.shield,
                              size: 14, color: scheme.onErrorContainer),
                          const SizedBox(width: 4),
                          Text('已启用内容安全保护',
                              style: text.labelSmall?.copyWith(
                                  color: scheme.onErrorContainer,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _thinkingBubble = TutorMessage(
    role: 'ai',
    text: 'AI 老师正在思考…',
  );
}