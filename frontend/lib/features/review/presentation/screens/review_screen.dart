import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
import '../../../../shared/widgets/app_motion.dart';

/// 娃娃端复习作答页：逐题作答遗忘曲线到期的错题。
/// v2 redesign：与 practice_screen 视觉一致（选项卡式答案、禁用提交、主题色弹窗）。
class ReviewScreen extends ConsumerStatefulWidget {
  final bool showBack;

  /// 导出「今日复习」卷（ADR-0052 复习页入口）。
  ///
  /// 不在这里直接 push 导出预览页：按 ADR-0037，feature 之间不得横向互引，
  /// `features/review` 导入不了 `features/export`。由组合根（home）注入——
  /// 传 null 时不显示该入口。
  final VoidCallback? onExportDue;

  /// 离开本页的出口（「返回」/「返回首页」），由组合根注入。
  ///
  /// ⚠️ **本页不是 `Navigator.push` 出来的路由**：娃娃端它是导航空壳的一个页签
  /// （`IndexedStack` 常驻），底下压根没有可 pop 的路由。此时 `Navigator.pop`
  /// 弹的是**根导航栈的最后一条路由（整个 App）**——按一下就白屏，下一次重建还会
  /// 撞上 `NavigatorState.build` 的 `assert(_history.isNotEmpty)`。
  /// 所以「回哪儿」只能由壳说了算（切回首页页签），本页不许自己 pop。
  ///
  /// 没注入时退回 `Navigator.maybePop`：它在无可 pop 路由时是 no-op，
  /// 不会把根栈弹空（这也是 `AppTopBar` / `AppPushedPage` 的默认退路）。
  final VoidCallback? onExit;

  const ReviewScreen({
    super.key,
    this.showBack = true,
    this.onExportDue,
    this.onExit,
  });

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
    final text = AppTheme.textOf(context);
    final nextIn =
        result.correct ? '下次 ${item.nextIntervalDays} 天后复习' : '已重新计时，明天再来';
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
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: EdgeInsets.zero,
              child: Text(result.explanation, style: text.bodyMedium),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDoneView(BuildContext context) {
    final accuracy =
        _totalCount > 0 ? (_correctCount / _totalCount * 100).round() : 0;
    return AppQuizResultCard(
      correct: _correctCount,
      total: _totalCount,
      title: '复习完成！',
      subtitle: '答对 $_correctCount 题 · 正确率 $accuracy%',
      note: '记住的题会自动升级，错的题明天再来',
      trailing: AppPrimaryButton(
        label: '返回首页',
        onPressed: widget.onExit ?? () => Navigator.of(context).maybePop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final state = ref.watch(dueReviewNotifierProvider);

    ref.listen<DueReviewState>(dueReviewNotifierProvider, (prev, next) {
      // 重新拉取 = 新一轮复习：清掉上一轮的进度。不清的话 `_done` 一旦为真就
      // 永久为真——页签常驻不重建，之后就算有新题到期也只会停在上一次那张完成卡。
      // （`answer()` 直接给 `DueReviewLoaded`，不会经过 `DueReviewLoading`，
      //   所以答完最后一题不会被这里误清。）
      if (next is DueReviewLoading) {
        _done = false;
        _currentIndex = 0;
        _correctCount = 0;
        _totalCount = 0;
        return;
      }
      if (next is DueReviewLoaded && !_done && _totalCount == 0) {
        _totalCount = next.items.length;
      }
    });

    return SizedBox.expand(
      child: ColoredBox(
        color: scheme.surface,
        child: Column(
          children: [
            AppTopBar(
              // 进度跟着标题走，不塞进 trailing：顶栏尾部槽位只有 40px、按 ADR-0046
              // 只放得下**一个**图标行动。原写法把「打印图标 + 题号 chip」并排放进去，
              // 横向溢出 32px——超出的部分落在屏幕右缘之外被裁掉，等于这个计数根本
              // 没显示出来（溢出是渲染错误，不是「挤一点还能看」）。
              title: !_done && _totalCount > 0
                  ? '复习 ${_currentIndex + 1}/$_totalCount'
                  : '复习',
              showBack: widget.showBack,
              onBack: widget.onExit,
              trailing: widget.onExportDue != null &&
                      state is DueReviewLoaded &&
                      state.items.isNotEmpty
                  ? AppIconAction(
                      icon: LucideIcons.printer,
                      semanticLabel: '打印今日复习卷',
                      onPressed: widget.onExportDue,
                    )
                  : null,
            ),
            Expanded(
              child: switch (state) {
                DueReviewInitial() ||
                DueReviewLoading() =>
                  const AppLoading(message: '加载待复习...'),
                DueReviewError() => AppError(
                    message: state.message,
                    onRetry: () =>
                        ref.read(dueReviewNotifierProvider.notifier).load(),
                  ),
                DueReviewLoaded() => _done
                    ? _buildDoneView(context)
                    : (state.items.isEmpty
                        ? ReviewEmptyView(onBack: widget.onExit)
                        : PopIn(
                            // key 稳定 → 切到下一题时重放弹簧入场，已在屏上的不重放。
                            key: ValueKey<int>(_currentIndex),
                            child: ReviewQuestionView(
                              item: state.items[
                                  _currentIndex.clamp(0, state.items.length - 1)],
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
                            ),
                          )),
              },
            ),
          ],
        ),
      ),
    );
  }
}
