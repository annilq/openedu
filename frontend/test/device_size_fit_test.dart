// 「适配 device」的行为级守卫（ADR-0045）。
//
// 为什么需要它：本仓的断点逻辑本身有 `adaptive_shell_layout_test` 守着，但那只覆盖
// **四个**人工挑的宽度（400 / 900 / 1600 / 2000），而且用的是 `Placeholder` 当 body。
// 真正会出问题的两件事它照不到：
//
//   1. **真实设备宽度**。320 / 360 / 393 / 430 / 852（手机横屏）/ 744 / 1194 这些数
//      值才是用户手上的尺寸；400 与 320 之间、700 断点两侧的表现只能靠这类用例兜。
//   2. **窗口缩放会重排**。「适配 device」的定义就是「窗口变了、界面跟着变」——
//      而断点判定错写成只在 `initState` 读一次宽度、或把宽度缓存进 provider 时，
//      静态的多个宽度用例**全都照不出来**（每个用例都是新建 widget 树）。必须
//      在同一个 tester 里 `setSurfaceSize` 两次才咬得住。
//
// 另外覆盖了此前几乎没人守的两条路径：紧凑·娃娃端**底栏 6 项**的边界（320 宽下
// 每项只有 ~53px），以及**真实主屏**（`HomeScreen` 家长 / 娃娃两种角色）。
// `flutter analyze` 对这两件事一个字都说不出来——溢出不是类型错误。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/screens/home_screen.dart';
import 'package:kids_learn/main/app.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/adaptive_shell.dart'
    show AdaptiveShell, AdaptiveNavDestination;
import 'package:kids_learn/shared/widgets/app_sidebar.dart' show AppSidebar;

/// 真实设备逻辑像素宽度（含手机横屏与桌面两档），命名里带机型便于失败时定位。
const _deviceSizes = <String, Size>{
  'iPhone SE 竖屏 320': Size(320, 568),
  '安卓窄机 360': Size(360, 640),
  'iPhone 16 竖屏 393': Size(393, 852),
  'iPhone 16 Pro Max 430': Size(430, 932),
  'iPhone 16 横屏 852': Size(852, 393),
  'iPad mini 竖屏 744': Size(744, 1133),
  'iPad Pro 11 横屏 1194': Size(1194, 834),
  '桌面最小窗口 800': Size(800, 600),
  '桌面 1920': Size(1920, 1080),
};

Future<StorageService> _makeStorage() async {
  SharedPreferences.setMockInitialValues({});
  final s = StorageService();
  await s.init();
  return s;
}

/// 娃娃端导航共 6 项（5 个页签 + 「我的」）——底栏最挤的真实规模，
/// 不是 1 项的简化版：项数才是挤压的来源。
List<AdaptiveNavDestination> _childDestinations() => const [
      AdaptiveNavDestination(
          icon: LucideIcons.house, label: '首页', active: true),
      AdaptiveNavDestination(
          icon: LucideIcons.refreshCw, label: '复习', active: false),
      AdaptiveNavDestination(
          icon: LucideIcons.bookOpen, label: '错题本', active: false),
      AdaptiveNavDestination(
          icon: LucideIcons.sparkles, label: '问 AI 老师', active: false),
      AdaptiveNavDestination(
          icon: LucideIcons.target, label: '掌握度', active: false),
      AdaptiveNavDestination(
          icon: LucideIcons.userRound, label: '我的', active: false),
    ];

UserModel _user(String role) => UserModel(
      id: 'u1',
      username: role == 'parent' ? 'parent1' : 'kid1',
      displayName: role == 'parent' ? '妈妈' : '小明',
      role: role,
      grade: role == 'parent' ? null : 3,
    );

Widget _host(Widget child, AppUserMode mode) => ShadApp.custom(
      theme: AppTheme.shadFor(false, mode, AppDensity.compact),
      appBuilder: (context) => CupertinoApp(home: child),
    );

void main() {
  for (final entry in _deviceSizes.entries) {
    for (final mode in AppUserMode.values) {
      testWidgets('壳 · ${entry.key} · ${mode.name} 不溢出且档位正确', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final storage = await _makeStorage();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [storageServiceProvider.overrideWithValue(storage)],
            child: _host(
              AdaptiveShell(
                mode: mode,
                destinations: _childDestinations(),
                body: const SizedBox(
                  height: 2000,
                  child: ColoredBox(color: Color(0xFFEEDDCC)),
                ),
              ),
              mode,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final ex = tester.takeException();
        expect(ex, isNull, reason: '${entry.key} @${mode.name} 抛了：$ex');

        if (entry.value.width < AppLayout.compactMax) {
          expect(find.byType(AppSidebar), findsNothing,
              reason: '紧凑档（<${AppLayout.compactMax}）不应出现侧栏');
          if (mode == AppUserMode.child) {
            // 底栏项必须留在屏幕内——被挤出去时 find.text 仍找得到，
            // 但用户看不到，所以断言的是**几何**而不是存在性。
            for (final label in ['首页', '复习', '错题本', '我的']) {
              final f = find.text(label);
              expect(f, findsOneWidget, reason: '$label 在紧凑底栏里丢了');
              final r = tester.getRect(f);
              expect(r.left, greaterThanOrEqualTo(-0.5),
                  reason: '$label 左缘跑到屏幕外：${r.left}');
              expect(r.right, lessThanOrEqualTo(entry.value.width + 0.5),
                  reason: '$label 右缘跑到屏幕外：${r.right} > ${entry.value.width}');
            }
          }
        } else {
          expect(find.byType(AppSidebar), findsOneWidget,
              reason: '非紧凑档必须有侧栏');
        }
      });
    }
  }

  testWidgets('入口页（未登录）在手机宽度下不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = await _makeStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('窗口从 1400 缩到 500，壳必须跟着重排（侧栏 → 底栏）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = await _makeStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: _host(
          AdaptiveShell(
            mode: AppUserMode.child,
            destinations: _childDestinations(),
            body: const ColoredBox(color: Color(0xFFEEDDCC)),
          ),
          AppUserMode.child,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppSidebar), findsOneWidget, reason: '1400 宽应为侧栏档');

    await tester.binding.setSurfaceSize(const Size(500, 800));
    await tester.pumpAndSettle();

    expect(find.byType(AppSidebar), findsNothing,
        reason: '缩到 500 后必须切紧凑档（侧栏消失）——不消失就说明宽度被判死、没有重排');
    expect(find.text('首页'), findsOneWidget, reason: '紧凑档应出现底栏');
    expect(tester.takeException(), isNull);
  });

  // 真实主屏（不是 Placeholder 代餐）：页面里那些 `Wrap` 芯片组、统计行、
  // 顶栏 trailing 才是窄宽下真正会挤爆的东西。
  for (final size in const [Size(393, 852), Size(360, 640), Size(320, 568)]) {
    for (final role in const ['parent', 'child']) {
      testWidgets('真实主屏 ${size.width.toInt()} 宽 · $role 不溢出', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final storage = await _makeStorage();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [storageServiceProvider.overrideWithValue(storage)],
            child: _host(
              HomeScreen(user: _user(role), onLogout: () {}),
              role == 'parent' ? AppUserMode.parent : AppUserMode.child,
            ),
          ),
        );
        // 不用 pumpAndSettle：页面内有在途网络请求与持续动画，它会一直等不到静止。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
      });
    }
  }
}
