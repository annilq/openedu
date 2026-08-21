import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../providers/practice_notifier.dart';

/// 做题页。v2 redesign：
/// - 选项改卡片式（非 ElevatedButton），选中态用植物绿容器 + 2px 主色描边
/// - 提交按钮答案为空时禁用
/// - 结果图标颜色改用主题 tertiary / error 体系
/// - 完成页卡片式氛围，与首页 Banner 视觉一致
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
    final scheme = AppTheme.colorsOf(context);
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: result.correct
                    ? scheme.tertiaryContainer
                    : scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                result.correct
                    ? CupertinoIcons.checkmark
                    : CupertinoIcons.refresh,
                size: 22,
                color: result.correct
                    ? scheme.onTertiaryContainer
                    : scheme.onErrorContainer,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                result.correct ? '答对啦' : '再想想',
                style: TextStyle(
                  color: result.correct
                      ? scheme.onTertiaryContainer
                      : scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
        content: Text(result.explanation.isEmpty
            ? (result.correct ? '做得不错，继续加油～' : '没关系，记住下次就好')
            : result.explanation),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('继续'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final state = ref.watch(practiceNotifierProvider);

    // 答题结果弹窗（仅在题号推进时触发）
    ref.listen<PracticeState>(practiceNotifierProvider, (prev, next) {
      if (prev is Practicing && next is Practicing) {
        if (next.currentIndex > prev.currentIndex) {
          final result = prev.results[prev.currentQuestion.id];
          if (result != null) _showResult(context, result);
        }
      }
    });

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.task.title, overflow: TextOverflow.ellipsis),
        trailing: state is Practicing
            ? Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xl),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${state.currentIndex + 1}/${widget.task.questions.length}',
                    style: AppTheme.textOf(context).labelMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
              )
            : null,
      ),
      child: switch (state) {
        PracticeIdle() => const AppLoading(message: '准备中...'),
        Practicing() => _buildQuestionView(state),
        PracticeDone() => _buildDoneView(context, state),
        PracticeError() => AppError(
            message: state.message,
            onRetry: () =>
                ref.read(practiceNotifierProvider.notifier).startTask(widget.task),
          ),
      },
    );
  }

  Widget _buildQuestionView(Practicing state) {
    final scheme = AppTheme.colorsOf(context);
    final q = state.currentQuestion;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 知识点标签（AppTags 语义化）
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppTags.normal(widget.task.subject),
                  AppTags.normal('${widget.task.grade}年级'),
                  AppTags.info(q.knowledgePoint),
                ],
              ),
              const SizedBox(height: AppSpacing.xl3),
              // 题干：卡片式包裹
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.xl2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.banner),
                  border: Border.all(color: scheme.outline, width: 1),
                ),
                child: Text(q.stem,
                    style: AppTheme.textOf(context).titleMedium),
              ),
              const SizedBox(height: AppSpacing.xl3),
              // 选项 / 输入
              if (q.options != null && q.options!.isNotEmpty)
                ...q.options!.asMap().entries.map((e) {
                  final idx = e.key;
                  final opt = e.value;
                  return _OptionTile(
                    index: idx,
                    text: opt,
                    selected: _selectedOption == opt,
                    onTap: () {
                      setState(() => _selectedOption = opt);
                      _answerController.text = opt;
                    },
                  );
                })
              else
                CupertinoTextField(
                  controller: _answerController,
                  placeholder: '在此填写...',
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  style: AppTheme.textOf(context).bodyLarge,
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: scheme.outline, width: 1),
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              const SizedBox(height: AppSpacing.xl4),
              CupertinoButton.filled(
                borderRadius: BorderRadius.circular(AppRadius.button),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                onPressed: _answerReady ? () => _submit(q.id) : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.paperplane_fill,
                        size: 20, color: scheme.onPrimary),
                    const SizedBox(width: 8),
                    Text('提交答案',
                        style: AppTheme.textOf(context)
                            .labelLarge
                            ?.copyWith(color: scheme.onPrimary)),
                  ],
                ),
              ),
              // 答案为空时的友好提示
              if (!_answerReady)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Center(
                    child: Text('请先选择或输入答案再提交',
                        style: AppTheme.textOf(context).labelSmall),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDoneView(BuildContext context, PracticeDone state) {
    final scheme = AppTheme.colorsOf(context);
    final correct = state.correctCount;
    final total = state.total;
    final perfect = correct == total;
    final accuracy = (correct / total * 100).round();
    // 按正确率分级配色，仍用主题色系（不用 amber/green 默认值）
    final tone = switch (accuracy) {
      >= 90 => ResultTone.positive,
      >= 70 => ResultTone.warm,
      >= 40 => ResultTone.alert,
      _ => ResultTone.neutral,
    };
    final (iconBg, iconFg, iconData) = switch (tone) {
      ResultTone.positive => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          CupertinoIcons.rosette
        ),
      ResultTone.warm => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          CupertinoIcons.hand_thumbsup_fill
        ),
      ResultTone.alert => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          CupertinoIcons.chart_bar
        ),
      ResultTone.neutral => (
          scheme.surfaceContainerHigh,
          scheme.onSurface,
          CupertinoIcons.checkmark_circle_fill
        ),
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl3),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xl3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.banner),
              border: Border.all(color: scheme.outline, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(36),
                  ),
                  alignment: Alignment.center,
                  child: Icon(iconData, size: 56, color: iconFg),
                ),
                const SizedBox(height: AppSpacing.xl2),
                Text(
                  perfect ? '全部答对！' : '完成练习',
                  style: AppTheme.textOf(context).headlineMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$correct / $total 正确 · 正确率 $accuracy%',
                  style: AppTheme.textOf(context).bodyLarge,
                ),
                const SizedBox(height: AppSpacing.xl3),
                // 结果细节条
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 12,
                    child: AppProgressBar(
                      value: (correct / total).clamp(0.0, 1.0),
                      height: 12,
                      color: scheme.primary,
                      trackColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl4),
                CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  onPressed: () async {
                    await ref
                        .read(practiceNotifierProvider.notifier)
                        .checkin(widget.task.id);
                    if (!mounted) return;
                    ref.read(practiceNotifierProvider.notifier).reset();
                    widget.onDone?.call();
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.checkmark_circle_fill,
                          size: 20, color: scheme.onPrimary),
                      const SizedBox(width: 8),
                      Text('完成打卡',
                          style: AppTheme.textOf(context)
                              .labelLarge
                              ?.copyWith(color: scheme.onPrimary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// 私有组件
// =====================================================================

/// 选项卡：A/B/C/D 前缀 + 文本。非按钮外观。
class _OptionTile extends StatelessWidget {
  final int index;
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({
    required this.index,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final letter =
        index < _letters.length ? _letters[index] : '${index + 1}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : scheme.outline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    letter,
                    style: AppTheme.textOf(context).labelLarge?.copyWith(
                          color: selected
                              ? scheme.onPrimary
                              : scheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(text,
                        style: AppTheme.textOf(context).bodyLarge?.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurface,
                            )),
                  ),
                ),
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: AppSpacing.md),
                    child: Icon(CupertinoIcons.checkmark_circle_fill,
                        color: scheme.primary, size: 24),
                  ),
              ],
            ),
          ),
        ),
    );
  }
}
