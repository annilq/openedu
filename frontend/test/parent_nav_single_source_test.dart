import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/screens/home_screen.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_sidebar.dart' show AppSidebarItem;
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';

/// 家长端导航「单一事实源」守卫（ADR-0059）。
///
/// 线上事故：家长端曾经有三个**并列**的导航状态——侧栏索引 `_parentNavIndex`、
/// 覆盖层 `_reviewingTask` / `_editingChild`、布尔 `_showProfile`。`AdaptiveShell`
/// 的 `detail` 在中屏 / 紧凑档会**整幅顶替** `body`，于是三者谁盖谁要靠每个回调
/// 自己记得清理：侧栏点击记得清覆盖层、底部「我的」忘了清 —— 从任务列表进审核后
/// 点「我的」，看到的仍是审核页，个人信息页压根没进渲染树。
///
/// 现在三者合成一个 `sealed _ParentPage`，壳也不再有 `detail`。本文件守两件事：
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
        '_parentNavIndex',
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
          reason: '$banned 不应再出现在 $_homeFile 的代码里：家长端导航状态必须是'
              '单一的 `_ParentPage`（ADR-0059）。\n${inCode.join('\n')}',
        );
      }
      expect(src.contains('_ParentPage _parentPage'), isTrue,
          reason: '家长端当前页面应由 `_ParentPage _parentPage` 单独承载');
    });
  });

  group('行为：「我的」对两个角色都要真的打开个人信息', () {
    // ⚠️ 这组用例的存在理由：`_onProfileTap()` 是**两个角色共用**的回调，而两端
    // 「当前页面」的载体不同（家长端 = `_ParentPage` 的一个分支，娃娃端 =
    // 「页签 + `_showProfile` 布尔」的二选一）。只写家长端那一份，娃娃端点「我的」
    // 就毫无反应——而 `flutter analyze` 完全照不出来。
    testWidgets('娃娃端：点「我的」渲染个人信息页，且页签不再高亮', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: ShadApp.custom(
            theme: AppTheme.shadFor(false, AppUserMode.child, AppDensity.compact),
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
          reason: '娃娃端点「我的」必须真的渲染个人信息页');
      expect(_activeLabels(tester), isEmpty,
          reason: '显示个人信息时页签应全部取消高亮（否则「首页」与「我的」同时亮）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('家长端：进入「我的」后，侧栏不留任何高亮页签', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
          child: ShadApp.custom(
            theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
            appBuilder: (context) => CupertinoApp(
              home: HomeScreen(user: _parent(), onLogout: () {}),
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
        (w) => w is AppFocusableAction && w.semanticLabel == '妈妈 · 家长账号',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 「我的」不在侧栏项里（它在侧栏底部的用户区），所以此时侧栏应**零**高亮。
      // 修复前这里是 ['概览'] —— `_showProfile` 与 `_parentNavIndex` 同时为真。
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
            theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
            appBuilder: (context) => CupertinoApp(
              home: HomeScreen(user: _parent(), onLogout: () {}),
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
        (w) => w is AppFocusableAction && w.semanticLabel == '妈妈 · 家长账号',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_activeLabels(tester), isEmpty);
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

UserModel _parent() => UserModel(
      id: 'u1',
      username: 'parent1',
      displayName: '妈妈',
      role: 'parent',
    );

UserModel _child() => UserModel(
      id: 'u2',
      username: 'child1',
      displayName: '小明',
      role: 'child',
      grade: 2,
    );
