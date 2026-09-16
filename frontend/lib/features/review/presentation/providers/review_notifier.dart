import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/presentation/paging.dart';
import '../../domain/repositories/review_repository.dart';
import '../../providers/review_provider.dart';

/// 复习作答：与练习一致的批改结果（错题调度更新由后端完成）。
typedef ReviewAnswerResult = AnswerResultModel;

// —— 娃娃端：待复习队列 ——
sealed class DueReviewState {
  const DueReviewState();
}

class DueReviewInitial extends DueReviewState {
  const DueReviewInitial();
}

class DueReviewLoading extends DueReviewState {
  const DueReviewLoading();
}

class DueReviewLoaded extends DueReviewState {
  final List<ReviewItemModel> items;
  const DueReviewLoaded(this.items);
}

class DueReviewError extends DueReviewState {
  final String message;
  const DueReviewError(this.message);
}

class DueReviewNotifier extends StateNotifier<DueReviewState> {
  final ReviewRepository _repo;
  DueReviewNotifier(this._repo) : super(const DueReviewInitial());

  Future<void> load() async {
    state = const DueReviewLoading();
    try {
      state = DueReviewLoaded(await _repo.dueReview());
    } catch (e) {
      state = DueReviewError(e.toString());
    }
  }

  /// 提交一道复习作答；成功后从当前队列移除该题（无论对错，下一轮到期重新进入）。
  Future<ReviewAnswerResult?> answer(String wrongQuestionId, String studentAnswer) async {
    final current = state;
    if (current is! DueReviewLoaded) return null;
    try {
      final result = await _repo.answer(wrongQuestionId, studentAnswer);
      final remaining = current.items
          .where((i) => i.wrongQuestionId != wrongQuestionId)
          .toList();
      state = DueReviewLoaded(remaining);
      return result;
    } catch (e) {
      state = DueReviewError(e.toString());
      return null;
    }
  }
}

final dueReviewNotifierProvider =
    StateNotifierProvider<DueReviewNotifier, DueReviewState>((ref) {
  return DueReviewNotifier(ref.watch(reviewRepositoryProvider));
});

// —— 错题本：娃娃自查 / 家长查看（游标分页，ADR-0053）——
//
// 错题本会一直长（答错即入集），一次拉全量会让家长端几百张卡全部构建出来。
// 改成首屏一页 + 触底追加后，卡片构建与网络载荷都随视口走。
/// 娃娃自查：错题本（不含答案）。
final childWrongQuestionsProvider = StateNotifierProvider<
    PagingNotifier<WrongQuestionModel>, PagingState<WrongQuestionModel>>(
  (ref) => PagingNotifier<WrongQuestionModel>(
    ({cursor}) => ref
        .watch(reviewRepositoryProvider)
        .childWrongQuestions(cursor: cursor),
  ),
);

/// 家长查看某娃娃的错题本（含答案）。
final parentWrongQuestionsProvider = StateNotifierProvider<
    ParamPagingNotifier<WrongQuestionModel, String>,
    PagingState<WrongQuestionModel>>(
  (ref) => ParamPagingNotifier<WrongQuestionModel, String>(
    (childId, {cursor}) => ref
        .watch(reviewRepositoryProvider)
        .parentWrongQuestions(childId, cursor: cursor),
  ),
);

/// 家长端「已掌握」分区（ADR-0053 P2）：毕业的错题不再删行，只读回顾 +
/// 可「重新加入复习」。与上面那份未毕业列表是两条独立的分页状态机——它们的
/// 查询条件不同，合一条会让「翻页」和「切分区」互相踩。
final parentGraduatedWrongQuestionsProvider = StateNotifierProvider<
    ParamPagingNotifier<WrongQuestionModel, String>,
    PagingState<WrongQuestionModel>>(
  (ref) => ParamPagingNotifier<WrongQuestionModel, String>(
    (childId, {cursor}) => ref
        .watch(reviewRepositoryProvider)
        .parentWrongQuestions(childId, cursor: cursor, scope: 'graduated'),
  ),
);

/// 「已掌握（N）」里的 N：**全量**计数，由服务端随页下发（ADR-0053 P2）。
///
/// 不能拿已加载的页统计——那是 P0 刚修掉的老问题（徽标只能统计已加载页）。
int graduatedTotalOf(PagingState<WrongQuestionModel> state) => switch (state) {
      PagingLoaded<WrongQuestionModel>(page: final p) =>
        p is WrongQuestionPage ? p.graduatedTotal : 0,
      _ => 0,
    };

/// 把一条「已掌握」的错题重新加入复习，并同步两条列表。
///
/// 成功后必须**两边都刷**：它从「已掌握」里消失（清了 graduated_at），
/// 同时出现在未毕业列表里。只刷一边会让家长点完看不到变化，以为没生效。
final rejoinWrongQuestionProvider =
    Provider<Future<void> Function(String childId, String wrongId)>((ref) {
  return (childId, wrongId) async {
    await ref
        .read(reviewRepositoryProvider)
        .rejoinWrongQuestion(childId, wrongId);
    await ref.read(parentWrongQuestionsProvider.notifier).load(childId);
    await ref
        .read(parentGraduatedWrongQuestionsProvider.notifier)
        .load(childId);
  };
});
