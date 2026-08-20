import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../providers/practice_notifier.dart';

class PracticeScreen extends ConsumerStatefulWidget {
  final TaskModel task;
  final VoidCallback? onDone;

  const PracticeScreen({super.key, required this.task, this.onDone});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  final _answerController = TextEditingController();
  String? _selectedOption;

  @override
  void initState() {
    super.initState();
    // 初始化做题状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(practiceNotifierProvider.notifier).startTask(widget.task);
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  void _submit(String questionId) {
    final answer = _selectedOption ?? _answerController.text.trim();
    if (answer.isEmpty) return;
    ref.read(practiceNotifierProvider.notifier).submitAnswer(questionId, answer);
    _answerController.clear();
    _selectedOption = null;
  }

  void _showResult(BuildContext context, AnswerResultModel result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(result.correct ? '答对啦！' : '再想想',
            style: TextStyle(color: result.correct ? Colors.green : Colors.orange)),
        content: Text(result.explanation.isEmpty
            ? (result.correct ? '真棒！' : '下次更努力')
            : result.explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('继续'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(practiceNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task.title),
        actions: [
          if (state is Practicing)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('${state.currentIndex + 1}/${widget.task.questions.length}',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
        ],
      ),
      body: switch (state) {
        PracticeIdle() => const AppLoading(message: '准备中...'),
        Practicing() => _buildQuestionView(state),
        PracticeDone() => _buildDoneView(context, state),
        PracticeError() => AppError(
            message: state.message,
            onRetry: () => ref.read(practiceNotifierProvider.notifier).startTask(widget.task),
          ),
      },
    );
  }

  Widget _buildQuestionView(Practicing state) {
    final q = state.currentQuestion;

    // 监听答题结果
    ref.listen<PracticeState>(practiceNotifierProvider, (prev, next) {
      if (prev is Practicing && next is Practicing) {
        // 题号变了，说明刚答完一题
        if (next.currentIndex > prev.currentIndex) {
          final result = prev.results[prev.currentQuestion.id];
          if (result != null) _showResult(context, result);
        }
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 知识点标签
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text(widget.task.subject)),
              Chip(label: Text('年级 ${widget.task.grade}')),
              Chip(label: Text(q.knowledgePoint)),
            ],
          ),
          const SizedBox(height: 24),
          // 题目
          Text(q.stem, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          // 选项 / 输入
          if (q.options != null && q.options!.isNotEmpty)
            ...q.options!.map((opt) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedOption == opt
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    foregroundColor: _selectedOption == opt
                        ? Colors.white
                        : null,
                  ),
                  onPressed: () {
                    setState(() => _selectedOption = opt);
                    _answerController.text = opt;
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(opt, textAlign: TextAlign.left),
                  ),
                ),
              ),
            ))
          else
            TextField(
              controller: _answerController,
              decoration: const InputDecoration(
                labelText: '输入你的答案',
                hintText: '在此填写...',
              ),
            ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _submit(q.id),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('提交答案'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneView(BuildContext context, PracticeDone state) {
    final correct = state.correctCount;
    final total = state.total;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              correct == total ? Icons.emoji_events : Icons.check_circle,
              size: 80,
              color: correct == total ? Colors.amber : Colors.green,
            ),
            const SizedBox(height: 16),
            Text('完成！$correct / $total 正确',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('正确率 ${(correct / total * 100).round()}%',
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  // 尝试打卡
                  await ref.read(practiceNotifierProvider.notifier).checkin(widget.task.id);
                  ref.read(practiceNotifierProvider.notifier).reset();
                  widget.onDone?.call();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('完成打卡'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
