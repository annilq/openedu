// 守住紧凑档抽屉的「可关闭性」（评审 P1-1 / P2-2）。
//
// 修复前：抽屉项 `onTap` 只调 `destination.onTap`，从不关抽屉（`adaptive_shell.dart`
// `_DrawerItem`），唯一出路是点遮罩。于是教师点菜单 → 抽屉不动、遮罩继续盖着新页面。
// 本文件守三条关闭路径 + 一条回归：
//   1. 点抽屉内菜单项 → 抽屉关闭 **且** 目标页已切换（两者都要发生）；
//   2. 点「我的」同样关闭（该入口两个角色共用，教师端抽屉里也走这一条）；
//   3. 抽屉上左滑可关闭；
//   4. 点遮罩关闭仍然有效（回归项，不得被本票弄丢）。
//
// 视口必须用 `setSurfaceSize`：test surface 默认 800×600，用 SizedBox 撑宽度会被裁到
// 800，断点判定落在错档位（紧凑档要求可用宽度 < AppLayout.compactMax = 700）。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart' show AppUserMode;
import 'package:kids_learn/shared/widgets/adaptive_shell.dart'
    show AdaptiveNavDestination, AdaptiveShell;

const _viewport = Size(600, 800);

Future<StorageService> _makeStorage() async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  return storage;
}

/// 抽屉项在渲染树里的矩形：抽屉展开时它落在视口内（left ≥ 0），
/// 收起后随抽屉整体左移出屏幕（right ≤ 0）。
Rect _drawerItemRect(WidgetTester tester, String label) =>
    tester.getRect(find.text(label));

/// 教师端壳（紧凑档：顶部汉堡 + 左抽屉）。
Future<void> _pumpShell(
  WidgetTester tester,
  StorageService storage, {
  List<AdaptiveNavDestination> destinations = const [
    AdaptiveNavDestination(icon: LucideIcons.house, label: '概览', active: true),
    AdaptiveNavDestination(icon: LucideIcons.users, label: '学生', active: false),
  ],
  AdaptiveNavDestination? profile,
  Widget body = const SizedBox.expand(),
}) async {
  await tester.binding.setSurfaceSize(_viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: ShadApp.custom(
        appBuilder: (context) => CupertinoApp(
          home: AdaptiveShell(
            mode: AppUserMode.teacher,
            destinations: destinations,
            profileDestination: profile,
            body: body,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('打开导航菜单'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('点抽屉内菜单项：抽屉关闭且目标页已切换', (tester) async {
    final storage = await _makeStorage();
    var tapped = 0;
    await _pumpShell(
      tester,
      storage,
      destinations: [
        const AdaptiveNavDestination(
            icon: LucideIcons.house, label: '概览', active: true),
        AdaptiveNavDestination(
            icon: LucideIcons.users,
            label: '学生',
            active: false,
            onTap: () => tapped++,
        ),
      ],
    );
    await _openDrawer(tester);
    expect(_drawerItemRect(tester, '学生').left, greaterThanOrEqualTo(0),
        reason: '前置条件：抽屉已展开，抽屉项落在视口内');

    await tester.tap(find.text('学生'));
    await tester.pumpAndSettle();

    expect(tapped, 1, reason: '点项必须切换目标页');
    expect(_drawerItemRect(tester, '学生').right, lessThanOrEqualTo(0),
        reason: '点项后抽屉必须整体移出视口，否则新页面仍被遮罩与抽屉盖着');
  });

  testWidgets('点抽屉内「我的」：同样关闭', (tester) async {
    final storage = await _makeStorage();
    var profileTapped = 0;
    await _pumpShell(
      tester,
      storage,
      profile: AdaptiveNavDestination(
        icon: LucideIcons.user,
        label: '我的',
        active: false,
        onTap: () => profileTapped++,
      ),
    );
    await _openDrawer(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(profileTapped, 1, reason: '「我的」必须切页');
    expect(_drawerItemRect(tester, '我的').right, lessThanOrEqualTo(0),
        reason: '「我的」与抽屉项共用同一份 items 列表，也必须带关闭动作');
  });

  testWidgets('抽屉上左滑可关闭', (tester) async {
    final storage = await _makeStorage();
    await _pumpShell(tester, storage);
    await _openDrawer(tester);

    // 起点取抽屉内、避开抽屉项的可点区域（列表项集中在顶部）。
    await tester.timedDrag(
      find.text('概览'),
      const Offset(-160, 0),
      const Duration(milliseconds: 120),
    );
    await tester.pumpAndSettle();

    expect(_drawerItemRect(tester, '概览').right, lessThanOrEqualTo(0),
        reason: '左滑必须能关掉抽屉：移动端只有点遮罩一条出路不够');
  });

  testWidgets('位移不足的左滑不关闭（不误触）', (tester) async {
    final storage = await _makeStorage();
    await _pumpShell(tester, storage);
    await _openDrawer(tester);

    await tester.timedDrag(
      find.text('概览'),
      const Offset(-20, 0),
      const Duration(milliseconds: 200),
    );
    await tester.pumpAndSettle();

    expect(_drawerItemRect(tester, '概览').left, greaterThanOrEqualTo(0),
        reason: '轻微位移不应关掉抽屉，否则列表竖向滚动会被误判成关闭');
  });

  testWidgets('点遮罩关闭仍然有效（回归）', (tester) async {
    final storage = await _makeStorage();
    await _pumpShell(tester, storage);
    await _openDrawer(tester);

    // 抽屉占左侧 240，右侧（X=500）只剩遮罩。
    await tester.tapAt(const Offset(500, 400));
    await tester.pumpAndSettle();

    expect(_drawerItemRect(tester, '概览').right, lessThanOrEqualTo(0),
        reason: '点遮罩是本票之前唯一的关闭路径，不得被弄丢');
  });
}
