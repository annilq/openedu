import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/children/domain/repositories/children_repository.dart';
import 'package:kids_learn/features/children/presentation/providers/children_notifier.dart';
import 'package:kids_learn/features/children/presentation/screens/child_form_screen.dart';
import 'package:kids_learn/shared/data/remote/network_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/widgets/app_inputs.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';

class MockChildrenRepository extends Mock implements ChildrenRepository {}

/// 静默 NetworkService（ChildFormScreen widget 测试用，校验拦截不会真正请求）。
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

  @override
  Stream<Uint8List> streamPost(String path, {Map<String, dynamic>? body}) =>
      const Stream<Uint8List>.empty();
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

  group('ChildFormScreen 表单校验', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkServiceProvider.overrideWithValue(_SilentNetwork()),
          ],
          // ShadApp 提供 ShadTheme（AppTopBar 内 ShadButton 需要）；
          // MaterialApp 提供 TextField 所需的 Material 祖先。
          child: ShadApp.custom(
            appBuilder: (context) => const MaterialApp(
              home: ChildFormScreen(mode: ChildFormMode.create),
            ),
          ),
        ),
      );
    }

    /// 定位带指定标签的输入框：AppTextField 的 label 是与 ShadInput 平级的 Text，
    /// 因此取「包含该 label 的 AppTextField」作为 enterText 的目标。
    Finder field(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byType(AppTextField),
        );

    /// 提交按钮位于长表单底部（下方还有兴趣选择器），需先滚动进视口再点击。
    /// 树中存在多个 Scrollable（输入框等自带），显式指定最外层那个。
    Future<void> tapSubmit(WidgetTester tester) async {
      final btn = find.text('创建娃娃账号');
      await tester.scrollUntilVisible(
        btn,
        300.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(btn);
      await tester.pump();
    }

    testWidgets('空字段提交：提示必填错误', (tester) async {
      await pumpScreen(tester);
      await tapSubmit(tester);

      expect(find.text('昵称、账号和密码都不能为空'), findsOneWidget);
    });

    testWidgets('密码不足 4 位：提示长度错误', (tester) async {
      await pumpScreen(tester);
      await tester.enterText(field('登录账号（唯一，例如：dabao）'), 'dabao');
      await tester.enterText(field('娃娃昵称（例如：大宝）'), '大宝');
      await tester.enterText(field('密码（至少 4 位）'), '123');
      await tester.pump();
      await tapSubmit(tester);

      expect(find.text('密码至少 4 位'), findsOneWidget);
    });
  });
}
