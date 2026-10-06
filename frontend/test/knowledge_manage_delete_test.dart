import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kids_learn/features/home/domain/repositories/material_repository.dart';
import 'package:kids_learn/features/home/providers/knowledge_manage_provider.dart';

class _MockRepo extends Mock implements MaterialRepository {}

/// 两个掉库知识点 + 两个骨架（id 为 null）。骨架是「确认才落库」的候选，
/// 在 DB 里还没有行 —— 这是「删除选中」必须处理好的边界。
final _curated = KnowledgePointOption(id: 'k1', name: '两位数乘法', status: 'curated');
final _pending = KnowledgePointOption(id: 'k2', name: '面积单位', status: 'pending');
final _skeleton = KnowledgePointOption(name: '骨架甲');

void main() {
  group('KnowledgeManageNotifier 删除选中', () {
    late _MockRepo repo;
    late KnowledgeManageNotifier notifier;

    setUp(() {
      repo = _MockRepo();
      when(() => repo.getKnowledgePointDirectory(
            subject: any(named: 'subject'),
            grade: any(named: 'grade'),
            semester: any(named: 'semester'),
          )).thenAnswer(
        (_) async => KnowledgePointDirectory(items: [
          _curated,
          _pending,
          _skeleton,
        ]),
      );
      when(() => repo.deleteKnowledgePoints(any())).thenAnswer((_) async => 2);
      notifier = KnowledgeManageNotifier(repo);
    });

    test('deletableSelectedCount 只数已落库的行', () async {
      await notifier.load();
      notifier.toggle('两位数乘法');
      expect(notifier.state.deletableSelectedCount, 1);

      notifier.toggle('骨架甲');
      // 骨架被勾上但删不掉：计数必须仍是 1，否则按钮会显示「删除选中（2）」
      // 而实际只删 1 条。
      expect(notifier.state.deletableSelectedCount, 1);
      expect(notifier.state.selectedNames.length, 2);
    });

    test('只把有 id 的知识点的 id 发给后端', () async {
      await notifier.load();
      notifier
        ..toggle('两位数乘法')
        ..toggle('骨架甲');

      await notifier.deleteSelected();

      verify(() => repo.deleteKnowledgePoints(['k1'])).called(1);
      expect(notifier.state.selectedNames, isEmpty);
      expect(notifier.state.notice, contains('已删除 2 个知识点'));
    });

    test('全勾骨架时不发起删除请求', () async {
      await notifier.load();
      notifier.toggle('骨架甲');

      await notifier.deleteSelected();

      verifyNever(() => repo.deleteKnowledgePoints(any()));
    });

    test('确认与删除共用同一份勾选，互不重置', () async {
      when(() => repo.confirmKnowledgePoints(
            subject: any(named: 'subject'),
            grade: any(named: 'grade'),
            names: any(named: 'names'),
            semester: any(named: 'semester'),
          )).thenAnswer((_) async {});
      await notifier.load();
      notifier.toggle('面积单位');

      await notifier.confirmSelected();
      expect(notifier.state.selectedNames, isEmpty, reason: '确认后清空勾选');

      // 删除是另一条动作：重新勾选后仍能独立触发。
      notifier.toggle('两位数乘法');
      await notifier.deleteSelected();
      verify(() => repo.deleteKnowledgePoints(['k1'])).called(1);
    });
  });
}
