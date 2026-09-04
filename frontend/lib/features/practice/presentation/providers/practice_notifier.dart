import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';

/// 做题状态机
sealed class PracticeState {
  const PracticeState();
}

class PracticeIdle extends PracticeState {
  const PracticeIdle();
}

class Practicing extends PracticeState {
  final TaskModel task;
  final int currentIndex;
  final Map<String, AnswerResultModel> results;

  Practicing(this.task, this.currentIndex, this.results);

  int get answeredCount => results.length;
  int get correctCount => results.values.where((r) => r.correct).length;
  bool get allAnswered => results.length >= task.questions.length;
  QuestionModel get currentQuestion => task.questions[currentIndex];
}

class PracticeReview extends PracticeState {
  final TaskModel task;
  final Map<String, AnswerResultModel> results;

  /// null = 订正列表视图；非 null = 正在订正该 questionId。
  final String? correctingId;

  PracticeReview(this.task, this.results, [this.correctingId]);

  int get correctCount => results.values.where((r) => r.correct).length;
  int get total => task.questions.length;

  /// 当前仍答错的题目（提交后待订正 / 订正后仍错的）。
  List<QuestionModel> get wrongQuestions => task.questions
      .where((q) => results[q.id]?.correct == false)
      .toList();

  QuestionModel? get correctingQuestion {
    if (correctingId == null) return null;
    for (final q in task.questions) {
      if (q.id == correctingId) return q;
    }
    return null;
  }
}

class PracticeError extends PracticeState {
  final String message;
  const PracticeError(this.message);
}

class PracticeNotifier extends StateNotifier<PracticeState> {
  final NetworkService _network;

  PracticeNotifier(this._network) : super(const PracticeIdle());

  void startTask(TaskModel task) {
    state = Practicing(task, 0, {});
  }

  /// 仅本地翻页（家长只读预览用）：不调用后端、不写作答记录。
  void goTo(int index) {
    final current = state;
    if (current is! Practicing) return;
    if (index < 0 || index >= current.task.questions.length) return;
    state = Practicing(current.task, index, current.results);
  }

  Future<void> submitAnswer(String questionId, String answer) async {
    final current = state;
    if (current is! Practicing) return;

    try {
      final data = await _network.post(
        '/tasks/${current.task.id}/answer',
        body: {
          'question_id': questionId,
          'student_answer': answer,
        },
      );
      final result = AnswerResultModel.fromJson(data);

      final newResults = Map<String, AnswerResultModel>.from(current.results);
      newResults[questionId] = result;

      final nextIndex = current.currentIndex + 1;
      if (nextIndex >= current.task.questions.length) {
        // 全部作答完毕 → 进入订正阶段（汇总错题 + 当场订正），而非直接终态。
        state = PracticeReview(current.task, newResults);
      } else {
        state = Practicing(current.task, nextIndex, newResults);
      }
    } catch (e) {
      state = PracticeError(e.toString());
    }
  }

  /// 进入某道错题的订正作答（当场订正）。correctingId 非空即代表订正态。
  void startCorrection(String questionId) {
    final current = state;
    if (current is! PracticeReview) return;
    state = PracticeReview(current.task, current.results, questionId);
  }

  /// 退出订正作答，回到订正列表。
  void exitCorrection() {
    final current = state;
    if (current is! PracticeReview) return;
    state = PracticeReview(current.task, current.results, null);
  }

  /// 订正作答：复用练习批改接口重新判分，就地覆盖该题结果（不新增 AnswerRecord 之外的副作用）。
  /// 答对即从待订正列表移除；答错保持/回到待订正。不直接推进遗忘曲线（与排期复习解耦）。
  Future<AnswerResultModel?> submitCorrection(
      String questionId, String answer) async {
    final current = state;
    if (current is! PracticeReview) return null;

    try {
      final data = await _network.post(
        '/tasks/${current.task.id}/answer',
        body: {
          'question_id': questionId,
          'student_answer': answer,
        },
      );
      final result = AnswerResultModel.fromJson(data);

      final newResults = Map<String, AnswerResultModel>.from(current.results);
      newResults[questionId] = result;
      state = PracticeReview(current.task, newResults, null);
      return result;
    } catch (e) {
      state = PracticeError(e.toString());
      return null;
    }
  }

  Future<bool> checkin(String taskId) async {
    try {
      await _network.post('/tasks/$taskId/checkin');
      return true;
    } catch (_) {
      return false;
    }
  }

  void reset() => state = const PracticeIdle();
}

final practiceNotifierProvider =
    StateNotifierProvider<PracticeNotifier, PracticeState>((ref) {
  final network = ref.watch(networkServiceProvider);
  return PracticeNotifier(network);
});
