import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kids_learn/features/children/domain/repositories/children_repository.dart';
import 'package:kids_learn/features/children/presentation/providers/children_notifier.dart';
import 'package:kids_learn/features/children/presentation/screens/add_child_screen.dart';
import 'package:kids_learn/shared/data/remote/network_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';

class MockChildrenRepository extends Mock implements ChildrenRepository {}

/// 静默 NetworkService（AddChildScreen widget 测试用，校验拦截不会真正请求）。
class _SilentNetwork implements NetworkService {
  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => null;

  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async => null;

  @override
  Future<dynamic> put(String path,
      {Map<String, dynamic>? query, Map<String, dynamic>? body}) async =>
      null;

  @override
  Future<dynamic> delete(String path) async => null;
}

void main() {
  final dabao = UserModel(
    id: 'c1',
    username: 'dabao',
    displayName: '大宝',
    role: 'child',
    grade: 2,
  );

  group('ChildrenNotifier', () {
    test('createChild 成功：提交参数并刷新列表', () async {
      final repo = MockChildrenRepository();
      when(() => repo.createChild(
            username: any(named: 'username'),
            password: any(named: 'password'),
            displayName: any(named: 'displayName'),
            grade: any(named: 'grade'),
          )).thenAnswer((_) async => dabao);
      when(() => repo.getChildren()).thenAnswer((_) async => [dabao]);
      final notifier = ChildrenNotifier(repo);

      await notifier.createChild(
        username: 'dabao',
        password: '1234',
        displayName: '大宝',
        grade: 2,
      );

      verify(() => repo.createChild(
            username: 'dabao',
            password: '1234',
            displayName: '大宝',
            grade: 2,
          )).called(1);
      final state = notifier.state as ChildrenLoaded;
      expect(state.children.length, 1);
      expect(state.children.first.displayName, '大宝');
    });

    test('createChild 失败：进入 Error 状态', () async {
      final repo = MockChildrenRepository();
      when(() => repo.createChild(
            username: any(named: 'username'),
            password: any(named: 'password'),
            displayName: any(named: 'displayName'),
            grade: any(named: 'grade'),
          )).thenThrow(Exception('username already registered'));
      final notifier = ChildrenNotifier(repo);

      await notifier.createChild(
        username: 'dabao',
        password: '1234',
        displayName: '大宝',
        grade: 2,
      );

      expect(notifier.state, isA<ChildrenError>());
    });

    test('loadChildren：Initial → Loading → Loaded（空列表）', () async {
      final repo = MockChildrenRepository();
      when(() => repo.getChildren()).thenAnswer((_) async => <UserModel>[]);
      final notifier = ChildrenNotifier(repo);

      expect(notifier.state, isA<ChildrenInitial>());
      final future = notifier.loadChildren();
      expect(notifier.state, isA<ChildrenLoading>());
      await future;

      final state = notifier.state as ChildrenLoaded;
      expect(state.children, isEmpty);
    });
  });

  group('AddChildScreen 表单校验', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkServiceProvider.overrideWithValue(_SilentNetwork()),
          ],
          child: const MaterialApp(home: AddChildScreen()),
        ),
      );
    }

    testWidgets('空字段提交：提示必填错误', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('创建娃娃账号'));
      await tester.pump();

      expect(find.text('昵称、账号和密码都不能为空'), findsOneWidget);
    });

    testWidgets('密码不足 4 位：提示长度错误', (tester) async {
      await pumpScreen(tester);
      await tester.enterText(
          find.widgetWithText(TextField, '登录账号（唯一，例如：dabao）'), 'dabao');
      await tester.enterText(find.widgetWithText(TextField, '娃娃昵称（例如：大宝）'), '大宝');
      await tester.enterText(find.widgetWithText(TextField, '密码（至少 4 位）'), '123');
      await tester.tap(find.text('创建娃娃账号'));
      await tester.pump();

      expect(find.text('密码至少 4 位'), findsOneWidget);
    });
  });
}
