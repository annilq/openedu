// 守住 ADR-0045 / ADR-0059 的布局契约：
//   1. 内容区统一套 AppLayout.contentWide 上限并居中（大屏下不再无限拉宽）；
//   2. 断点分档：紧凑（< compactMax）走底栏 / 抽屉，其余走侧栏。
//
// 曾经还有「大屏 + detail 走 master-detail 双栏、中屏 detail 整幅顶替 body」一组
// 用例——detail 已在 ADR-0059 移除（壳只认一个 body），那组用例随之删除。
// 若有人把 detail 加回来，test/parent_nav_single_source_test.dart 会红。
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
import 'package:kids_learn/shared/widgets/app_sidebar.dart' show AppSidebar;

void main() {
  const bodyKey = ValueKey('body-pane');

  Future<StorageService> makeStorage() async {
    SharedPreferences.setMockInitialValues({});
    final s = StorageService();
    await s.init();
    return s;
  }

  /// 把测试窗口撑到 [width] 宽——`SizedBox` 不够用：test surface 默认 800x600，
  /// 更宽的 SizedBox 会被裁到 800，断点判定就落错档位。
  Future<void> pumpShell(
    WidgetTester tester,
    StorageService storage,
    double width,
  ) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AdaptiveShell(
            mode: AppUserMode.parent,
            destinations: const [
              AdaptiveNavDestination(
                  icon: LucideIcons.house, label: '首页', active: true),
            ],
            body: const Placeholder(key: bodyKey),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('大屏下内容区宽度钉到 contentWide 且水平居中', (tester) async {
    final storage = await makeStorage();
    await pumpShell(tester, storage, 2000);

    final body = tester.getRect(find.byKey(bodyKey));
    expect(body.width, AppLayout.contentWide,
        reason: '大屏下 body 必须被 contentWide 钉住，否则列表会被无限拉宽');

    // 侧栏 240 + 居中留白 (2000-240-1080)/2 = 340 → 左侧起点 580。
    const railWidth = AppLayout.sidebarExpanded;
    final expectedLeft = railWidth + (2000 - railWidth - AppLayout.contentWide) / 2;
    expect(body.left, closeTo(expectedLeft, 0.5),
        reason: '内容不足可用宽度时必须居中，不能贴左留一条空带');
  });

  testWidgets('窄屏下 contentWide 不生效（不破坏手机 / 小平板排布）', (tester) async {
    final storage = await makeStorage();
    await pumpShell(tester, storage, 400);

    expect(tester.getSize(find.byKey(bodyKey)).width, 400,
        reason: '400 < contentWide，约束不应生效，body 铺满可用宽度');
    expect(find.byType(AppSidebar), findsNothing, reason: '紧凑档不应出现侧栏');
  });

  testWidgets('宽度上限只约束横向：内容不足一屏时仍贴顶，不竖向居中', (tester) async {
    final storage = await makeStorage();
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AdaptiveShell(
            mode: AppUserMode.parent,
            destinations: const [
              AdaptiveNavDestination(
                  icon: LucideIcons.house, label: '首页', active: true),
            ],
            // 定高 50、非贪心：竖向若被居中，dy 会变成接近 375，而不是 0。
            body: const SizedBox(
              key: bodyKey,
              height: 50,
              width: 200,
              child: Placeholder(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(bodyKey));
    expect(rect.top, 0,
        reason: '内容贴顶是本仓明确口径；用 Center 做宽度居中会把短内容浮到屏幕中间');
    expect(rect.width, 200, reason: '横向也应保持内容自身宽度，不被撑满');
  });
}
