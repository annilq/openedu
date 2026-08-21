import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../providers/tutor_notifier.dart';

/// 娃娃端 AI 伴学答疑页。v2 redesign：
/// - DropdownButton(无框) → DropdownButtonFormField（与全局输入框一致）
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('问 AI 老师')),
      body: Column(
        children: [
          // 学科 / 年级选择：统一 DropdownButtonFormField 风格
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, 0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _subject,
                    decoration: const InputDecoration(
                      labelText: '学科',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: _subjects
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _subject = v ?? '数学'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '年级',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    child: Text('$_grade年级',
                        style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, thickness: 1),
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
            padding:
                const EdgeInsets.fromLTRB(AppSpacing.xl2, AppSpacing.sm, AppSpacing.xl2, 0),
            child: TextField(
              controller: _kpCtrl,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: const InputDecoration(
                labelText: '相关知识点（选填）',
                prefixIcon: Icon(Icons.lightbulb_outline_rounded),
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
                    child: TextField(
                      controller: _questionCtrl,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: '输入你的学习问题…',
                        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        prefixIcon: const Icon(Icons.edit_note_rounded),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: FilledButton.icon(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                      label: Text(_sending ? '思考中' : '发送'),
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
    final scheme = Theme.of(context).colorScheme;
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
                  child: Icon(Icons.smart_toy_rounded,
                      size: 36, color: scheme.secondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('有问题就问 AI 老师吧',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: scheme.onSecondaryContainer,
                        )),
                const SizedBox(height: AppSpacing.sm),
                Text('只讲学习内容，其他问题不回答哦',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
    final scheme = Theme.of(context).colorScheme;
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                          Icon(Icons.shield_outlined,
                              size: 14, color: scheme.onErrorContainer),
                          const SizedBox(width: 4),
                          Text('已启用内容安全保护',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
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
