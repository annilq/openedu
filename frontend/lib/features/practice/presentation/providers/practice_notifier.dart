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

class PracticeDone extends PracticeState {
  final TaskModel task;
  final Map<String, AnswerResultModel> results;

  PracticeDone(this.task, this.results);

  int get correctCount => results.values.where((r) => r.correct).length;
  int get total => task.questions.length;
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
        state = PracticeDone(current.task, newResults);
      } else {
        state = Practicing(current.task, nextIndex, newResults);
      }
    } catch (e) {
      state = PracticeError(e.toString());
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
