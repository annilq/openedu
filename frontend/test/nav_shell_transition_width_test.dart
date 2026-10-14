import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/screens/home_screen.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/teacher_overview_view.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/teacher_question_bank_view.dart';
import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import 'package:kids_learn/features/students/providers/students_provider.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_content_frame.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';

/// 05：壳内换页淡入转场 + 宽度收口。
///
/// 三条验收线：
///   1. 壳内切页有 ≤150ms 淡入转场；reduce-motion 下时长归零（不靠缺省行为）；
///   2. 每个页面可声明内容宽度上限，未声明者沿用壳默认（contentWide）；
///      表单类页面（发布任务 / 添加·编辑学生）与「我的」用窄宽度（contentNarrow）居中；
///   3. 学生端 IndexedStack 常驻保活不被转场破坏（避免掉页签 State）。
void main() {
  group('壳内切页：淡入转场（教师端）', () {
    testWidgets('切页触发交叉淡入——过渡中新旧两页共存', (tester) async {
      await _pumpTeacherWide(tester);

      // 初始在「概览」。
      expect(find.byType(TeacherOverviewView), findsOneWidget);
      expect(find.byType(TeacherQuestionBankView), findsNothing);

      // 切到「题库」：bodyKey（_teacherPage）变化 → AnimatedSwitcher 交叉淡入。
      await _tapSidebar(tester, '题库');
      // 过渡进行中（< 150ms）：旧页仍在树中淡出、新页淡入 → 两页共存。
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TeacherOverviewView), findsOneWidget,
          reason: '过渡中旧页（概览）仍挂载淡出');
      expect(find.byType(TeacherQuestionBankView), findsOneWidget,
          reason: '过渡中新页（题库）已挂载淡入——证明切页触发了转场');

      // 过渡结束：旧页卸载，只剩新页。
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(TeacherOverviewView), findsNothing,
          reason: '过渡结束后旧页应卸载');
      expect(find.byType(TeacherQuestionBankView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduce-motion：切页转场时长为零（旧页即时移除）', (tester) async {
      await _pumpTeacherWide(tester, reduceMotion: true);

      await _tapSidebar(tester, '题库');
      // 即便只泵极小时间，reduce-motion 下时长归零 → 旧页即时移除。
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byType(TeacherOverviewView), findsNothing,
          reason: 'reduce-motion 下转场时长归零，旧页不应残留');
      expect(find.byType(TeacherQuestionBankView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('淡入转场不干扰 push 路由（壳内转场独立于 CupertinoPageRoute）',
        (tester) async {
      // 仅验证壳内转场存在且不抛异常；push 整页的 Cupertino 转场由路由层负责，
      // 二者互不耦合（验收「不并存两套动画语言」的实现边界）。
      await _pumpTeacherWide(tester);
      await _tapSidebar(tester, '题库');
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });
  });

  group('宽度收口：表单类与「我的」用窄宽度', () {
    testWidgets('默认页（概览）沿用壳默认宽度，无窄框', (tester) async {
      await _pumpTeacherWide(tester);
      expect(_narrowFrames(tester), 0,
          reason: '未声明窄宽度的页面不应出现 contentNarrow 框');
    });

    testWidgets('教师端「我的」被收进窄宽度框 contentNarrow', (tester) async {
      await _pumpTeacherWide(tester);
      // 「我的」经侧栏底部用户区进入（与侧栏项同一套 AppFocusableAction 语义标签）。
      await _tapSidebar(tester, '妈妈 · 教师账号');
      await tester.pump(const Duration(milliseconds: 200));
      expect(_narrowFrames(tester), greaterThan(0),
          reason: '「我的」页应被 _narrow 收进 contentNarrow 框');
      expect(tester.takeException(), isNull);
    });

    testWidgets('学生端「我的」被收进窄宽度框（IndexedStack 槽位 onstage 才命中）',
        (tester) async {
      await _pumpStudentCompact(tester);
      // find.byType 默认跳过 offstage：未切到「我的」时其槽位 offstage 不计入，
      // 故先切到该页签，使其 onstage 后再断言窄框存在且唯一。
      await _tapBottomNav(tester, '我的');
      await tester.pump(const Duration(milliseconds: 200));
      expect(_narrowFrames(tester), 1,
          reason: '学生端「我的」页应被 _narrow 收进 contentNarrow 框，且唯一');
      expect(tester.takeException(), isNull);
    });
  });

  group('学生端保活：转场不破坏 IndexedStack 常驻', () {
    testWidgets('切页时 IndexedStack 不被换挂（始终仅一份）', (tester) async {
      await _pumpStudentCompact(tester);
      expect(_indexedStackCount(tester), 1,
          reason: '静止态应仅有 1 个 IndexedStack（五个槽位共享）');

      await _tapBottomNav(tester, '我的');
      // 过渡进行中：若用 AnimatedSwitcher 换挂会把旧 IndexedStack 卸载、新一份挂载，
      // 此刻应出现 2 份；正确实现（_KeepAliveFade）始终保持 1 份。
      await tester.pump(const Duration(milliseconds: 50));
      expect(_indexedStackCount(tester), 1,
          reason: '过渡中 IndexedStack 仍应仅 1 份（保活，不丢页签 State）');
      await tester.pump(const Duration(milliseconds: 200));
      expect(_indexedStackCount(tester), 1);
      expect(tester.takeException(), isNull);
    });
  });
}

/// 统计树中 contentNarrow 宽度的 [AppContentFrame] 数量。
int _narrowFrames(WidgetTester tester) =>
    tester.widgetList<AppContentFrame>(find.byType(AppContentFrame)).where(
      (f) => f.maxWidth == AppLayout.contentNarrow,
    ).length;

int _indexedStackCount(WidgetTester tester) =>
    tester.widgetList<IndexedStack>(find.byType(IndexedStack)).length;

/// 点击宽屏侧栏中带指定语义标签的导航项（教师端侧栏恒可见，无需开抽屉）。
Future<void> _tapSidebar(WidgetTester tester, String label) async {
  await tester.tap(
    find.byWidgetPredicate(
      (w) => w is AppFocusableAction && w.semanticLabel == label,
    ),
  );
  await tester.pump();
}

/// 点击紧凑档学生端底栏中带指定语义标签的页签。
Future<void> _tapBottomNav(WidgetTester tester, String label) async {
  await tester.tap(
    find.byWidgetPredicate(
      (w) => w is AppFocusableAction && w.semanticLabel == label,
    ),
  );
  await tester.pump();
}

UserModel _teacher() => UserModel(
      id: 'u1',
      username: 'teacher1',
      displayName: '妈妈',
      role: 'teacher',
    );

UserModel _student() => UserModel(
      id: 's1',
      username: '2023001',
      displayName: '小明',
      role: 'child',
    );

class _FakeStudentsRepo implements StudentsRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();

  @override
  Future<List<UserModel>> getStudents({
    String? classId,
    String? keyword,
  }) async =>
      const [];

  @override
  Future<Map<String, int>> getWrongQuestionCounts() async => const {};
}

class _FakeClassesRepo implements ClassesRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();

  @override
  Future<List<ClassModel>> getClasses() async => const [];
}

/// 宽屏教师端（侧栏常驻）：验证壳内转场与窄宽度。
Future<void> _pumpTeacherWide(
  WidgetTester tester, {
  bool reduceMotion = false,
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
          home: MediaQuery(
            data: MediaQueryData.fromView(View.of(context))
                .copyWith(disableAnimations: reduceMotion),
            child: HomeScreen(user: _teacher(), onLogout: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 紧凑屏学生端（底栏）：验证窄宽度与 IndexedStack 保活。
Future<void> _pumpStudentCompact(
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
        theme: AppTheme.shadFor(false, AppUserMode.student, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: MediaQuery(
            data: MediaQueryData.fromView(View.of(context)),
            child: HomeScreen(user: _student(), onLogout: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
