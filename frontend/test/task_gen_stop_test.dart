import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/assistant/domain/assistant_event.dart';
import 'package:kids_learn/features/assistant/domain/assistant_requests.dart';
import 'package:kids_learn/features/assistant/domain/conversation.dart';
import 'package:kids_learn/features/assistant/domain/repositories/assistant_repository.dart';
import 'package:kids_learn/features/home/domain/repositories/tasks_repository.dart';
import 'package:kids_learn/features/home/presentation/providers/home_notifier.dart';
import 'package:kids_learn/shared/domain/models/models.dart';

/// 复刻 question_gen_fold_test 的题卡构造，避免跨文件依赖。
AssistantEvent questionCard(String stem) => AssistantEvent(
      eventType: AssistantEventType.data,
      data: {
        'type': 'question',
        'result': {
          'stem': stem,
          'subject': '数学',
          'grade': 2,
          'qtype': 'calc',
        },
      },
    );

/// 受控 assistant：generate 发两题后卡在「第 2→3 题」的间隔，模拟逐题串行出题。
class _FakeAssistant extends AssistantRepository {
  final Completer<void> _resume = Completer<void>();

  void release() => _resume.complete();

  @override
  Stream<AssistantEvent> generate(TaskGenerateReq req) async* {
    yield questionCard('第1题');
    yield questionCard('第2题');
    // 卡在间隔里：此时测试调用 stop()，循环停在 await for、_stopped 已置位。
    await _resume.future;
  }

  @override
  Stream<AssistantEvent> chat(AssistantChatReq req) => throw UnimplementedError();
  @override
  Stream<AssistantEvent> regenerateOne({
    required String taskId,
    required String tqId,
  }) =>
      throw UnimplementedError();
  @override
  Future<List<AssistantConversation>> conversations() =>
      throw UnimplementedError();
  @override
  Future<AssistantConversationDetail> conversationDetail(String id) =>
      throw UnimplementedError();
  @override
  Future<int> deleteConversations(List<String> ids) =>
      throw UnimplementedError();
  @override
  ScheduledDeleteHandle scheduleDelete(
    List<String> ids, {
    required Future<void> Function() onConfirm,
    Duration window = const Duration(seconds: 5),
  }) =>
      throw UnimplementedError();
  @override
  bool cancelScheduledDelete(String handleId) => throw UnimplementedError();
}

class _FakeTasks extends TasksRepository {
  @override
  Future<List<TaskModel>> todayTasks() => throw UnimplementedError();
  @override
  Future<TaskPage> parentTasks({
    String? status,
    String? cursor,
    int pageSize = 20,
  }) =>
      throw UnimplementedError();
  @override
  Future<ProgressModel> progress(String childId) => throw UnimplementedError();
  @override
  Future<MasteryModel> mastery(String childId) => throw UnimplementedError();
  @override
  Future<TaskModel> persistGenerated(Map<String, dynamic> body) =>
      throw UnimplementedError();
}

void main() {
  test('stop() 在生成中调用：保留已出题目并转待确认态（ADR-0057 Q1=B）', () async {
    final assistant = _FakeAssistant();
    final notifier = TaskGenNotifier(_FakeTasks(), assistant);

    // 不 await：流由 _resume 控制，generate 在 release 前不会自然结束。
    final future = notifier.generate(
      childId: 'c1',
      title: '单元测',
      specs: [
        TaskSpecModel(
          subject: '数学',
          grade: 2,
          knowledgePoint: '进位加法',
          qtype: 'calc',
          count: 3,
        ),
      ],
    );

    // 等两题被 await for 消费完（卡在间隔里，不会发第 3 题）。
    await Future.delayed(const Duration(milliseconds: 20));
    expect(notifier.state, isA<TaskGenPreview>());
    expect((notifier.state as TaskGenPreview).questions.length, 2);

    // 主动停止：在当前题边界中断，已出的 2 题原样保留。
    notifier.stop();
    final r1 = notifier.state;
    expect(r1, isA<TaskGenReady>());
    final ready = r1 as TaskGenReady;
    expect(ready.stopped, isTrue);
    expect(ready.questions.length, 2); // 已出的题不丢
    expect(ready.expected, 3); // 应出题数照常带入，供「少题」判据

    // 释放间隔：流自然结束，stopped 仍是 true，题数不变。
    assistant.release();
    await future;
    final r2 = notifier.state as TaskGenReady;
    expect(r2.stopped, isTrue);
    expect(r2.questions.length, 2);
  });
}
