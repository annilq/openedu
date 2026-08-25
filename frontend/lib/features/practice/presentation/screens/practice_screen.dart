import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_answer_result_dialog.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../providers/practice_notifier.dart';
import '../widgets/practice_done_view.dart';
import '../widgets/practice_question_view.dart';

/// 做题页。v2 redesign：
/// - 选项改卡片式（AppOptionTile），选中态用植物绿容器 + 2px 主色描边
/// - 提交按钮答案为空时禁用
/// - 结果弹窗与完成页复用共享组件（AppAnswerResultDialog / AppQuizResultCard）
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(practiceNotifierProvider.notifier).startTask(widget.task);
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  bool get _answerReady {
    final q = _currentQuestion;
    if (q == null) return false;
    if (q.options != null && q.options!.isNotEmpty) return _selectedOption != null;
    return _answerController.text.trim().isNotEmpty;
  }

  QuestionModel? get _currentQuestion {
    final state = ref.read(practiceNotifierProvider);
    return state is Practicing ? state.currentQuestion : null;
  }

  void _submit(String questionId) {
    final answer = _selectedOption ?? _answerController.text.trim();
    if (answer.isEmpty) return;
    ref.read(practiceNotifierProvider.notifier).submitAnswer(questionId, answer);
    _answerController.clear();
    setState(() => _selectedOption = null);
  }

  void _showResult(BuildContext context, AnswerResultModel result) {
    AppAnswerResultDialog.show(
      context,
      correct: result.correct,
      title: result.correct ? '答对啦' : '再想想',
      content: Text(
        result.explanation.isEmpty
            ? (result.correct ? '做得不错，继续加油～' : '没关系，记住下次就好')
            : result.explanation,
        style: AppTheme.textOf(context).bodyMedium,
      ),
      animateIcon: true,
    );
  }

  Future<void> _checkin() async {
    await ref.read(practiceNotifierProvider.notifier).checkin(widget.task.id);
    if (!mounted) return;
    ref.read(practiceNotifierProvider.notifier).reset();
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final state = ref.watch(practiceNotifierProvider);

    ref.listen<PracticeState>(practiceNotifierProvider, (prev, next) {
      if (prev is Practicing && next is Practicing) {
        if (next.currentIndex > prev.currentIndex) {
          final result = prev.results[prev.currentQuestion.id];
          if (result != null) _showResult(context, result);
        }
      }
    });

    return SizedBox.expand(
      child: ColoredBox(
        color: scheme.surface,
        child: Column(
          children: [
            AppTopBar(
              title: widget.task.title,
              showBack: true,
              trailing: state is Practicing
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: scheme.surfaceSunken,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${state.currentIndex + 1}/${widget.task.questions.length}',
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
                PracticeIdle() => const AppLoading(message: '准备中...'),
                Practicing() => PracticeQuestionView(
                    question: state.currentQuestion,
                    task: widget.task,
                    selectedOption: _selectedOption,
                    answerController: _answerController,
                    answerReady: _answerReady,
                    onOptionTap: (v) => setState(() {
                      _selectedOption = v;
                      _answerController.text = v;
                    }),
                    onAnswerChanged: () => setState(() {}),
                    onSubmit: () => _submit(state.currentQuestion.id),
                  ),
                PracticeDone() => PracticeDoneView(
                    correct: state.correctCount,
                    total: state.total,
                    onCheckin: _checkin,
                  ),
                PracticeError() => AppError(
                    message: state.message,
                    onRetry: () => ref
                        .read(practiceNotifierProvider.notifier)
                        .startTask(widget.task),
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}
