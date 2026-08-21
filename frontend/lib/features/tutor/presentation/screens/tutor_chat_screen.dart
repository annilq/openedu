import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../providers/tutor_notifier.dart';

/// 娃娃端 AI 伴学答疑页（F-302）：自由提问，AI 给出适龄讲解。
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

  // 内容安全提示（底层已拦截，这里仅做友好提示）
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
    super.dispose();
  }

  Future<void> _send() async {
    final question = _questionCtrl.text.trim();
    if (question.isEmpty || _sending) return;
    // 上次请求仍在进行（如离开页面再返回，_sending 已复位但 notifier 仍 Loading）：
    // 直接忽略，避免输入框先被清空、又被 notifier 防重入拦截导致内容静默丢失。
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
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tutorNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('问 AI 老师')),
      body: Column(
        children: [
          // 学科 / 年级选择
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                DropdownButton<String>(
                  value: _subject,
                  items: _subjects
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _subject = v ?? '数学'),
                ),
                const SizedBox(width: 16),
                Text('$_grade年级', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const Divider(height: 16),
          // 对话区
          Expanded(
            child: switch (state) {
              TutorInitial() => const Center(
                  child: Text('有问题就问 AI 老师吧～\n只讲学习内容哦',
                      textAlign: TextAlign.center),
                ),
              // Loading 与 Loaded 共用消息渲染；Loading 末尾追加「思考中」占位
              TutorLoading(:final messages) =>
                _messageList(context, messages, thinking: true),
              TutorLoaded(:final messages) => messages.isEmpty
                  ? const Center(child: Text('开始提问吧'))
                  : _messageList(context, messages),
            },
          ),
          // 知识点（可选）+ 提问输入
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _kpCtrl,
              decoration: const InputDecoration(
                labelText: '相关知识点（选填）',
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _questionCtrl,
                      enabled: !_sending,
                      decoration: const InputDecoration(
                        hintText: '输入你的学习问题…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('发送'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 渲染对话气泡列表；thinking=true 时末尾追加「AI 正在思考…」占位。
  Widget _messageList(
    BuildContext context,
    List<TutorMessage> messages, {
    bool thinking = false,
  }) {
    final items = thinking ? [...messages, _thinkingBubble] : messages;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final m = items[i];
        final isChild = m.role == 'child';
        return Align(
          alignment:
              isChild ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            decoration: BoxDecoration(
              color: isChild
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.text),
                if (m.blocked)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('（已启用内容安全保护）',
                        style: TextStyle(fontSize: 11, color: Colors.orange)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// AI 回复前的占位气泡。
  static const _thinkingBubble = TutorMessage(
    role: 'ai',
    text: 'AI 老师正在思考…',
  );
}
