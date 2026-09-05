// 验证 AdaptiveShell 的缩起按钮在中屏 / 大屏下都能生效（修复前大屏回调为空实现导致点击无效）。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/adaptive_shell.dart'
    show AdaptiveShell, AdaptiveNavDestination;
import 'package:kids_learn/shared/widgets/app_sidebar.dart'
    show SidebarCollapseScope;

void main() {
  Future<StorageService> makeStorage() async {
    SharedPreferences.setMockInitialValues({});
    final s = StorageService();
    await s.init();
    return s;
  }

  Widget pumpShell(WidgetTester tester, StorageService storage, double width) {
    return ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 800)),
          child: SizedBox(
            width: width,
            height: 800,
            child: AdaptiveShell(
              mode: AppUserMode.parent,
              destinations: const [
                AdaptiveNavDestination(
                    icon: LucideIcons.house, label: '首页', active: true),
              ],
              body: const Placeholder(),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('大屏(≥1024)点击缩起按钮应切换 SidebarCollapseScope.collapsed',
      (tester) async {
    final storage = await makeStorage();
    await tester.pumpWidget(pumpShell(tester, storage, 1280));
    await tester.pumpAndSettle();

    final scopeBefore =
        tester.widget<SidebarCollapseScope>(find.byType(SidebarCollapseScope));
    expect(scopeBefore.collapsed, isFalse);

    // 找到缩起按钮（44x44 的 GestureDetector，内含 panelLeftClose 图标）。
    await tester.tap(find.byIcon(LucideIcons.panelLeftClose));
    await tester.pumpAndSettle();

    final scopeAfter =
        tester.widget<SidebarCollapseScope>(find.byType(SidebarCollapseScope));
    expect(scopeAfter.collapsed, isTrue);
    expect(storage.getSidebarCollapsed(), isTrue);
  });

  testWidgets('中屏(700–1023)缩起按钮同样生效', (tester) async {
    final storage = await makeStorage();
    await tester.pumpWidget(pumpShell(tester, storage, 900));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.panelLeftClose));
    await tester.pumpAndSettle();

    final scope =
        tester.widget<SidebarCollapseScope>(find.byType(SidebarCollapseScope));
    expect(scope.collapsed, isTrue);
  });
}
