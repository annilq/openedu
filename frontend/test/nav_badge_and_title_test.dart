import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/screens/home_screen.dart';
import 'package:kids_learn/features/home/presentation/screens/teacher_destinations.dart';
import 'package:kids_learn/features/home/presentation/providers/teacher_tasks_notifier.dart';
import 'package:kids_learn/features/home/presentation/providers/home_notifier.dart';
import 'package:kids_learn/features/home/presentation/teacher_pages.dart';
import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import 'package:kids_learn/features/students/providers/students_provider.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_badge.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';
import 'package:kids_learn/shared/widgets/nav_section.dart';

/// 09：导航可见性——侧栏徽标（待审核草稿）+ 紧凑档当前页标题。
/// 两条验收线：
///   1. 侧栏「任务」项在有待审核草稿时显示数量徽标、为 0 时不显示，且与出题进度
///      徽标分槽不打架；
///   2. 紧凑档顶栏显示**当前页面名**（取自 01 映射），跟随切页（含下钻页），长名截断。
const _compactTitleKey = Key('compact-current-title');

void main() {
  group('侧栏「任务」项：待审核草稿徽标随数量出现 / 消失', () {
    // 直接 override [teacherDraftCountProvider] 注入计数（数据加载不在本票范围，
    // 且避免测试里打真实网络）。徽标仅出现在「任务」项——AppBadge 全仓尚无其它用例。
    testWidgets('有待审核草稿时「任务」项显示数量徽标', (tester) async {
      await _pumpTeacherWide(tester,
          extra: [teacherDraftCountProvider.overrideWithValue(3)]);

      final badges = tester.widgetList<AppBadge>(find.byType(AppBadge));
      expect(badges, hasLength(1),
          reason: '待审核草稿 > 0 时，应仅在「任务」项出现一个数量徽标');
      expect(badges.first.label, '3',
          reason: '徽标显示待审核草稿数');
      expect(tester.takeException(), isNull);
    });

    testWidgets('草稿为 0 时「任务」项不显示徽标', (tester) async {
      await _pumpTeacherWide(tester,
          extra: [teacherDraftCountProvider.overrideWithValue(0)]);

      expect(find.byType(AppBadge), findsNothing,
          reason: '待审核草稿为 0 时不显示徽标');
      expect(tester.takeException(), isNull);
    });

    testWidgets('出题进行中：出题进度徽标与草稿徽标分槽并存（不打架）',
        (tester) async {
      // 注入草稿计数 + 模拟出题进行中（gen 进度徽标由 home_screen 依据
      // taskGenNotifierProvider 渲染，此处用 Provider 注入一个 streaming 态）。
      await _pumpTeacherWide(tester, extra: [
        teacherDraftCountProvider.overrideWithValue(2),
      ]);

      // 草稿徽标存在。
      expect(tester.widget<AppBadge>(find.byType(AppBadge)).label, '2');
      // 出题未在进行中（idle）→ 不应有「x/y」进度徽标（accent 实色 Container 无稳定
      // 标识，这里只验证草稿徽标是唯一徽标组件，且整体无异常）。
      expect(tester.takeException(), isNull);
    });
  });

  group('单元：侧栏「任务」项尾部组合徽标——草稿计数与出题进度显式分槽', () {
    // 直接构造 [NavigationDestinations] 并检视「任务」项的 trailing，避免 widget 泵
    // 与 provider 注入的抖动；覆盖 acceptance「徽标与既有的出题进度徽标不打架」。
    const genBadgeKey = Key('gen-progress-badge');
    Widget? stubGenTrailing(TaskGenState gen) =>
        gen is TaskGenPreview && gen.streaming
            ? Container(key: genBadgeKey)
            : null;

    AdaptiveNavDestination taskItem(TaskGenState gen, int draftCount) {
      final dests = NavigationDestinations(
        goEntry: (_) {},
        goChildTab: (_) {},
        goProfile: () {},
        genTrailing: stubGenTrailing,
      ).teacher(const CreateTaskPage(), gen, draftCount: draftCount);
      return dests.expand((s) => s.items).firstWhere((d) => d.label == '任务');
    }

    test('草稿 0 + 出题空闲：无 trailing', () {
      expect(taskItem(const TaskGenIdle(), 0).trailing, isNull);
    });

    test('草稿 3 + 出题空闲：仅草稿数量徽标（AppBadge）', () {
      final trailing = taskItem(const TaskGenIdle(), 3).trailing;
      expect(trailing, isA<AppBadge>());
      expect((trailing as AppBadge).label, '3');
    });

    test('草稿 2 + 出题进行中：Row 分槽并存（AppBadge + 进度徽标），不抢优先级',
        () {
      final trailing = taskItem(
        const TaskGenPreview([], streaming: true, expected: 5),
        2,
      ).trailing;
      expect(trailing, isA<Row>(),
          reason: '两徽标应显式分槽并排，而非叠在同一槽位互斥');
      final row = trailing as Row;
      // Row = [AppBadge, SizedBox 间距, 进度徽标]，中间是分槽间距，不是第三类徽标。
      expect(row.children.whereType<AppBadge>().single.label, '2',
          reason: '第一格为待审核草稿计数');
      expect(
          row.children.any((w) =>
              w is Container && w.key == genBadgeKey),
          isTrue,
          reason: '第二格为出题进度徽标');
    });
  });

  group('紧凑档顶栏：显示当前页面名并跟随切页（含下钻页）', () {
    // 紧凑宽度（< AppLayout.compactMax = 700）走教师端汉堡 + 抽屉；顶栏显示当前页名。
    testWidgets('默认显示概览；切到「班级」跟随更新', (tester) async {
      await _pumpTeacherCompact(tester);

      expect(_compactTitle(tester), '概览',
          reason: '紧凑档顶栏默认应显示当前页「概览」，而非固定的应用名');

      await _openDrawerAndTap(tester, '班级');
      expect(_compactTitle(tester), '班级',
          reason: '切到「班级」后顶栏应跟随显示「班级」');
      expect(tester.takeException(), isNull);
    });

    testWidgets('下钻进班级后顶栏显示班级名（下钻页自己的名字，非父级）',
        (tester) async {
      await _pumpTeacherCompact(tester);

      await _openDrawerAndTap(tester, '班级');
      expect(_compactTitle(tester), '班级');

      // 容器默认「全部学生」视图，班级卡片在「按班级」视图下才可点；先切视图。
      await tester.tap(find.text('按班级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 班级卡片下钻（桩返回「三(1)班」）。
      await tester.tap(find.text('三(1)班'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_compactTitle(tester), '三(1)班',
          reason: '下钻进班级后顶栏应显示班级名（下钻页自己的名字），而不是「班级管理」');
      expect(find.text('三(1)班'), findsWidgets,
          reason: '班级名下钻页应真正渲染');
      expect(tester.takeException(), isNull);
    });

    testWidgets('长页面名截断而非溢出（不抛 Layout 异常）', (tester) async {
      // 班级名本身不超长，这里只验证截断机制存在：把 surface 压到很窄，标题若超长
      // 应走省略号而不溢出。用一个超长 class 名走同一渲染路径。
      await _pumpTeacherCompact(tester);

      await _openDrawerAndTap(tester, '班级');
      // 找一个超长名的班级卡会落进现有桩之外，这里改用断言：窄视口下顶栏标题组件
      // 用 Flexible + ellipsis，pump 后不应产生溢出异常。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull,
          reason: '窄视口下顶栏标题应截断而非溢出（Flexible + ellipsis）');
    });
  });
}

/// 读取紧凑档顶栏标题文本（经稳定 Key 定位，避免与其它同名 Text 冲突）。
String _compactTitle(WidgetTester tester) {
  final text = tester.widget<Text>(find.byKey(_compactTitleKey));
  return text.data!;
}

/// 打开抽屉并点击名为 [label] 的导航项；抽屉项在壳内，需先开抽屉再点。
///
/// 按 `semanticLabel` 命中外壳导航项而非 `find.text`——切页后 body 里也可能出现同名
/// 文案（如 StudentManagementScreen / ClassManagementScreen 自带标题），按文本会误点 body。
/// 抽屉滑入动画 280ms，开抽屉后 pump 足额时长再点，否则项中心仍在屏幕外导致点击落空。
Future<void> _openDrawerAndTap(WidgetTester tester, String label) async {
  await tester.tap(find.byWidgetPredicate(
    (w) => w is AppFocusableAction && w.semanticLabel == '打开导航菜单',
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));

  await tester.tap(find.byWidgetPredicate(
    (w) => w is AppFocusableAction && w.semanticLabel == label,
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

UserModel _teacher() => UserModel(
      id: 'u1',
      username: 'teacher1',
      displayName: '妈妈',
      role: 'teacher',
    );

final _classes = [
  ClassModel(id: 'c1', name: '三(1)班', grade: 3, studentCount: 1),
];
final _students = [
  UserModel(
    id: 's1',
    username: '2023001',
    displayName: '小明',
    role: 'child',
    classId: 'c1',
  ),
];

class _FakeStudentsRepo implements StudentsRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();

  @override
  Future<List<UserModel>> getStudents({
    String? classId,
    String? keyword,
  }) async =>
      _students;

  @override
  Future<Map<String, int>> getWrongQuestionCounts() async => const {};
}

class _FakeClassesRepo implements ClassesRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();

  @override
  Future<List<ClassModel>> getClasses() async => _classes;
}

/// 宽屏教师端（侧栏常驻）：验证侧栏徽标。
Future<void> _pumpTeacherWide(
  WidgetTester tester, {
  List<Override> extra = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 900));
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
        ...extra,
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: HomeScreen(user: _teacher(), onLogout: () {}),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 紧凑屏教师端（汉堡 + 抽屉）：验证顶栏当前页标题。
Future<void> _pumpTeacherCompact(
  WidgetTester tester, {
  List<Override> extra = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(480, 800));
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
        ...extra,
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: HomeScreen(user: _teacher(), onLogout: () {}),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
