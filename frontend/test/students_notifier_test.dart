import 'dart:typed_data';
import 'package:dio/dio.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import 'package:kids_learn/features/students/presentation/providers/students_notifier.dart';
import 'package:kids_learn/features/students/presentation/screens/student_form_screen.dart';
import 'package:kids_learn/shared/data/remote/network_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/presentation/resource.dart';
import 'package:kids_learn/shared/widgets/app_inputs.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';

class MockStudentsRepository extends Mock implements StudentsRepository {}

/// 静默 NetworkService（StudentFormScreen widget 测试用，校验拦截不会真正请求）。
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
  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) async => null;

  @override
  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async => null;

  @override
  Future<dynamic> postForm(String path, FormData form) async =>
      throw UnimplementedError();

  @override
  Stream<Uint8List> streamPost(
    String path, {
    Map<String, dynamic>? body,
    Duration? receiveTimeout,
  }) =>
      const Stream<Uint8List>.empty();

  @override
  Future<Uint8List> postBytes(String path, {Map<String, dynamic>? body}) async =>
      throw UnimplementedError('本测试的替身不涉及二进制下载');

  @override
  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? query}) async =>
      throw UnimplementedError('本测试的替身不涉及二进制下载');
}

void main() {
  final dabao = UserModel(
    id: 'c1',
    username: 'dabao',
    displayName: '大宝',
    role: 'child',
  );

  group('ChildrenNotifier', () {
    test('createChild 成功：提交参数并刷新列表', () async {
      final repo = MockStudentsRepository();
      when(() => repo.createChild(
            username: any(named: 'username'),
            password: any(named: 'password'),
            displayName: any(named: 'displayName'),
          )).thenAnswer((_) async => dabao);
      when(() => repo.getChildren()).thenAnswer((_) async => [dabao]);
      final notifier = ChildrenNotifier(repo);

      await notifier.createChild(
        username: 'dabao',
        password: '1234',
        displayName: '大宝',
      );

      verify(() => repo.createChild(
            username: 'dabao',
            password: '1234',
            displayName: '大宝',
          )).called(1);
      final state = notifier.state as ResourceLoaded<List<UserModel>>;
      expect(state.data.length, 1);
      expect(state.data.first.displayName, '大宝');
    });

    test('createChild 失败：进入 Error 状态', () async {
      final repo = MockStudentsRepository();
      when(() => repo.createChild(
            username: any(named: 'username'),
            password: any(named: 'password'),
            displayName: any(named: 'displayName'),
          )).thenThrow(Exception('username already registered'));
      final notifier = ChildrenNotifier(repo);

      await notifier.createChild(
        username: 'dabao',
        password: '1234',
        displayName: '大宝',
      );

      expect(notifier.state, isA<ResourceError<List<UserModel>>>());
    });

    test('loadChildren：Initial → Loading → Loaded（空列表）', () async {
      final repo = MockStudentsRepository();
      when(() => repo.getChildren()).thenAnswer((_) async => <UserModel>[]);
      final notifier = ChildrenNotifier(repo);

      expect(notifier.state, isA<ResourceIdle>());
      final future = notifier.loadChildren();
      expect(notifier.state, isA<ResourceLoading<List<UserModel>>>());
      await future;

      final state = notifier.state as ResourceLoaded<List<UserModel>>;
      expect(state.data, isEmpty);
    });
  });

  group('StudentFormScreen 表单校验', () {
    /// 首帧 `_loadingClasses` 为真 → 班级选择器位置先渲染 [AppLoading] 的 spinner，
    /// 该 spinner 由 `flutter_animate` 的 `Animate` 驱动。
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
              home: StudentFormScreen(mode: ChildFormMode.create),
            ),
          ),
        ),
      );
      // 两步泵帧，缺一不可（这是装置问题，不是产品校验逻辑问题）：
      // 1. `Animate.initState` 会走 `_restart()` 起一个 `Duration.zero` 的
      //    `Future.delayed`。`tester.pump()` 不带时长的重载**不会推进假时钟**，
      //    这个 future 永远不触发；而 `Animate.dispose` 只 `ignore()` 它、并不取消
      //    底层 Timer → 测试收尾的 invariant 检查报「pending timers」。
      //    因此必须在 spinner **还在树上**时显式推进时钟，让 `_play()` 作用于活状态。
      //    （不能用 `pumpAndSettle`：spinner 是 `onPlay: (c) => c.repeat()` 的无限
      //    循环动画，永远 settle 不了，会把测试挂死。）
      await tester.pump(const Duration(milliseconds: 1));
      // 2. 再泵一帧让 `_loadClasses` 的异步分支落地（`_SilentNetwork` 返回 null →
      //    走 catch），spinner 随 `_loadingClasses` 转假而卸载，重复动画的 ticker
      //    一并停止，后续交互不会被无限 ticker 干扰。
      await tester.pump();
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
      final btn = find.text('创建学生账号');
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
      await tester.enterText(field('学生昵称（例如：大宝）'), '大宝');
      await tester.enterText(field('密码（至少 4 位）'), '123');
      await tester.pump();
      await tapSubmit(tester);

      expect(find.text('密码至少 4 位'), findsOneWidget);
    });
  });
}
