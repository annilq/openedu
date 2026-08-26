import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_answer_result_dialog.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_quiz_result_card.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../providers/review_notifier.dart';
import '../widgets/review_empty_view.dart';
import '../widgets/review_question_view.dart';

/// 娃娃端复习作答页：逐题作答遗忘曲线到期的错题。
/// v2 redesign：与 practice_screen 视觉一致（选项卡式答案、禁用提交、主题色弹窗）。
class ReviewScreen extends ConsumerStatefulWidget {
  final bool showBack;
  const ReviewScreen({super.key, this.showBack = true});

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

  bool _answerReady(ReviewItemModel item) {
    if (_submitting) return false;
    if (item.options != null && item.options!.isNotEmpty) {
      return _selectedOption != null;
    }
    return _answerController.text.trim().isNotEmpty;
  }

  Future<void> _submit(ReviewItemModel item) async {
    if (!_answerReady(item)) return;
    if (_submitting) return;
    final answer = _selectedOption ?? _answerController.text.trim();

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
    setState(() => _selectedOption = null);

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

  void _showResult(
      BuildContext context, AnswerResultModel result, ReviewItemModel item) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final nextIn = result.correct
        ? '下次 ${item.nextIntervalDays} 天后复习'
        : '已重新计时，明天再来';
    AppAnswerResultDialog.show(
      context,
      correct: result.correct,
      title: result.correct ? '复习答对啦' : '答错了，重新计时',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nextIn, style: text.bodyMedium),
          if (result.explanation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceSunken,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(result.explanation, style: text.bodyMedium),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDoneView(BuildContext context) {
    final accuracy = _totalCount > 0
        ? (_correctCount / _totalCount * 100).round()
        : 0;
    return AppQuizResultCard(
      correct: _correctCount,
      total: _totalCount,
      title: '复习完成！',
      subtitle: '答对 $_correctCount 题 · 正确率 $accuracy%',
      note: '记住的题会自动升级，错的题明天再来',
      trailing: AppPrimaryButton(
        label: '返回首页',
        onPressed: () => Navigator.of(context).pop(true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final state = ref.watch(dueReviewNotifierProvider);

    return SizedBox.expand(
      child: ColoredBox(
        color: scheme.surface,
        child: Column(
          children: [
            AppTopBar(
              title: '复习',
              showBack: widget.showBack,
              trailing: state is DueReviewLoaded && !_done && _totalCount > 0
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: scheme.surfaceSunken,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_currentIndex + 1}/$_totalCount',
                          style: AppTheme.textOf(context).labelMedium?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                        ),
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: switch (state) {
                DueReviewInitial() || DueReviewLoading() =>
                  const AppLoading(message: '加载待复习...'),
                DueReviewError() => AppError(
                    message: state.message,
                    onRetry: () =>
                        ref.read(dueReviewNotifierProvider.notifier).load(),
                  ),
                DueReviewLoaded() => _done
                    ? _buildDoneView(context)
                    : (state.items.isEmpty
                        ? const ReviewEmptyView()
                        : ReviewQuestionView(
                            item: state.items[_currentIndex
                                .clamp(0, state.items.length - 1)],
                            selectedOption: _selectedOption,
                            answerController: _answerController,
                            submitting: _submitting,
                            answerReady: _answerReady(state.items[_currentIndex
                                .clamp(0, state.items.length - 1)]),
                            onOptionTap: (v) => setState(() {
                              _selectedOption = v;
                              _answerController.text = v;
                            }),
                            onAnswerChanged: () => setState(() {}),
                            onSubmit: () => _submit(state.items[_currentIndex
                                .clamp(0, state.items.length - 1)]),
                          )),
              },
            ),
          ],
        ),
      ),
    );
  }
}
