import 'package:flutter/material.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final nextIn = result.correct
        ? '下次 ${item.nextIntervalDays} 天后复习'
        : '已重新计时，明天再来';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
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
                result.correct ? Icons.check_rounded : Icons.refresh_rounded,
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
            Text(nextIn, style: Theme.of(context).textTheme.bodyMedium),
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
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('继续'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(dueReviewNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('复习'),
        actions: [
          if (state is DueReviewLoaded && !_done && _totalCount > 0)
            Padding(
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
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
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
                : _buildQuestionView(
                    state.items[_currentIndex.clamp(0, state.items.length - 1)])),
      },
    );
  }

  Widget _buildEmptyView() {
    final scheme = Theme.of(context).colorScheme;
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
                  child: Icon(Icons.celebration_rounded,
                      size: 48, color: scheme.onTertiaryContainer),
                ),
                const SizedBox(height: AppSpacing.xl2),
                Text('今天没有要复习的题',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.sm),
                Text('把错题复习掉，就能记得更牢～',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xl4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionView(ReviewItemModel item) {
    final scheme = Theme.of(context).colorScheme;
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
                    style: Theme.of(context).textTheme.titleMedium),
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
                TextField(
                  controller: _answerController,
                  onChanged: (_) => setState(() {}),
                  enabled: !_submitting,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    labelText: '输入你的答案',
                    hintText: '在此填写...',
                  ),
                ),
              const SizedBox(height: AppSpacing.xl4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _answerReady(item) ? () => _submit(item) : null,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                  label: Text(_submitting ? '判题中…' : '提交复习'),
                ),
              ),
              if (!_answerReady(item) && !_submitting)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Center(
                    child: Text('请先给出你的答案',
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDoneView(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          Icons.emoji_events_rounded
        ),
      ResultTone.warm => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          Icons.thumb_up_alt_rounded
        ),
      ResultTone.alert => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.auto_graph_rounded
        ),
      ResultTone.neutral => (
          scheme.surfaceContainerHigh,
          scheme.onSurface,
          Icons.check_circle_rounded
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
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.xs),
                Text('答对 $_correctCount 题 · 正确率 $accuracy%',
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: AppSpacing.sm),
                Text('记住的题会自动升级，错的题明天再来',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xl3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _totalCount > 0
                        ? (_correctCount / _totalCount).clamp(0.0, 1.0)
                        : 0,
                    minHeight: 12,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('返回首页'),
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
    final scheme = Theme.of(context).colorScheme;
    final letter = index < _letters.length ? _letters[index] : '${index + 1}';
    final disabled = submitting;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
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
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                    child: Icon(Icons.check_circle_rounded,
                        color: scheme.primary, size: 24),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
