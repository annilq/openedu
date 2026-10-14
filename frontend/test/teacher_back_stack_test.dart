import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import 'package:kids_learn/features/home/presentation/screens/home_screen.dart';
import 'package:kids_learn/features/students/providers/students_provider.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_actions.dart' show AppIconAction;
import 'package:kids_learn/shared/widgets/app_sidebar.dart' show AppSidebarItem;

/// 系统返回键 / Esc / 侧滑手势接管（P0-2）+ 返回栈（P1-3）。
///
/// 全 App 只有一个 route（ADR-0059），返回键原本**直接退出应用**：教师在
/// 「班级 → 班内学生 → 学生详情 → 编辑学生」四级链上按一下，四级全丢。
///
/// 为什么必须走 widget 测试而不是读源码：`PopScope` 装没装、`canPop` 给没给错，
/// `flutter analyze` 一条都照不出来；而「返回键被消费了但页面没动」和「返回键
/// 根本没被消费」在源码上只差一行。这里用**平台通道**当观测点：根页面必须把
/// `SystemNavigator.pop` 打回系统，非根页面必须一条都不打。
///
/// 触发方式统一用 `handlePopRoute()`——它是 Android 返回键、外接键盘 Esc、
/// 系统侧滑手势在框架内的**同一个入口**，三者不可能分叉。
void main() {
  group('系统返回键：四级下钻逐级回退', () {
    testWidgets('班级 → 班内学生 → 学生详情 → 编辑学生：按四次回到概览',
        (tester) async {
      final system = _recordSystemNavigator();
      await _pumpTeacherHome(tester);
      expect(_activeLabels(tester), ['概览']);

      await tester.tap(find.text('班级管理'));
      await _settle(tester);
      await tester.tap(find.text('三(1)班'));
      await _settle(tester);
      await tester.tap(find.text('小明'));
      await _settle(tester);
      await tester.tap(_editEntry());
      await _settle(tester);
      expect(find.text('编辑学生资料'), findsOneWidget, reason: '已进入第四级');

      await _popRoute(tester);
      expect(_editEntry(), findsOneWidget, reason: '第一次返回：回到学生详情页');
      expect(find.text('编辑学生资料'), findsNothing);

      await _popRoute(tester);
      expect(find.textContaining('三(1)班 ·'), findsOneWidget,
          reason: '第二次返回：回到班内学生页');

      await _popRoute(tester);
      expect(_activeLabels(tester), ['班级管理'],
          reason: '第三次返回：回到班级管理列表并高亮');

      await _popRoute(tester);
      expect(_activeLabels(tester), ['概览'],
          reason: '第四次返回：回到根页面（概览）');

      expect(system.calls, isEmpty,
          reason: '四级下钻里每一次返回都应被壳消费，一次都不许漏给系统');
      expect(tester.takeException(), isNull);
    });

    testWidgets('根页面（概览）按返回键不消费，交回系统', (tester) async {
      final system = _recordSystemNavigator();
      await _pumpTeacherHome(tester);
      expect(_activeLabels(tester), ['概览']);

      await _popRoute(tester);

      expect(_activeLabels(tester), ['概览'], reason: '根页面没有历史可退');
      expect(system.calls.map((c) => c.method), ['SystemNavigator.pop'],
          reason: '根页面的返回必须交回系统：否则用户按返回键退出应用的能力被白白拿走');
      expect(tester.takeException(), isNull);
    });
  });

  group('侧栏切换一级入口：清空历史', () {
    // ⚠️ 「切到『题库』后按返回不会先弹回上一次的班内学生页」——不清空历史的话，
    // 换入口只是「换了个栈顶」，底下压着的还是上一个入口的下钻链，按返回就跨入口
    // 弹回去。这是本票要求 `_go` 区分「下钻入栈 / 换入口清栈」两个语义的理由。
    testWidgets('切到「题库」后按返回回概览，不弹回班内学生页', (tester) async {
      final system = _recordSystemNavigator();
      await _pumpTeacherHome(tester);

      await tester.tap(find.text('班级管理'));
      await _settle(tester);
      await tester.tap(find.text('三(1)班'));
      await _settle(tester);
      expect(find.textContaining('三(1)班 ·'), findsOneWidget);

      await tester.tap(find.text('题库'));
      await _settle(tester);
      expect(_activeLabels(tester), ['题库']);

      await _popRoute(tester);
      expect(_activeLabels(tester), ['概览'],
          reason: '换一级入口应清空历史：返回落到概览，不跨入口弹回班内学生页');
      expect(find.textContaining('三(1)班 ·'), findsNothing);
      expect(system.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('学生端：页签内的返回不退出应用', () {
    testWidgets('非首页按返回回首页，不交回系统', (tester) async {
      final system = _recordSystemNavigator();
      await _pumpChildHome(tester);
      expect(_activeLabels(tester), ['首页']);

      await tester.tap(find.text('复习'));
      await _settle(tester);
      expect(_activeLabels(tester), ['复习']);

      await _popRoute(tester);
      expect(_activeLabels(tester), ['首页'],
          reason: '学生端页签内的返回应回首页，而不是退出应用');
      expect(system.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}

/// 侧栏（AppSidebarItem）里处于高亮态的标签——「我的」不计入，它在侧栏底部用户区。
List<String> _activeLabels(WidgetTester tester) => tester
    .widgetList<AppSidebarItem>(find.byType(AppSidebarItem))
    .where((item) => item.active)
    .map((item) => item.label)
    .toList();

/// 学生详情页里的「编辑学生资料」入口——只在详情页存在（编辑页里它被表单替掉）。
Finder _editEntry() => find.byWidgetPredicate(
    (w) => w is AppIconAction && w.semanticLabel == '编辑学生资料');

/// 触发系统返回（Android 返回键 / Esc / 侧滑手势在框架内的唯一入口）。
Future<void> _popRoute(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

/// 不 pumpAndSettle：页面内有在途网络请求，它会一直等不到静止。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 把 `flutter/platform` 通道的调用记录下来：这是「返回键有没有交回系统」唯一的
/// 观测点——`SystemNavigator.pop` 在测试里不会真的退出进程，只会打一条方法调用。
_SystemNavigatorLog _recordSystemNavigator() {
  final log = _SystemNavigatorLog();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    // 只记 `SystemNavigator.*`：同一条通道上还跑着 SystemChrome 等无关调用。
    if (call.method.startsWith('SystemNavigator')) log.calls.add(call);
    return null;
  });
  addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return log;
}

class _SystemNavigatorLog {
  final calls = <MethodCall>[];
}

UserModel _teacher() => UserModel(
      id: 'u1',
      username: 'teacher1',
      displayName: '妈妈',
      role: 'teacher',
    );

UserModel _child() => UserModel(
      id: 'u2',
      username: 'child1',
      displayName: '小明',
      role: 'child',
    );

// 桩只实现导航链路上真正取数的方法，其余走 noSuchMethod。
final _classes = [ClassModel(id: 'c1', name: '三(1)班', grade: 3, studentCount: 1)];
final _students = [
  UserModel(
      id: 's1', username: '2023001', displayName: '小明', role: 'child',
      classId: 'c1'),
];

class _FakeStudentsRepo implements StudentsRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();

  @override
  Future<List<UserModel>> getStudents({String? classId, String? keyword}) async =>
      _students;

  // 学生详情页的学生名取自 `studentsNotifierProvider`（壳 initState 里加载）。
  @override
  Future<List<UserModel>> getChildren() async => _students;

  @override
  Future<Map<String, int>> getWrongQuestionCounts() async => const {'s1': 0};
}

class _FakeClassesRepo implements ClassesRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();

  @override
  Future<List<ClassModel>> getClasses() async => _classes;
}

Future<void> _pumpTeacherHome(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        studentsRepositoryProvider.overrideWithValue(_FakeStudentsRepo()),
        classesRepositoryProvider.overrideWithValue(_FakeClassesRepo()),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: HomeScreen(user: _teacher(), onLogout: () {}),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _pumpChildHome(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.student, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: HomeScreen(user: _child(), onLogout: () {}),
        ),
      ),
    ),
  );
  await _settle(tester);
}
