import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/screens/home_screen.dart';
import 'package:kids_learn/features/home/presentation/screens/teacher_destinations.dart';
import 'package:kids_learn/features/home/presentation/teacher_pages.dart';
import 'package:kids_learn/features/assistant/domain/repositories/run_trace_repository.dart';
import 'package:kids_learn/features/assistant/domain/run_trace.dart';
import 'package:kids_learn/features/assistant/providers/run_trace_provider.dart';
import 'package:kids_learn/features/home/presentation/providers/home_notifier.dart';
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
import 'package:kids_learn/shared/widgets/app_actions.dart' show AppIconAction;

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
const _pagesFile = 'lib/features/home/presentation/teacher_pages.dart';

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
        '_showProfile',
        '_childNavIndex',
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
      // 私有名不能跨 library——这里断言的是「仍由单一状态承载」，不绑私有名。
      //
      // ticket 03 引入返回栈之后，不变式**更严了**：当前页面不许是栈之外的另一个
      // 字段，只能是栈顶的只读派生（getter）。「栈 + 当前页字段」正是 ADR-0059 要
      // 防的并列真源——栈顶说 A、字段说 B 的时候无从裁决，与当年「索引 + 覆盖层 +
      // 布尔」是同一个坑换了个壳。
      expect(RegExp(r'TeacherPage\s+_teacherPage\b').hasMatch(src), isFalse,
          reason: '教师端不许存在「栈之外的当前页面字段」：栈外再存一份当前页就是'
              '两个真源（ADR-0059）。当前页只能是栈顶的只读派生。');
      expect(RegExp(r'TeacherPage\s+get\s+_teacherPage\b').hasMatch(src), isTrue,
          reason: '教师端「当前页面」应由 `TeacherPage get _teacherPage` 从导航栈派生');
    });

    test('TeacherPage 子类不再携带回落目标字段（返回由壳的历史栈负责）', () {
      // ⚠️ ticket 03 之前四个页面各带一个 `back` 字段（TaskReviewPage / EditStudentPage /
      // StudentDetailPage / SceneLibraryEditorPage）。那是「每个新增下钻页都要记得
      // 声明回落目标」，漏声明就静默回落概览——而 `flutter analyze` 照不出来。
      // 现在回落由 `TeacherNavStack` 记录，页面类零义务；这条断言把「零义务」钉住。
      final src = File(_pagesFile).readAsStringSync();
      final inCode = src
          .split('\n')
          .where((l) => l.contains('back') && !l.trimLeft().startsWith('//'))
          .toList();
      expect(
        inCode,
        isEmpty,
        reason: '$_pagesFile 的代码里不应再出现回落目标字段：返回落点由壳的历史栈'
            '决定，新增下钻页不该有任何义务（ticket 03）。\n${inCode.join('\n')}',
      );
    });
  });

  group('行为：「我的」对两个角色都要真的打开个人信息', () {
    // ⚠️ 这组用例的存在理由：`_onProfileTap()` 是**两个角色共用**的回调，而两端
    // 「当前页面」的载体不同（教师端 = `TeacherPage` 的一个分支，学生端 = [ChildPage]
    // 单一状态）。只写教师端那一份，学生端点「我的」就毫无反应——而 `flutter analyze`
    // 完全照不出来。
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
        (w) => w is AppFocusableAction && w.semanticLabel == '小明 · 未分班',
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
      // ticket 08：教师端「我的」新增系统分区，内容变长，抬高 surface 让整屏
      // 个人信息（含退出登录）都在首屏构建出来（ListView 懒构建，落出视口即不在树）。
      await tester.binding.setSurfaceSize(const Size(1000, 1200));
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
      // ticket 08：教师端「我的」新增系统分区，内容变长，「退出登录」可能落在首屏之外；
      // ListView 懒构建，未滚入视口的子项不在渲染树里，需先 ensureVisible 再断言。
      await tester.ensureVisible(find.text('退出登录'));
      await tester.pump();
      expect(find.text('退出登录'), findsOneWidget,
          reason: '个人信息页必须真的渲染出来（不是被更高优先级的面板顶替）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('从「我的」切回侧栏页签，高亮唯一且跟随', (tester) async {
      // ticket 08：教师端「我的」新增系统分区，内容变长，抬高 surface 让整屏构建。
      await tester.binding.setSurfaceSize(const Size(1000, 1200));
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

      // ticket 08：模型管理已不是侧栏项（搬进「我的」系统分区），改用仍留在侧栏的
      // 「班级」验证「侧栏页签 ↔ 我的」之间的单一高亮状态切换（ticket 10 合并入口后
      // 承载学生的侧栏项改名为「班级」）。
      await tester.tap(find.text('班级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_activeLabels(tester), ['班级']);

      await tester.tap(find.byWidgetPredicate(
        (w) => w is AppFocusableAction && w.semanticLabel == '妈妈 · 教师账号',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_activeLabels(tester), isEmpty,
          reason: '进入「我的」后侧栏不应残留高亮页签');

      // 切回侧栏页签：高亮应唯一且跟随回到「班级」。
      await tester.tap(find.text('班级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_activeLabels(tester), ['班级'],
          reason: '从「我的」切回侧栏页签，高亮唯一且跟随');
      expect(tester.takeException(), isNull);
    });
  });

  group('行为：ticket 10 合并入口「班级」状态可达（全部学生视图 / 学生详情）', () {
    // ⚠️ 这两个页面态（StudentsPage / StudentDetailPage）是合并入口的承载页；只靠
    // sealed 穷尽性只能保证「编译过」，UI 层若没真构建过仍可能漏接 `onOpenStudent`
    // 之类的跳转回调。`flutter analyze` 照不出来，必须真点。
    testWidgets('教师端：点「班级」高亮唯一且默认渲染「全部学生」视图', (tester) async {
      await _pumpTeacherHome(tester);
      expect(_activeLabels(tester), ['概览']);

      await tester.tap(find.text('班级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_activeLabels(tester), ['班级'],
          reason: '同一时刻侧栏只能有一个高亮项（单一导航状态）');
      expect(find.text('学生管理'), findsOneWidget,
          reason: 'StudentsScreen 默认「全部学生」视图应真正渲染学生管理页');
      expect(tester.takeException(), isNull);
    });

    testWidgets('教师端：从「全部学生」drill 进学生详情，侧栏零高亮且详情页渲染',
        (tester) async {
      await _pumpTeacherHome(tester);
      expect(_activeLabels(tester), ['概览']);

      await tester.tap(find.text('班级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_activeLabels(tester), ['班级']);
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

    testWidgets('教师端：学生详情点返回回到「班级」的全部学生视图，而非工作台概览',
        (tester) async {
      await _pumpTeacherHome(tester);
      expect(_activeLabels(tester), ['概览']);

      await tester.tap(find.text('班级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_activeLabels(tester), ['班级']);

      // 进入学生详情。
      await tester.tap(find.text('小明'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('错题本'), findsWidgets,
          reason: '学生详情页应渲染');
      expect(_activeLabels(tester), isEmpty,
          reason: '详情页是 drill-down，不应高亮任何顶级侧栏项');

      // 点返回：应回落到「班级」的全部学生视图并高亮，而不是工作台概览。
      await tester.tap(find.byWidgetPredicate(
        (w) => w is AppIconAction && w.semanticLabel == '返回',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // ticket 05：壳内换页有 150ms 交叉淡入，旧页（学生详情）在淡出期间仍挂载，
      // 其树里可能含与管理页同名的「学生管理」文本。等转场结束再断言管理页唯一渲染。
      await tester.pump(const Duration(milliseconds: 200));
      expect(_activeLabels(tester), ['班级'],
          reason: '学生详情返回应回到班级入口并高亮，而非工作台概览');
      expect(find.text('学生管理'), findsOneWidget,
          reason: '返回后应再次渲染全部学生视图');
      expect(tester.takeException(), isNull);
    });
  });

  group('ticket 02/04/10：合并入口「班级」的「按班级」视图与下钻（ADR-0086）', () {
    // ⚠️ 班级管理前端的下钻页 `ClassStudentsPage` 仍是独立的 `TeacherPage` 分支；合并后
    // 进入它的入口从独立侧栏项「班级管理」变成合并入口「班级」的「按班级」视图。只靠
    // sealed 穷尽性只能保证「编译过」，UI 层若没真构建过仍可能漏接 `onOpenClass` /
    // `onBack` 跳转。`flutter analyze` 照不出来，必须真点。
    testWidgets('教师端：点「班级」切到「按班级」视图，高亮唯一且渲染班级卡片', (tester) async {
      await _pumpTeacherHome(tester);
      expect(_activeLabels(tester), ['概览']);

      await tester.tap(find.text('班级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_activeLabels(tester), ['班级'],
          reason: '同一时刻侧栏只能有一个高亮项（单一导航状态）');

      // 默认是「全部学生」视图；切到「按班级」才渲染班级卡片。
      await tester.tap(find.text('按班级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // 班级卡片（桩返回「三(1)班」）应真实渲染。
      expect(find.text('三(1)班'), findsOneWidget,
          reason: 'ClassManagementScreen 应真正渲染班级卡片');
      expect(tester.takeException(), isNull);
    });

    testWidgets('教师端：从「按班级」下钻进班级，返回回到「按班级」视图（落点唯一）',
        (tester) async {
      await _pumpTeacherHome(tester);
      await tester.tap(find.text('班级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('按班级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('三(1)班'), findsOneWidget);

      // 点班级卡片下钻（经 HomeScreen 接好的 `onOpenClass` 进入 ClassStudentsPage）。
      await tester.tap(find.text('三(1)班'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 下钻页标题含班级名；全量视图的「全部/各班/未分班」筛选 chip 在此隐藏。
      expect(find.textContaining('三(1)班'), findsWidgets,
          reason: '下钻页标题应含班级名');
      expect(find.text('全部'), findsNothing,
          reason: '下钻页不应出现全量视图的筛选 chip');
      expect(tester.takeException(), isNull);

      // 返回回落到「按班级」视图（单一出口，不裸 Navigator.pop）；落点由历史栈决定，
      // 且视图经 `studentsEntryViewProvider` 还原为进入前的「按班级」。
      await tester.tap(find.byWidgetPredicate(
        (w) => w is AppFocusableAction && w.semanticLabel == '返回',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_activeLabels(tester), ['班级'],
          reason: '从班级下钻返回应回到「班级」入口并高亮');
      expect(tester.takeException(), isNull);
    });
  });

  group('ticket 06：班内添加/导入归属本班（ADR-0086）', () {
    // ⚠️ 下钻页「添加学生」必须落到 StudentFormScreen 创建态（而非概览或无反应），
    // 且把本班 classId 经 AddStudentPage 传入表单——这是 ticket 05 后端 class_id 归属的
    // 前端入口。`flutter analyze` 照不出来，必须真点。
    testWidgets('教师端：班级下钻页「添加学生」打开创建态表单', (tester) async {
      await _pumpTeacherHome(tester);
      await tester.tap(find.text('班级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('按班级'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('三(1)班'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('全部'), findsNothing, reason: '已进入班级下钻页');

      // 下钻页「添加学生」入口（AppIconAction）应打开 StudentFormScreen。
      await tester.tap(find.byWidgetPredicate(
        (w) => w is AppIconAction && w.semanticLabel == '添加学生',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('学生昵称（例如：大宝）'), findsOneWidget,
          reason: '下钻页「添加学生」应打开创建态表单（StudentFormScreen）');
      expect(find.text('添加学生账号'), findsOneWidget,
          reason: '表单标题应为创建态');
      expect(tester.takeException(), isNull);
    });
  });

  group('ADR-0088 ticket 02：运行轨迹入口（全步骤口径，与历史会话分离）', () {
    // ⚠️ ticket 08：运行轨迹页已不在侧栏，改由「我的」页内系统分区进入。sealed 穷尽性
    // 只能保证「编译过」，UI 层若没真构建过仍可能漏接入口——必须真点。
    testWidgets('教师端：从「我的」系统分区点「运行轨迹」渲染轨迹页', (tester) async {
      await _pumpTeacherHome(tester, extra: [
        runTraceRepositoryProvider.overrideWithValue(_StubRunTraceRepo()),
      ]);
      expect(_activeLabels(tester), ['概览']);

      // ticket 08：运行轨迹已不在侧栏，改由「我的」页内系统分区进入。
      // 「我的」不在侧栏项里，它住在侧栏底部的用户区（AdaptiveUserBlock）。
      // 直接按它在教师端的语义标签点开——不要找字面「我的」文本（不存在）。
      await tester.tap(find
          .byWidgetPredicate((w) =>
              w is AppFocusableAction && w.semanticLabel == '妈妈 · 教师账号')
          .first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.text('运行轨迹'));
      await tester.pump();

      expect(find.text('系统'), findsOneWidget,
          reason: '「我的」页内应有系统分区');
      expect(find.text('运行轨迹'), findsOneWidget,
          reason: '系统分区含运行轨迹入口');

      await tester.tap(find.text('运行轨迹'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 运行轨迹由「我的」入栈进入，不再是侧栏项 → 侧栏无高亮。
      expect(_activeLabels(tester), isEmpty,
          reason: '运行轨迹入栈自「我的」，侧栏不残留高亮');
      expect(find.textContaining('还没有 AI 运行记录'), findsOneWidget,
          reason: 'RunTracePage 应真正渲染（桩返回空列表 → 空态）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('「我的」系统分区：模型管理 / 运行轨迹可从「我的」到达并返回',
        (tester) async {
      await _pumpTeacherHome(tester, extra: [
        runTraceRepositoryProvider.overrideWithValue(_StubRunTraceRepo()),
      ]);
      // 「我的」不在侧栏项里，它住在侧栏底部的用户区（AdaptiveUserBlock）。
      // 直接按它在教师端的语义标签点开——不要找字面「我的」文本（不存在）。
      await tester.tap(find
          .byWidgetPredicate((w) =>
              w is AppFocusableAction && w.semanticLabel == '妈妈 · 教师账号')
          .first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.text('运行轨迹'));
      await tester.pump();

      // 两个系统入口都应可达。
      expect(find.text('模型管理'), findsOneWidget);
      expect(find.text('运行轨迹'), findsOneWidget);

      // 模型管理：到达（出现返回头）后即可返回「我的」系统分区。
      await tester.ensureVisible(find.text('模型管理'));
      await tester.pump();
      await tester.tap(find.text('模型管理'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          find.byWidgetPredicate(
              (w) => w is AppIconAction && w.semanticLabel == '返回'),
          findsWidgets,
          reason: '从「我的」入栈进入的页面应带返回头');
      await tester.tap(find.byWidgetPredicate(
          (w) => w is AppIconAction && w.semanticLabel == '返回'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.text('系统'));
      await tester.pump();
      expect(find.text('系统'), findsOneWidget,
          reason: '从模型管理返回应落回「我的」系统分区');

      // 运行轨迹：到达后返回「我的」。
      await tester.ensureVisible(find.text('运行轨迹'));
      await tester.pump();
      await tester.tap(find.text('运行轨迹'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('还没有 AI 运行记录'), findsOneWidget,
          reason: 'RunTracePage 应真正渲染');
      await tester.tap(find.byWidgetPredicate(
          (w) => w is AppIconAction && w.semanticLabel == '返回'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.text('系统'));
      await tester.pump();
      expect(find.text('系统'), findsOneWidget,
          reason: '从运行轨迹返回应落回「我的」系统分区');
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
      );
      expect(highlightFor(page), same(page),
          reason: '新页面态不应引入并列高亮逻辑，否则又回到 ADR-0059 前的漏清坑');
    });
  });

  group('T: 侧栏收敛「发布任务」到「任务」（方案 A）', () {
    // ⚠️ 本次合并的核心：原来的「布置任务」是一级侧栏入口，与「任务」并列，既多占
    // 一项、又让「发布任务」这个动作散落在两个入口。现在它收进「任务」页（页头
    // 「发布任务」按钮 + 空态 CTA），侧栏只剩「任务」。
    test('侧栏目的地：已无「布置任务」，且「任务」覆盖生成页高亮', () {
      final dests = NavigationDestinations(
        goEntry: (_) {},
        goChildTab: (_) {},
        goProfile: () {},
        genTrailing: (_) => null,
      ).teacher(const CreateTaskPage(), const TaskGenIdle());
      final labels = dests.expand((s) => s.items).map((d) => d.label).toList();
      expect(labels, isNot(contains('布置任务')),
          reason: '「布置任务」已收进「任务」页，不应再作为独立侧栏入口');
      expect(labels, contains('任务'));
      final task =
          dests.expand((s) => s.items).firstWhere((d) => d.label == '任务');
      expect(task.active, isTrue,
          reason: '在生成页（CreateTaskPage）时「任务」应高亮，生成进度徽标也挂这一项');
    });

    testWidgets('教师端：侧栏不再有「布置任务」，点「任务」高亮唯一', (tester) async {
      await _pumpTeacherHome(tester);
      expect(_activeLabels(tester), ['概览']);

      expect(
        tester
            .widgetList<AppSidebarItem>(find.byType(AppSidebarItem))
            .any((item) => item.label == '布置任务'),
        isFalse,
        reason: '「发布任务」已收进「任务」页，侧栏不应再有「布置任务」项',
      );

      await tester.tap(find.text('任务'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_activeLabels(tester), ['任务'],
          reason: '同一时刻侧栏只能有一个高亮项（单一导航状态）');
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

/// 运行轨迹取数桩（ADR-0088 ticket 02）：空列表 → 轨迹页渲染空态。
class _StubRunTraceRepo implements RunTraceRepository {
  @override
  Future<List<RunTraceRun>> runs() async => const [];

  @override
  Future<RunTraceDetail> detail(String runId) async =>
      throw UnimplementedError();

  // ticket 03：破窗入口只对 admin 开放，本桩不涉及，抛未实现即可。
  @override
  Future<RunTraceDetail> reveal(String runId, String reason) async =>
      throw UnimplementedError();
}

/// 用桩 repository 泵起教师端 HomeScreen，使「学生」入口能渲染并 drill 进详情。
Future<void> _pumpTeacherHome(
  WidgetTester tester, {
  List<Override> extra = const [],
}) async {
  // ticket 07：侧栏是 lazy ListView，分组后「运行轨迹」落在「系统」组末位（第 14 行），
  // 默认 800×600 视口渲染不到它，find.text('运行轨迹') 直接落空。抬高 surface 让
  // 14 行侧栏完整渲染；tearDown 还原，避免污染同文件其它测试的默认视口。
  await tester.binding.setSurfaceSize(const Size(1000, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
