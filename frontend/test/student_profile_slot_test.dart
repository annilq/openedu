import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/child_pages.dart';
import 'package:kids_learn/features/home/presentation/providers/home_notifier.dart';
import 'package:kids_learn/features/home/presentation/screens/home_screen.dart';
import 'package:kids_learn/features/home/presentation/screens/teacher_destinations.dart';
import 'package:kids_learn/features/home/presentation/widgets/student_home.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/presentation/resource.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';
import 'package:kids_learn/shared/widgets/app_sidebar.dart' show AppSidebarItem;

/// 学生端「我的」是**常驻的第五个槽位**（ADR-0059 / nav-ia-review P1-2）。
///
/// 修复前 `_buildChildView()` 在 [ChildProfilePage] 时走独立分支、把整个
/// [IndexedStack] 移出渲染树：看一眼个人信息，四个页签的 State 全部销毁，
/// 切回首页要重建，滚动位置与已加载数据全丢。这类「整棵子树被销毁」在
/// `flutter analyze` 上完全没有痕迹，只能靠真点 + 观测 State 存活来抓。
///
/// 本文件守三个缝：
///   1. [childPages] 映射层：「我的」与四个页签**同构**（不再是 -1 特例）；
///   2. [NavigationDestinations.child] 目的地层：显示「我的」时页签零高亮；
///   3. [HomeScreen] 组合根（真泵起）：切走再切回，页签页的 State 未重建。
void main() {
  group('映射：「我的」与四个页签同构（不再走 -1 特例）', () {
    test('「我的」占第五个槽位，索引往返同构', () {
      // 修复前这里是 -1（「不进 IndexedStack」），正是「整棵子树被移出渲染树」的
      // 源头：槽位不存在 → 切到「我的」只能把 IndexedStack 换掉。
      expect(childPageIndex(const ChildProfilePage()), 4,
          reason: '「我的」应与四个页签同构地占一个 IndexedStack 槽位，'
              '而不是用 -1 把自己排除在栈外');
      expect(childPageFromIndex(4), const ChildProfilePage(),
          reason: '下标 → 页面必须能回到「我的」，否则槽位与导航状态不是同构映射');
    });

    test('五个槽位逐一往返，无越界回落', () {
      // 越界回落首页是 [childPageFromIndex] 的既有兜底，不能吞掉合法的第 5 槽位。
      for (var index = 0; index < 5; index++) {
        expect(childPageIndex(childPageFromIndex(index)), index,
            reason: '槽位 $index 应往返成自身');
      }
    });
  });

  group('目的地：显示「我的」时四个页签一律取消高亮', () {
    test('「我的」的槽位下标传给页签目的地 → 零高亮', () {
      final dests = NavigationDestinations(
        go: (_) {},
        goChildTab: (_) {},
        goProfile: () {},
        genTrailing: (_) => null,
      ).child(childPageIndex(const ChildProfilePage()));

      expect(dests.map((d) => d.label), ['首页', '复习', '错题本', '掌握度'],
          reason: '「我的」不是页签，不应混进页签目的地列表');
      expect(dests.map((d) => d.active), everyElement(isFalse),
          reason: '显示「我的」时四个页签必须全部取消高亮，否则两个入口同时亮');
    });

    test('四个页签各自只亮自己', () {
      final dests = NavigationDestinations(
        go: (_) {},
        goChildTab: (_) {},
        goProfile: () {},
        genTrailing: (_) => null,
      );
      for (var index = 0; index < 4; index++) {
        final active = dests
            .child(index)
            .where((d) => d.active)
            .map((d) => d.label)
            .toList();
        expect(active, hasLength(1), reason: '页签 $index 应且只应高亮一项');
      }
    });
  });

  group('行为：切走再切回，页签页的 State 未被重建', () {
    testWidgets('首页滚到中部 → 切「我的」→ 切回首页，滚动偏移未归零', (tester) async {
      await _pumpStudentHome(tester);
      final before = _homeScrollPosition(tester);
      expect(before.maxScrollExtent, greaterThan(200.0),
          reason: '首页内容应足够长，否则滚不动、本用例观测不到偏移是否被销毁');

      await tester.drag(_homeFinder, const Offset(0, -220));
      await tester.pump(const Duration(milliseconds: 400));
      expect(before.pixels, greaterThan(0.0), reason: '首页应已被滚到中部');

      // 侧栏底部用户区（学生端「我的」入口之一）。
      await tester.tap(_profileEntry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('退出登录'), findsOneWidget,
          reason: '应真的切到个人信息页');

      await tester.tap(find.text('首页'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final after = _homeScrollPosition(tester);
      expect(after, same(before),
          reason: '切回首页后 ScrollPosition 应是**同一个对象**：换了对象说明'
              'IndexedStack 整棵被移出渲染树、四个页签的 State 全被销毁重建');
      expect(after.pixels, before.pixels,
          reason: '看了一眼个人信息再切回首页，首页的滚动位置不该被重置');
      expect(_activeLabels(tester), ['首页']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('切「我的」再切回，页签页已渲染的内容仍在渲染树里', (tester) async {
      await _pumpStudentHome(tester);
      final before = _homeScrollPosition(tester);
      await tester.drag(_homeFinder, const Offset(0, -220));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(_profileEntry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 「我的」在槽位里 ⇒ 四个页签仍在渲染树（只是离屏），不是被整棵 dispose。
      expect(_homeFinder, findsOneWidget,
          reason: '显示「我的」时四个页签必须仍在渲染树里常驻挂载，否则切回来'
              '只能重建（滚动位置 / 已加载数据全丢）');
      expect(_homeScrollPosition(tester), same(before));
      expect(tester.takeException(), isNull);
    });
  });

  group('行为：两个「我的」入口行为一致（回调两个角色共用）', () {
    // ⚠️ `_onProfileTap()` 是教师端 / 学生端共用的回调。改它必须两端各走一遍：
    // 只写学生端那份，教师端「我的」会失效；而 `flutter analyze` 完全照不出来。
    testWidgets('紧凑档：底栏「我的」渲染个人信息页', (tester) async {
      await _pumpStudentHome(tester, size: const Size(600, 800));

      await tester.tap(_bottomItem('我的'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('退出登录'), findsOneWidget,
          reason: '底栏「我的」必须真的渲染个人信息页');
      expect(tester.takeException(), isNull);
    });

    testWidgets('紧凑档：底栏「我的」切回首页，首页重新可见', (tester) async {
      await _pumpStudentHome(tester, size: const Size(600, 800));
      expect(find.text('今日任务'), findsOneWidget, reason: '起始应落在首页');

      await tester.tap(_bottomItem('我的'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('退出登录'), findsOneWidget);

      await tester.tap(_bottomItem('首页'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('今日任务'), findsOneWidget,
          reason: '底栏点回「首页」应切回首页，与宽屏侧栏同一个语义');
      expect(find.text('退出登录'), findsNothing,
          reason: '切回首页后不应还停在个人信息页');
      expect(tester.takeException(), isNull);
    });

    testWidgets('宽屏：侧栏底部用户区「我的」与底栏同语义', (tester) async {
      await _pumpStudentHome(tester);
      expect(_activeLabels(tester), ['首页']);

      await tester.tap(_profileEntry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('退出登录'), findsOneWidget,
          reason: '侧栏底部用户区「我的」必须真的渲染个人信息页');
      expect(_activeLabels(tester), isEmpty,
          reason: '显示个人信息时页签应全部取消高亮（否则「首页」与「我的」同时亮）');
      expect(tester.takeException(), isNull);
    });
  });
}

/// 学生端首页（[StudentHome]）在渲染树里的位置。
///
/// `skipOffstage: false` 是本票的重点：首页不在当前槽位时它仍是「离屏但活着」，
/// 默认查找会跳过离屏子树，那就观测不到「是否还在渲染树里」了。
final Finder _homeFinder = find.byWidgetPredicate(
  (w) => w is StudentHome,
  skipOffstage: false,
);

/// 首页的滚动位置：它是「State 活没活着」的可观测代理——State 一被销毁重建，
/// 这个对象就换了一个（pixels 也随之归零）。
ScrollPosition _homeScrollPosition(WidgetTester tester) {
  final scrollable = find.descendant(
    of: _homeFinder,
    matching: find.byType(Scrollable, skipOffstage: false),
  );
  expect(scrollable, findsOneWidget,
      reason: '学生端首页应挂在渲染树里（CustomScrollView → Scrollable）');
  return tester.state<ScrollableState>(scrollable).position;
}

/// 宽屏档的「我的」入口：侧栏底部用户区。
final Finder _profileEntry = find.byWidgetPredicate(
  (w) => w is AppFocusableAction && w.semanticLabel == '小明 · 未分班',
);

/// 侧栏（AppSidebarItem）里处于高亮态的标签——「我的」不计入，它在侧栏底部用户区。
List<String> _activeLabels(WidgetTester tester) => tester
    .widgetList<AppSidebarItem>(find.byType(AppSidebarItem))
    .where((item) => item.active)
    .map((item) => item.label)
    .toList();

/// 底栏里的某一项（`_BottomNavItem` 把目的地标签挂在 [AppFocusableAction] 上）。
///
/// 高亮与否不在这里断言：底栏的高亮只是「accent 色图标」这一个像素级差别，而四个
/// 页签常驻在 [IndexedStack] 里、屏上还叠着首页自己的按钮，按图标找会撞到页签页
/// 内部的同名图标。高亮语义改由上方的 [NavigationDestinations.child] 单测与宽屏
/// 侧栏的 [_activeLabels] 观测——那里是唯一的真源，不重复测同一件事。
Finder _bottomItem(String label) => find.byWidgetPredicate(
      (w) => w is AppFocusableAction && w.semanticLabel == label,
    );

/// 用种子任务泵起学生端 HomeScreen。
///
/// 种子任务让首页内容超过一屏（否则滚不动，滚动位置这个观测点失效）。取数走真实的
/// [ResourceNotifier]（刷新时机保持现状——本票不碰它，那是 ticket 13）：切回首页
/// 照样会重拉一次，观测到的滚动位置守恒只可能来自「State 没被销毁」。
Future<void> _pumpStudentHome(
  WidgetTester tester, {
  Size size = const Size(1000, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        todayTasksNotifierProvider.overrideWith(
          (ref) => ResourceNotifier<List<TaskModel>>(() async => _seededTasks),
        ),
      ],
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
}

/// 12 条任务：让首页内容远超一屏，滚动位置这个观测点才有意义。
List<TaskModel> get _seededTasks => List<TaskModel>.generate(
      12,
      (i) => TaskModel(
        id: 't$i',
        title: '今日任务 ${i + 1}',
        status: 'assigned',
        questions: [
          QuestionModel(
            id: 'q$i',
            stem: '题目 ${i + 1}',
            qtype: 'choice',
            knowledgePoint: '知识点 ${i + 1}',
            subject: '数学',
            grade: 3,
          ),
        ],
      ),
    );

UserModel _child() => UserModel(
      id: 'u2',
      username: 'child1',
      displayName: '小明',
      role: 'child',
    );
