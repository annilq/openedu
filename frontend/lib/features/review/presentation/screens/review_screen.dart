import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../providers/review_notifier.dart';

/// 娃娃端复习作答页：逐题作答遗忘曲线到期的错题。
/// v2 redesign：与 practice_screen 视觉一致（选项卡式答案、禁用提交、主题色弹窗）。
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
    final nextIn = result.correct
        ? '下次 ${item.nextIntervalDays} 天后复习'
        : '已重新计时，明天再来';
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
                result.correct ? '复习答对啦' : '答错了，重新计时',
                style: TextStyle(
                  color: result.correct
                      ? scheme.onTertiaryContainer
                      : scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nextIn, style: AppTheme.textOf(context).bodyMedium),
            if (result.explanation.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(result.explanation,
                    style: AppTheme.textOf(context).bodyMedium),
              ),
            ],
          ],
        ),
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
    final state = ref.watch(dueReviewNotifierProvider);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('复习'),
        trailing: state is DueReviewLoaded && !_done && _totalCount > 0
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
                    '${_currentIndex + 1}/$_totalCount',
                    style: AppTheme.textOf(context).labelMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
              )
            : null,
      ),
      child: switch (state) {
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
                : _buildQuestionView(
                    state.items[_currentIndex.clamp(0, state.items.length - 1)])),
      },
    );
  }

  Widget _buildEmptyView() {
    final scheme = AppTheme.colorsOf(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl3),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xl4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.banner),
              border: Border.all(color: scheme.outline, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  alignment: Alignment.center,
                  child: Icon(CupertinoIcons.sparkles,
                      size: 48, color: scheme.onTertiaryContainer),
                ),
                const SizedBox(height: AppSpacing.xl2),
                Text('今天没有要复习的题',
                    textAlign: TextAlign.center,
                    style: AppTheme.textOf(context).headlineMedium),
                const SizedBox(height: AppSpacing.sm),
                Text('把错题复习掉，就能记得更牢～',
                    textAlign: TextAlign.center,
                    style: AppTheme.textOf(context).bodyMedium),
                const SizedBox(height: AppSpacing.xl4),
                AppPrimaryButton(
                  label: '返回',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionView(ReviewItemModel item) {
    final scheme = AppTheme.colorsOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  AppTags.normal(item.subject),
                  AppTags.normal('${item.grade}年级'),
                  AppTags.info(item.knowledgePoint),
                  AppTags.warning('错过 ${item.wrongCount} 次'),
                ],
              ),
              const SizedBox(height: AppSpacing.xl3),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.xl2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.banner),
                  border: Border.all(color: scheme.outline, width: 1),
                ),
                child: Text(item.stem,
                    style: AppTheme.textOf(context).titleMedium),
              ),
              const SizedBox(height: AppSpacing.xl3),
              if (item.options != null && item.options!.isNotEmpty)
                ...item.options!.asMap().entries.map((e) => _ReviewOptionTile(
                      index: e.key,
                      text: e.value,
                      selected: _selectedOption == e.value,
                      submitting: _submitting,
                      onTap: _submitting
                          ? null
                          : () {
                              setState(() => _selectedOption = e.value);
                              _answerController.text = e.value;
                            },
                    ))
              else
                CupertinoTextField(
                  controller: _answerController,
                  placeholder: '在此填写...',
                  enabled: !_submitting,
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
                onPressed: _answerReady(item) ? () => _submit(item) : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CupertinoActivityIndicator(
                                color: scheme.onPrimary, radius: 11),
                          )
                        : Icon(CupertinoIcons.paperplane_fill,
                            size: 20, color: scheme.onPrimary),
                    const SizedBox(width: 8),
                    Text(_submitting ? '判题中…' : '提交复习',
                        style: AppTheme.textOf(context)
                            .labelLarge
                            ?.copyWith(color: scheme.onPrimary)),
                  ],
                ),
              ),
              if (!_answerReady(item) && !_submitting)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Center(
                    child: Text('请先给出你的答案',
                        style: AppTheme.textOf(context).labelSmall),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDoneView(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final accuracy = _totalCount > 0
        ? (_correctCount / _totalCount * 100).round()
        : 0;
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
                Text('复习完成！',
                    style: AppTheme.textOf(context).headlineMedium),
                const SizedBox(height: AppSpacing.xs),
                Text('答对 $_correctCount 题 · 正确率 $accuracy%',
                    style: AppTheme.textOf(context).bodyLarge),
                const SizedBox(height: AppSpacing.sm),
                Text('记住的题会自动升级，错的题明天再来',
                    style: AppTheme.textOf(context).bodySmall),
                const SizedBox(height: AppSpacing.xl3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 12,
                    child: AppProgressBar(
                      value: _totalCount > 0
                          ? (_correctCount / _totalCount).clamp(0.0, 1.0)
                          : 0,
                      height: 12,
                      color: scheme.primary,
                      trackColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl4),
                AppPrimaryButton(
                  label: '返回首页',
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 复习页选项卡：与 practice_screen 的 _OptionTile 设计一致，单独声明避免耦合。
class _ReviewOptionTile extends StatelessWidget {
  final int index;
  final String text;
  final bool selected;
  final bool submitting;
  final VoidCallback? onTap;
  const _ReviewOptionTile({
    required this.index,
    required this.text,
    required this.selected,
    required this.submitting,
    required this.onTap,
  });

  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final letter = index < _letters.length ? _letters[index] : '${index + 1}';
    final disabled = submitting;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : onTap,
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
                color: selected ? scheme.primary : scheme.outline,
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
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
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
