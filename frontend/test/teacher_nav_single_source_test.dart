import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/screens/home_screen.dart';
import 'package:kids_learn/features/home/presentation/teacher_pages.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';
import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import 'package:kids_learn/features/students/providers/students_provider.dart';
import 'package:kids_learn/shared/widgets/app_sidebar.dart' show AppSidebarItem;
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';

/// 教师端导航「单一事实源」守卫（ADR-0059）。
///
/// 线上事故：教师端曾经有三个**并列**的导航状态——侧栏索引 `_teacherNavIndex`、
/// 覆盖层 `_reviewingTask` / `_editingChild`、布尔 `_showProfile`。`AdaptiveShell`
/// 的 `detail` 在中屏 / 紧凑档会**整幅顶替** `body`，于是三者谁盖谁要靠每个回调
/// 自己记得清理：侧栏点击记得清覆盖层、底部「我的」忘了清 —— 从任务列表进审核后
/// 点「我的」，看到的仍是审核页，个人信息页压根没进渲染树。
///
/// 现在三者合成一个 `sealed TeacherPage`，壳也不再有 `detail`。本文件守两件事：
///   1. **静态**：`detail` / 并列状态不许回来（这类洞 `flutter analyze` 照不出来）；
///   2. **行为**：任一时刻侧栏最多只有一个高亮项，且「我的」不与任何页签同时高亮
///      ——这正是「状态不唯一」在界面上唯一能被观测到的痕迹。
const _shellFile = 'lib/shared/widgets/adaptive_shell.dart';
const _homeFile = 'lib/features/home/presentation/screens/home_screen.dart';

void main() {
  group('静态：master-detail 与并列导航状态不许回来', () {
    test('AdaptiveShell 不再有 detail 入参', () {
      final file = File(_shellFile);
      expect(file.existsSync(), isTrue,
          reason: '请在 frontend/ 目录下运行（flutter test 的 CWD）');
      final src = file.readAsStringSync();
      expect(
        RegExp(r'\bWidget\?\s+detail\b').hasMatch(src),
        isFalse,
        reason: 'detail 覆盖层已在 ADR-0059 移除：它让「当前该看哪个页面」变成两个'
            '状态的优先级裁决，漏清一个就整幅顶替 body（个人信息被审核页挡住）。',
      );
    });

    test('home_screen 不再传 detail，也不再有并列的导航状态字段', () {
      final src = File(_homeFile).readAsStringSync();
      for (final banned in const [
        'detail:',
        '_teacherNavIndex',
        '_reviewingTask',
        '_editingChild',
      ]) {
        // 只查代码，不查注释——本文件的文档注释里正写着这些名字作为反面教材。
        final inCode = src
            .split('\n')
            .where((l) => l.contains(banned) && !l.trimLeft().startsWith('//'))
            .toList();
        expect(
          inCode,
          isEmpty,
          reason: '$banned 不应再出现在 $_homeFile 的代码里：教师端导航状态必须是'
              '单一的 `TeacherPage`（ADR-0059）。\n${inCode.join('\n')}',
        );
      }
      // P4 后页面层级迁到 `teacher_pages.dart` 并改为公开（`TeacherPage`），
      // 私有名不能跨 library——这里断言的是「仍由单一字段承载」，不绑私有名。
      expect(src.contains('TeacherPage _teacherPage'), isTrue,
          reason: '教师端当前页面应由 `TeacherPage _teacherPage` 单独承载');
    });
  });

  group('行为：「我的」对两个角色都要真的打开个人信息', () {
    // ⚠️ 这组用例的存在理由：`_onProfileTap()` 是**两个角色共用**的回调，而两端
    // 「当前页面」的载体不同（教师端 = `TeacherPage` 的一个分支，学生端 =
    // 「页签 + `_showProfile` 布尔」的二选一）。只写教师端那一份，学生端点「我的」
    // 就毫无反应——而 `flutter analyze` 完全照不出来。
    testWidgets('学生端：点「我的」渲染个人信息页，且页签不再高亮', (tester) async {
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_activeLabels(tester), ['首页']);

      await tester.tap(find.byWidgetPredicate(
        (w) => w is AppFocusableAction && w.semanticLabel == '小明 · 2年级',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('退出登录'), findsOneWidget,
          reason: '学生端点「我的」必须真的渲染个人信息页');
      expect(_activeLabels(tester), isEmpty,
          reason: '显示个人信息时页签应全部取消高亮（否则「首页」与「我的」同时亮）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('教师端：进入「我的」后，侧栏不留任何高亮页签', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: ShadApp.custom(
            theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
            appBuilder: (context) => CupertinoApp(
              home: HomeScreen(user: _teacher(), onLogout: () {}),
            ),
          ),
        ),
      );
      // 不用 pumpAndSettle：页面内有在途网络请求，它会一直等不到静止。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 默认落在概览，侧栏应有且仅有一个高亮项。
      expect(_activeLabels(tester), ['概览']);

      await tester.tap(find.byWidgetPredicate(
        (w) => w is AppFocusableAction && w.semanticLabel == '妈妈 · 教师账号',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 「我的」不在侧栏项里（它在侧栏底部的用户区），所以此时侧栏应**零**高亮。
      // 修复前这里是 ['概览'] —— `_showProfile` 与 `_teacherNavIndex` 同时为真。
      expect(_activeLabels(tester), isEmpty,
          reason: '显示个人信息时侧栏不应再有高亮页签：两个入口同时亮说明导航状态'
              '又变回了并列的两份');
      expect(find.text('退出登录'), findsOneWidget,
          reason: '个人信息页必须真的渲染出来（不是被更高优先级的面板顶替）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('从「我的」切回侧栏页签，高亮唯一且跟随', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
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

      await tester.tap(find.text('模型管理'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_activeLabels(tester), ['模型管理']);

      await tester.tap(find.byWidgetPredicate(
        (w) => w is AppFocusableAction && w.semanticLabel == '妈妈 · 教师账号',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_activeLabels(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('行为：ticket 16 新增页面状态可达（学生管理 / 学生详情）', () {
    // ⚠️ 这两个页面态（StudentManagementPage / StudentDetailPage）是 16 收尾新增的
    // `TeacherPage` 分支；只靠 sealed 穷尽性只能保证「编译过」，UI 层若没真构建过
    // 仍可能漏接 `onOpenStudent` 之类的跳转回调。`flutter analyze` 照不出来，必须真点。
    testWidgets('教师端：点「学生」高亮唯一且渲染学生管理页', (tester) async {
      await _pumpTeacherHome(tester);
      expect(_activeLabels(tester), ['概览']);

      await tester.tap(find.text('学生'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_activeLabels(tester), ['学生'],
          reason: '同一时刻侧栏只能有一个高亮项（单一导航状态）');
      expect(find.text('学生管理'), findsOneWidget,
          reason: 'StudentManagementPage 应真正渲染');
      expect(tester.takeException(), isNull);
    });

    testWidgets('教师端：从「学生」drill 进学生详情，侧栏零高亮且详情页渲染',
        (tester) async {
      await _pumpTeacherHome(tester);
      expect(_activeLabels(tester), ['概览']);

      await tester.tap(find.text('学生'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_activeLabels(tester), ['学生']);
      expect(find.text('学生管理'), findsOneWidget);

      // 在管理页点学生行 → 经 HomeScreen 接好的 `onOpenStudent` 进入 StudentDetailPage。
      await tester.tap(find.text('小明'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('错题本'), findsWidgets,
          reason: '学生详情页应渲染（页签「错题本」来自 StudentDetailTab.wrongQuestions）');
      expect(_activeLabels(tester), isEmpty,
          reason: '详情页是 drill-down，不应高亮任何顶级侧栏项（单一导航状态语义）');
      expect(tester.takeException(), isNull);
    });
  });

  group('T02：场景编辑器收编为 sealed 导航状态（ADR-0074）', () {
    // ⚠️ 编辑器原来由知识点行 `showDialog(KnowledgePointSceneEditor)` 直接开——把
    // 「当前该看哪个页面」偷变成并列状态，漏清就弹根栈（白屏）。现在它是
    // `SceneLibraryEditorPage` 这一个分支，必须经 HomeScreen 的单一 `_go` switch 打开。
    test('home_screen 经单一 switch 处理 SceneLibraryEditorPage（不散落 showDialog/push）',
        () {
      final src = File(_homeFile).readAsStringSync();
      final inCode = src
          .split('\n')
          .where((l) =>
              l.contains('SceneLibraryEditorPage(') &&
              !l.trimLeft().startsWith('//'))
          .toList();
      expect(inCode, isNotEmpty,
          reason: 'SceneLibraryEditorPage 必须经 HomeScreen 的 `_go` switch 打开，'
              '不能由知识点行 showDialog / Navigator.push 直接开编辑器（ADR-0059）');
    });

    test('highlightFor 对新页面态无并列高亮处理（单一导航状态）', () {
      final page = SceneLibraryEditorPage(
        kpId: 'k1',
        kpName: '轴对称',
        subject: '数学',
        grade: 4,
        semester: '上学期',
        back: const SceneLibraryPage(),
      );
      expect(highlightFor(page), same(page),
          reason: '新页面态不应引入并列高亮逻辑，否则又回到 ADR-0059 前的漏清坑');
    });
  });
}

/// 侧栏（AppSidebarItem）里处于高亮态的标签——「我的」不计入，它在侧栏底部用户区。
List<String> _activeLabels(WidgetTester tester) => tester
    .widgetList<AppSidebarItem>(find.byType(AppSidebarItem))
    .where((item) => item.active)
    .map((item) => item.label)
    .toList();

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
      grade: 2,
    );

/// ticket 16 收尾：让「学生」入口真能加载出学生，从而 drill 进学生详情页。
/// 桩只实现管理页用到的取数方法，其余走 noSuchMethod。
final _classes = [
  ClassModel(id: 'c1', name: '三(1)班', grade: 3, studentCount: 1),
];
final _students = [
  UserModel(
    id: 's1',
    username: '2023001',
    displayName: '小明',
    role: 'child',
    grade: 3,
    classId: 'c1',
  ),
];
final _wrongCounts = <String, int>{'s1': 0};

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
  Future<Map<String, int>> getWrongQuestionCounts() async => _wrongCounts;
}

class _FakeClassesRepo implements ClassesRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();

  @override
  Future<List<ClassModel>> getClasses() async => _classes;
}

/// 用桩 repository 泵起教师端 HomeScreen，使「学生」入口能渲染并 drill 进详情。
Future<void> _pumpTeacherHome(
  WidgetTester tester, {
  List<Override> extra = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        studentsRepositoryProvider
            .overrideWithValue(_FakeStudentsRepo()),
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
