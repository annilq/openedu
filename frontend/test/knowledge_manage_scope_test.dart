import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kids_learn/features/home/domain/repositories/material_repository.dart';
import 'package:kids_learn/features/home/providers/knowledge_manage_provider.dart';

class _MockRepo extends Mock implements MaterialRepository {}

/// 教师的提问原型：只传了 4 年级数学上下册 + 2 年级语文上册 → 范围里就该只有这三项。
final _scopes = [
  const KnowledgePointScope(
      subject: '数学', grade: 4, semester: '上学期', materialCount: 1),
  const KnowledgePointScope(
      subject: '数学', grade: 4, semester: '下学期', materialCount: 1),
  const KnowledgePointScope(
      subject: '语文', grade: 2, semester: '上学期', materialCount: 2),
];

KnowledgePointDirectory _dir(List<String> names) => KnowledgePointDirectory(
      items: [
        for (final n in names) KnowledgePointOption(id: 'id-$n', name: n),
      ],
    );

void main() {
  group('知识点管理范围（ADR-0065）', () {
    late _MockRepo repo;
    late KnowledgeManageNotifier notifier;

    setUp(() {
      repo = _MockRepo();
      when(() => repo.getKnowledgePointScopes()).thenAnswer(
        (_) async => KnowledgePointScopeList(scopes: _scopes, unscopedCount: 0),
      );
      when(() => repo.getKnowledgePointDirectory(
            subject: any(named: 'subject'),
            grade: any(named: 'grade'),
            semester: any(named: 'semester'),
          )).thenAnswer((_) async => _dir(['甲']));
      notifier = KnowledgeManageNotifier(repo);
    });

    test('入口落到第一个真实有教材的范围', () async {
      await notifier.loadScopes();

      expect(notifier.state.subject, '数学');
      expect(notifier.state.grade, 4);
      // 默认给「整学年」并集：只传了上册时切到「下学期」会看到空列表，
      // 教师的第一反应是「联动坏了」，所以默认必须是并集。
      expect(notifier.state.semester, '');
      verify(() => repo.getKnowledgePointDirectory(
            subject: '数学',
            grade: 4,
            semester: '',
          )).called(1);
    });

    test('一份教材都没传：整页空态，连目录接口都不打', () async {
      when(() => repo.getKnowledgePointScopes())
          .thenAnswer((_) async => const KnowledgePointScopeList());

      await notifier.loadScopes();

      expect(notifier.state.scopes, isEmpty);
      expect(notifier.state.items, isEmpty);
      expect(notifier.state.loading, isFalse, reason: '要在页面上渲染成空态');
      verifyNever(() => repo.getKnowledgePointDirectory(
            subject: any(named: 'subject'),
            grade: any(named: 'grade'),
            semester: any(named: 'semester'),
          ));
    });

    test('下拉只派生自真实有教材的范围', () async {
      await notifier.loadScopes();

      final km = notifier.state;
      expect(km.subjects, ['数学', '语文'], reason: '没传过的学科不该出现在下拉里');
      expect(km.gradesOf('数学'), [4]);
      expect(km.gradesOf('语文'), [2]);
      expect(km.semestersOf('数学', 4), ['', '上学期', '下学期']);
      // 语文只有上册，下拉不该凭空补一个「下学期」的空门
      expect(km.semestersOf('语文', 2), ['', '上学期']);
      expect(km.materialCountInScope, 2, reason: '范围内的教材份数用于佐证来源');
    });

    test('教材被删光后，当前范围会被校正回仍存在的那一档', () async {
      await notifier.loadScopes();
      notifier.setScope('语文', 2, '上学期');
      expect(notifier.state.subject, '语文');

      // 教师在资料库删光了语文教材：下一次进来不该停在已经消失的范围上
      when(() => repo.getKnowledgePointScopes()).thenAnswer(
        (_) async => const KnowledgePointScopeList(scopes: [
          KnowledgePointScope(subject: '数学', grade: 4, semester: '上学期'),
        ]),
      );
      await notifier.loadScopes();

      expect(notifier.state.subject, '数学');
      expect(notifier.state.grade, 4);
      expect(notifier.state.semester, '');
    });

    test('切学科时级联到该学科第一个年级，学期退回整学年', () async {
      await notifier.loadScopes();
      // 模拟下拉回调：教师在学科下拉里选了「语文」
      final firstGrade = notifier.state.gradesOf('语文').first;
      notifier.setScope('语文', firstGrade, '');

      expect(notifier.state.subject, '语文');
      expect(notifier.state.grade, 2);
      verify(() => repo.getKnowledgePointDirectory(
            subject: '语文',
            grade: 2,
            semester: '',
          )).called(1);
    });

    test('没识别出学科年级的教材要计数回报', () async {
      when(() => repo.getKnowledgePointScopes()).thenAnswer(
        (_) async => KnowledgePointScopeList(scopes: _scopes, unscopedCount: 3),
      );

      await notifier.loadScopes();

      expect(notifier.state.unscopedCount, 3);
    });
  });
}
