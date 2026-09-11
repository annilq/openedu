import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';
import '../../../../shared/presentation/resource.dart';

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
  final NetworkService _network;
  DueReviewNotifier(this._network) : super(const DueReviewInitial());

  Future<void> load() async {
    state = const DueReviewLoading();
    try {
      final data = await _network.get('/review/due');
      final items = (data as List)
          .map((e) => ReviewItemModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = DueReviewLoaded(items);
    } catch (e) {
      state = DueReviewError(e.toString());
    }
  }

  /// 提交一道复习作答；成功后从当前队列移除该题（无论对错，下一轮到期重新进入）。
  Future<ReviewAnswerResult?> answer(String wrongQuestionId, String studentAnswer) async {
    final current = state;
    if (current is! DueReviewLoaded) return null;
    try {
      final data = await _network.post('/review/answer', body: {
        'wrong_question_id': wrongQuestionId,
        'student_answer': studentAnswer,
      });
      final result = AnswerResultModel.fromJson(data);
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
  final network = ref.watch(networkServiceProvider);
  return DueReviewNotifier(network);
});

// —— 错题本：娃娃自查 / 家长查看 ——
/// 娃娃自查：GET /tasks/wrong-questions（不含答案）。
final childWrongQuestionsProvider =
    StateNotifierProvider<ResourceNotifier<List<WrongQuestionModel>>,
        Resource<List<WrongQuestionModel>>>(
  (ref) => ResourceNotifier(
    ref.watch(networkServiceProvider),
    path: '/tasks/wrong-questions',
    parse: (d) => decodeList(d, WrongQuestionModel.fromJson),
  ),
);

/// 家长查看：GET /tasks/children/{id}/wrong-questions（含答案）。
final parentWrongQuestionsProvider = StateNotifierProvider<
    ParamResourceNotifier<List<WrongQuestionModel>, String>,
    Resource<List<WrongQuestionModel>>>(
  (ref) => ParamResourceNotifier(
    ref.watch(networkServiceProvider),
    pathOf: (childId) => '/tasks/children/$childId/wrong-questions',
    parse: (d) => decodeList(d, WrongQuestionModel.fromJson),
  ),
);
