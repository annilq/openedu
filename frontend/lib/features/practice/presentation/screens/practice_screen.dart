import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_answer_result_dialog.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../providers/practice_notifier.dart';
import '../widgets/practice_question_view.dart';
import '../widgets/practice_review_view.dart';

/// 做题页。v2 redesign：
/// - 选项改卡片式（AppOptionTile），选中态用植物绿容器 + 2px 主色描边
/// - 提交按钮答案为空时禁用
/// - 结果弹窗与完成页复用共享组件（AppAnswerResultDialog / AppQuizResultCard）
class PracticeScreen extends ConsumerStatefulWidget {
  final TaskModel task;
  final VoidCallback? onDone;

  /// 家长只读预览模式：禁用提交/打卡，仅浏览题目；
  /// 显式「以娃娃身份代答」才进入交互态写入娃娃作答记录。
  final bool preview;

  const PracticeScreen({
    super.key,
    required this.task,
    this.onDone,
    this.preview = false,
  });

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  final _answerController = TextEditingController();
  String? _selectedOption;
  late bool _preview;

  @override
  void initState() {
    super.initState();
    _preview = widget.preview;
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
    if (state is Practicing) return state.currentQuestion;
    if (state is PracticeReview && state.correctingId != null) {
      return state.correctingQuestion;
    }
    return null;
  }

  void _submit(String questionId) {
    final answer = _selectedOption ?? _answerController.text.trim();
    if (answer.isEmpty) return;
    ref.read(practiceNotifierProvider.notifier).submitAnswer(questionId, answer);
    _answerController.clear();
    setState(() => _selectedOption = null);
  }

  /// 订正作答：复用练习批改，提交后弹结果并回到订正列表。
  Future<void> _submitCorrection(String questionId) async {
    final answer = _selectedOption ?? _answerController.text.trim();
    if (answer.isEmpty) return;
    final notifier = ref.read(practiceNotifierProvider.notifier);
    final result = await notifier.submitCorrection(questionId, answer);
    _answerController.clear();
    setState(() => _selectedOption = null);
    if (result != null && mounted) _showResult(context, result);
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

  /// 家长从只读预览切到真正作答：重置到第一题，此后提交/打卡将写入娃娃记录。
  void _enterInteractive() {
    setState(() => _preview = false);
    _answerController.clear();
    setState(() => _selectedOption = null);
    ref.read(practiceNotifierProvider.notifier).startTask(widget.task);
  }

  /// 只读预览翻页：仅本地切换当前题，不调用后端、不写作答记录。
  void _goTo(int index) {
    ref.read(practiceNotifierProvider.notifier).goTo(index);
  }

  Widget _buildPreviewBanner(AppColors scheme) {
    return Container(
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(LucideIcons.eye, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '家长预览（只读）· 仅查看，不会写入娃娃作答记录',
              style: AppTheme.textOf(context)
                  .bodySmall
                  ?.copyWith(color: scheme.onTertiaryContainer),
            ),
          ),
          ShadButton(
            height: 36,
            onPressed: _enterInteractive,
            leading: const Icon(LucideIcons.pencil, size: 16),
            child: const Text('以娃娃身份代答'),
          ),
        ],
      ),
    );
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

    // 订正作答子页：独立顶栏 + 返回列表。
    if (state is PracticeReview && state.correctingId != null) {
      return _buildCorrecting(state);
    }

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
            if (_preview) _buildPreviewBanner(scheme),
            Expanded(
              child: switch (state) {
                PracticeIdle() => const AppLoading(message: '准备中...'),
                Practicing() => PracticeQuestionView(
                    question: state.currentQuestion,
                    task: widget.task,
                    selectedOption: _selectedOption,
                    answerController: _answerController,
                    answerReady: _answerReady,
                    preview: _preview,
                    onOptionTap: (v) => setState(() {
                      _selectedOption = v;
                      _answerController.text = v;
                    }),
                    onAnswerChanged: () => setState(() {}),
                    onSubmit: _preview ? () {} : () => _submit(state.currentQuestion.id),
                    onNext: _preview ? () => _goTo(state.currentIndex + 1) : null,
                  ),
                PracticeReview() => PracticeReviewView(
                    task: state.task,
                    results: state.results,
                    onCorrect: (id) {
                      setState(() {
                        _selectedOption = null;
                        _answerController.clear();
                      });
                      ref
                          .read(practiceNotifierProvider.notifier)
                          .startCorrection(id);
                    },
                    onCommit: _checkin,
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

  /// 当场订正子页：独立顶栏（返回列表），复用 [PracticeQuestionView] 重新作答。
  Widget _buildCorrecting(PracticeReview state) {
    final scheme = AppTheme.colorsOf(context);
    final q = state.correctingQuestion;
    if (q == null) return const SizedBox.shrink();
    return SizedBox.expand(
      child: ColoredBox(
        color: scheme.surface,
        child: Column(
          children: [
            AppTopBar(
              title: '订正',
              leading: ShadButton.ghost(
                width: 40,
                height: 40,
                padding: EdgeInsets.zero,
                backgroundColor: const Color(0x00000000),
                hoverBackgroundColor: scheme.surfaceSunken,
                pressedBackgroundColor: scheme.surfaceRaised,
                onPressed: () =>
                    ref.read(practiceNotifierProvider.notifier).exitCorrection(),
                child: Icon(
                  LucideIcons.chevronLeft,
                  color: scheme.onSurface,
                  size: 24,
                ),
              ),
            ),
            Expanded(
              child: PracticeQuestionView(
                question: q,
                task: state.task,
                selectedOption: _selectedOption,
                answerController: _answerController,
                answerReady: _answerReady,
                preview: false,
                onOptionTap: (v) => setState(() {
                  _selectedOption = v;
                  _answerController.text = v;
                }),
                onAnswerChanged: () => setState(() {}),
                onSubmit: () => _submitCorrection(q.id),
                onNext: null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
