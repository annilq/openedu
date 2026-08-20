import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../providers/review_notifier.dart';

/// 娃娃端复习作答页：逐题作答遗忘曲线到期的错题。
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _answerController = TextEditingController();
  String? _selectedOption;
  int _currentIndex = 0;
  int _totalCount = 0;
  bool _done = false;
  bool _submitting = false;
  int _correctCount = 0;

  @override
  void initState() {
    super.initState();
    // 队列加载完成时记录初始总数，供进度显示（答完会从队列移除）。
    ref.listen<DueReviewState>(dueReviewNotifierProvider, (prev, next) {
      if (next is DueReviewLoaded && !_done && _totalCount == 0) {
        _totalCount = next.items.length;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dueReviewNotifierProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _submit(ReviewItemModel item) async {
    if (_submitting) return;
    final answer = _selectedOption ?? _answerController.text.trim();
    if (answer.isEmpty) return;

    setState(() => _submitting = true);
    final result = await ref
        .read(dueReviewNotifierProvider.notifier)
        .answer(item.wrongQuestionId, answer);
    if (!mounted) return;

    if (result == null) {
      setState(() => _submitting = false);
      return;
    }

    if (result.correct) _correctCount++;
    _answerController.clear();
    _selectedOption = null;

    final nextState = ref.read(dueReviewNotifierProvider);
    if (nextState is DueReviewLoaded && nextState.items.isEmpty) {
      setState(() {
        _done = true;
        _submitting = false;
      });
    } else {
      setState(() {
        _currentIndex += 1;
        _submitting = false;
      });
    }
    _showResult(context, result, item);
  }

  void _showResult(BuildContext context, AnswerResultModel result, ReviewItemModel item) {
    final nextIn = result.correct ? '下次 ${item.nextIntervalDays} 天后复习' : '已重新计时，明天再来';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(result.correct ? '复习答对啦！' : '答错了，重新计时',
            style: TextStyle(color: result.correct ? Colors.green : Colors.orange)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nextIn),
            if (result.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(result.explanation),
            ],
          ],
        ),
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
    final state = ref.watch(dueReviewNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('复习'),
        actions: [
          if (state is DueReviewLoaded && !_done)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('${_currentIndex + 1}/$_totalCount',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
        ],
      ),
      body: switch (state) {
        DueReviewInitial() || DueReviewLoading() =>
          const AppLoading(message: '加载待复习...'),
        DueReviewError() => AppError(
            message: state.message,
            onRetry: () => ref.read(dueReviewNotifierProvider.notifier).load(),
          ),
        DueReviewLoaded() => _done
            ? _buildDoneView(context)
            : (state.items.isEmpty
                ? _buildEmptyView()
                : _buildQuestionView(state.items[_currentIndex.clamp(0, state.items.length - 1)])),
      },
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration, size: 72, color: Colors.green),
            const SizedBox(height: 16),
            Text('今天没有要复习的题', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('把错题复习掉，就能记住啦～'),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionView(ReviewItemModel item) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text(item.subject)),
              Chip(label: Text('年级 ${item.grade}')),
              Chip(label: Text(item.knowledgePoint)),
              Chip(label: Text('错过 ${item.wrongCount} 次')),
            ],
          ),
          const SizedBox(height: 24),
          Text(item.stem, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          if (item.options != null && item.options!.isNotEmpty)
            ...item.options!.map((opt) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedOption == opt
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    foregroundColor: _selectedOption == opt ? Colors.white : null,
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
              onPressed: () => _submit(item),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('提交复习'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events, size: 80, color: Colors.amber),
            const SizedBox(height: 16),
            Text('复习完成！答对 $_correctCount 题',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('记住的题会自动升级，错的题明天再来'),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('返回首页'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
