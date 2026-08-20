import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';

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
sealed class WrongQuestionsState {
  const WrongQuestionsState();
}

class WrongQuestionsInitial extends WrongQuestionsState {
  const WrongQuestionsInitial();
}

class WrongQuestionsLoading extends WrongQuestionsState {
  const WrongQuestionsLoading();
}

class WrongQuestionsLoaded extends WrongQuestionsState {
  final List<WrongQuestionModel> items;
  const WrongQuestionsLoaded(this.items);
}

class WrongQuestionsError extends WrongQuestionsState {
  final String message;
  const WrongQuestionsError(this.message);
}

class WrongQuestionsNotifier extends StateNotifier<WrongQuestionsState> {
  final NetworkService _network;
  WrongQuestionsNotifier(this._network) : super(const WrongQuestionsInitial());

  /// childId 为空 → 娃娃自查（不含答案）；非空 → 家长查看（含答案）。
  Future<void> load({String? childId}) async {
    state = const WrongQuestionsLoading();
    try {
      final path = childId == null
          ? '/tasks/wrong-questions'
          : '/tasks/children/$childId/wrong-questions';
      final data = await _network.get(path);
      final items = (data as List)
          .map((e) => WrongQuestionModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = WrongQuestionsLoaded(items);
    } catch (e) {
      state = WrongQuestionsError(e.toString());
    }
  }
}

final childWrongQuestionsProvider =
    StateNotifierProvider<WrongQuestionsNotifier, WrongQuestionsState>((ref) {
  final network = ref.watch(networkServiceProvider);
  return WrongQuestionsNotifier(network);
});

final parentWrongQuestionsProvider =
    StateNotifierProvider<WrongQuestionsNotifier, WrongQuestionsState>((ref) {
  final network = ref.watch(networkServiceProvider);
  return WrongQuestionsNotifier(network);
});
