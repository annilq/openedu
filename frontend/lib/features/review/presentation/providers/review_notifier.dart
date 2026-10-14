import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/presentation/paging.dart';
import '../../../../shared/presentation/resource.dart';
import '../../domain/repositories/review_repository.dart';
import '../../providers/review_provider.dart';

/// 复习作答：与练习一致的批改结果（错题调度更新由后端完成）。
typedef ReviewAnswerResult = AnswerResultModel;

// —— 学生端：待复习队列（LCC-08）——
//
// 取一次就显示，但 `answer()` 会就地把已答题从当前列表移除（不重新拉取）。
// 故用自定义 notifier `with ResourceLoader`：load 走共享四态落法，answer 在
// ResourceLoaded 态直接替换 data，保持「答完最后一题不误清进度」的既有语义
// （load 经过 ResourceLoading 才清进度；answer 直达 ResourceLoaded 不触发清）。
class DueReviewNotifier
    extends StateNotifier<Resource<List<ReviewItemModel>>>
    with ResourceLoader<List<ReviewItemModel>> {
  final ReviewRepository _repo;
  DueReviewNotifier(this._repo) : super(const ResourceIdle());

  Future<void> load() => runLoad(_repo.dueReview);

  /// 过期则静默刷新（见 [ResourceLoader.refreshIfStaleFetch]）。
  Future<void> refreshIfStale() => refreshIfStaleFetch(_repo.dueReview);

  /// 提交一道复习作答；成功后从当前队列移除该题（无论对错，下一轮到期重新进入）。
  Future<ReviewAnswerResult?> answer(
      String wrongQuestionId, String studentAnswer) async {
    final current = state;
    if (current is! ResourceLoaded<List<ReviewItemModel>>) return null;
    try {
      final result = await _repo.answer(wrongQuestionId, studentAnswer);
      final remaining = current.data
          .where((i) => i.wrongQuestionId != wrongQuestionId)
          .toList();
      state = ResourceLoaded<List<ReviewItemModel>>(remaining);
      return result;
    } catch (e) {
      state = ResourceError<List<ReviewItemModel>>(e.toString());
      return null;
    }
  }
}

final dueReviewNotifierProvider = StateNotifierProvider<
    DueReviewNotifier,
    Resource<List<ReviewItemModel>>>(
  (ref) => DueReviewNotifier(ref.watch(reviewRepositoryProvider)),
);

// —— 错题本：学生自查 / 教师查看（游标分页，ADR-0053）——
//
// 错题本会一直长（答错即入集），一次拉全量会让教师端几百张卡全部构建出来。
// 改成首屏一页 + 触底追加后，卡片构建与网络载荷都随视口走。
/// 学生自查：错题本（不含答案）。
final childWrongQuestionsProvider = StateNotifierProvider<
    PagingNotifier<WrongQuestionModel>, PagingState<WrongQuestionModel>>(
  (ref) => PagingNotifier<WrongQuestionModel>(
    ({cursor}) => ref
        .watch(reviewRepositoryProvider)
        .childWrongQuestions(cursor: cursor),
  ),
);

/// 教师查看某学生的错题本（含答案）。
final teacherWrongQuestionsProvider = StateNotifierProvider<
    ParamPagingNotifier<WrongQuestionModel, String>,
    PagingState<WrongQuestionModel>>(
  (ref) => ParamPagingNotifier<WrongQuestionModel, String>(
    (studentId, {cursor}) => ref
        .watch(reviewRepositoryProvider)
        .teacherWrongQuestions(studentId, cursor: cursor),
  ),
);

/// 教师端「已掌握」分区（ADR-0053 P2）：毕业的错题不再删行，只读回顾 +
/// 可「重新加入复习」。与上面那份未毕业列表是两条独立的分页状态机——它们的
/// 查询条件不同，合一条会让「翻页」和「切分区」互相踩。
final teacherGraduatedWrongQuestionsProvider = StateNotifierProvider<
    ParamPagingNotifier<WrongQuestionModel, String>,
    PagingState<WrongQuestionModel>>(
  (ref) => ParamPagingNotifier<WrongQuestionModel, String>(
    (studentId, {cursor}) => ref
        .watch(reviewRepositoryProvider)
        .teacherWrongQuestions(studentId, cursor: cursor, scope: 'graduated'),
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
/// 同时出现在未毕业列表里。只刷一边会让教师点完看不到变化，以为没生效。
final rejoinWrongQuestionProvider =
    Provider<Future<void> Function(String studentId, String wrongId)>((ref) {
  return (studentId, wrongId) async {
    await ref
        .read(reviewRepositoryProvider)
        .rejoinWrongQuestion(studentId, wrongId);
    await ref.read(teacherWrongQuestionsProvider.notifier).load(studentId);
    await ref
        .read(teacherGraduatedWrongQuestionsProvider.notifier)
        .load(studentId);
  };
});
