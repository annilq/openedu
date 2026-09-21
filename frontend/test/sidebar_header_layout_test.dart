// 守住侧栏头部的布局契约（切换娃娃选择器 + 收缩按钮）。
//
// 背景：`sidebarTop` 原先没有内边距契约——选择器只给自己的右侧塞了 12px，宿主
// （AppSidebar / 抽屉）一点不给。结果是同一侧栏里出现三种左边缘（头部 0 / 导航 8 /
// 分隔线 16），且卡片右缘比导航窄 48px。`flutter analyze` 照不出这类问题（它不是
// 类型错误），溢出也只在大屏/轨态才暴露，所以只能用行为测试守。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/children/domain/repositories/children_repository.dart';
import 'package:kids_learn/features/children/presentation/providers/children_notifier.dart';
import 'package:kids_learn/features/children/providers/children_provider.dart'
    show childrenNotifierProvider;
import 'package:kids_learn/features/home/presentation/widgets/parent/parent_child_selector.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/adaptive_shell.dart'
    show AdaptiveShell, AdaptiveNavDestination;
import 'package:kids_learn/shared/widgets/app_sidebar.dart'
    show AppSidebar, AppSidebarItem;
import 'package:kids_learn/shared/widgets/app_avatar.dart';
import 'package:kids_learn/shared/widgets/app_buttons.dart';
import 'package:kids_learn/shared/widgets/app_card.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';

/// 只为构造 notifier 存在；本测试不经它取数（状态由构造器直接种入）。
class _UnusedChildrenRepo implements ChildrenRepository {
  @override
  Future<List<UserModel>> getChildren() async => const [];
  @override
  Future<UserModel> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
    InterestsModel? interests,
  }) async =>
      throw UnimplementedError();
  @override
  Future<UserModel> updateChild({
    required String childId,
    String? displayName,
    int? grade,
    InterestsModel? interests,
  }) async =>
      throw UnimplementedError();
}

/// 直接种一个已加载状态，避开网络层。
class _SeededChildrenNotifier extends ChildrenNotifier {
  _SeededChildrenNotifier(List<UserModel> children)
      : super(_UnusedChildrenRepo()) {
    state = ChildrenLoaded(children);
  }
}

void main() {
  final children = [
    UserModel(
        id: 'c1', username: 'xiaoming', displayName: '小明', role: 'child', grade: 2),
    UserModel(
        id: 'c2', username: 'xiaohong', displayName: '小红', role: 'child', grade: 4),
  ];

  Future<StorageService> makeStorage() async {
    SharedPreferences.setMockInitialValues({});
    final s = StorageService();
    await s.init();
    return s;
  }

  Future<void> pumpShell(
    WidgetTester tester,
    StorageService storage, {
    Size size = const Size(1280, 800),
  }) async {
    // 必须显式设视口：test surface 默认 800×600，`SizedBox(width: 1280)` 会被
    // 静默裁到 800 —— 断点分支就会测错档（ADR-0045 记录过的坑）。
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          childrenNotifierProvider
              .overrideWith((ref) => _SeededChildrenNotifier(children)),
        ],
        child: ShadApp.custom(
          // ⚠️ 必须传真实主题：`ShadApp.custom` 不传 `theme:` 会走 shadcn 默认主题
          // （默认浮层内边距是 `h12/v6`、按钮竖向内边距 8），量出来的浮层宽度与
          // 控件高度都跟产品不一致。断言几何的测试**必须**传真主题。
          theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
          appBuilder: (context) => MaterialApp(
            home: Scaffold(
              body: AdaptiveShell(
                mode: AppUserMode.parent,
                destinations: const [
                  AdaptiveNavDestination(
                      icon: LucideIcons.house, label: '首页', active: true),
                ],
                sidebarTop: ParentChildSelector(
                  onNavigateToAddChild: () {},
                  onNavigateToEditChild: (_) {},
                ),
                body: const Placeholder(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 侧栏导航项药丸的左缘。`AppSidebarItem` = Padding(h: sm) → 药丸，
  /// 故药丸左缘即 `AppSidebar` 左缘 + [AppSpacing.sm]。
  Finder navPill() => find
      .descendant(
          of: find.byType(AppSidebarItem), matching: find.byType(Container))
      .first;

  testWidgets('展开态：头部选择器左缘与导航项药丸左缘对齐', (tester) async {
    final storage = await makeStorage();
    await pumpShell(tester, storage);

    final selectorLeft = tester.getTopLeft(find.byType(ParentChildSelector)).dx;
    final pillLeft = tester.getTopLeft(navPill()).dx;
    final sidebarLeft = tester.getTopLeft(find.byType(AppSidebar)).dx;

    expect(selectorLeft, sidebarLeft + AppSpacing.sm,
        reason: '头部左缘必须等于导航项左缘（8px），否则一个侧栏里出现两条左边缘');
    expect(selectorLeft, pillLeft);
  });

  testWidgets('展开态：选择器与收缩按钮同高，基线齐平', (tester) async {
    final storage = await makeStorage();
    await pumpShell(tester, storage);

    final selector = tester.getSize(find.byType(ParentChildSelector));
    final toggle = tester.getSize(find.ancestor(
            of: find.byIcon(LucideIcons.panelLeftClose),
            matching: find.byType(AppFocusableAction))
        .first);

    expect(selector.height, AppLayout.tapTarget,
        reason: '选择器高度应钉到 tapTarget');
    expect(toggle.height, AppLayout.tapTarget,
        reason: '收缩按钮高度应钉到 tapTarget');
    expect(selector.height, toggle.height, reason: '同行的两个控件必须同高');
  });

  testWidgets('展开态：选择器顶部与左侧都有留白（不再贴边）', (tester) async {
    final storage = await makeStorage();
    await pumpShell(tester, storage);

    final sidebar = tester.getTopLeft(find.byType(AppSidebar));
    final selector = tester.getTopLeft(find.byType(ParentChildSelector));

    expect(selector.dx - sidebar.dx, AppSpacing.sm);
    expect(selector.dy - sidebar.dy, AppSpacing.md,
        reason: '头部顶部留白，贴边会让卡片与侧栏上边缘黏在一起');
  });

  /// 触发卡的可见外框（含 1px 发丝描边）：选择器子树里第一个带描边的 `Container`。
  ///
  /// `ShadCard` 内部就是一个 `Container(decoration: BoxDecoration(border: ...))`，
  /// 不是 `ShadDecorator`（探针实测：搜 `ShadDecorator` 找不到元素）。
  Finder triggerCard() => find
      .descendant(
        of: find.byType(ParentChildSelector),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).border != null,
        ),
      )
      .first;

  testWidgets('展开态：触发卡内容与容器上下居中（钉高后不得贴顶）', (tester) async {
    final storage = await makeStorage();
    await pumpShell(tester, storage);

    // 卡片被 `SizedBox(height: tapTarget)` 钉到 44，内容只有 28（头像高度）。
    // 而 `ShadCard` 内部是 `Row(crossAxisAlignment: start)` + `Column(min)`，
    // 内容**不会**因容器被拉高而居中 —— 修前实测：卡片 12–56、头像 13–41，
    // 上边距 1、下边距 15，内容中心比卡片中心高 7px。修法是在卡片内容外补 `Center`。
    final card = tester.getRect(triggerCard());
    final avatar = tester.getRect(find.byType(AvatarSquircle).first);

    expect(card.height, AppLayout.tapTarget, reason: '卡片仍须钉到 tapTarget');
    expect((avatar.top + avatar.bottom) / 2, closeTo((card.top + card.bottom) / 2, 1),
        reason: '内容中心必须等于容器中心；容差 1px 留给 1px 发丝描边与亚像素舍入。'
            '贴顶（而非居中）说明卡片内容外面漏了 `Center`');
    expect(avatar.top - card.top, closeTo(card.bottom - avatar.bottom, 1),
        reason: '上下留白必须对称');
  });

  testWidgets('轨态：选择器降级为头像，不溢出、不丢失（带 Expanded 的行会撑爆 48px）',
      (tester) async {
    final storage = await makeStorage();
    await pumpShell(tester, storage);

    await tester.tap(find.byIcon(LucideIcons.panelLeftClose));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: '轨态宽度只有 48px，展开态那行（头像+姓名+箭头）会 RenderFlex overflowed');
    expect(find.byType(ParentChildSelector), findsOneWidget,
        reason: '轨态不能把「当前在看谁」直接丢掉');
    expect(find.byIcon(LucideIcons.chevronsUpDown), findsNothing,
        reason: '轨态不该渲染展开态的下拉箭头');
    expect(find.byType(AvatarSquircle), findsWidgets,
        reason: '轨态应保留娃娃头像');
    // 收起按钮仍在，且能再展开。
    expect(find.byIcon(LucideIcons.panelLeftOpen), findsOneWidget);
  });

  testWidgets('浮层：「添加娃娃」是主按钮，选项不再套一层带描边卡片', (tester) async {
    final storage = await makeStorage();
    await pumpShell(tester, storage);

    await tester.tap(find.byType(ParentChildSelector));
    await tester.pumpAndSettle();

    expect(find.byType(AppPrimaryButton), findsOneWidget,
        reason: '「添加娃娃」是动作，必须与娃娃选项区分开（原先同形 → 读成第三个娃娃）');
    expect(find.byType(AppCard), findsOneWidget,
        reason: '浮层里只有触发器那一个 AppCard；选项若也用 AppCard 就是盒中盒');
    // 两个娃娃选项各有一个可点药丸 + 编辑按钮。
    expect(find.text('小明'), findsWidgets);
    expect(find.text('小红'), findsWidgets);
    expect(find.bySemanticsLabel('编辑娃娃资料'), findsNWidgets(2),
        reason: '行内编辑按钮必须进焦点树（原先裸 GestureDetector，键盘 Tab 不到）');
  });

  /// 浮层的可见外框（含主题内边距与 2px 描边）。
  ///
  /// `AppPrimaryButton` 只在浮层里出现，从它往上找**最近的** `ShadDecorator`
  /// 就是浮层本体；`ShadDecorator` 的尺寸已含 decoration 的描边与内边距。
  Finder popoverBox() => find
      .ancestor(
        of: find.byType(AppPrimaryButton),
        matching: find.byType(ShadDecorator),
      )
      .first;

  testWidgets('浮层：外框与触发卡左缘齐平、宽度钉到令牌、不溢出侧栏', (tester) async {
    final storage = await makeStorage();
    await pumpShell(tester, storage);

    await tester.tap(find.byType(ParentChildSelector));
    await tester.pumpAndSettle();

    final box = tester.getRect(popoverBox());
    final trigger = tester.getRect(find.byType(ParentChildSelector));
    final sidebar = tester.getRect(find.byType(AppSidebar));

    // 原先 shadcn 默认 anchor 是「相对触发卡水平居中」，而触发卡（171）比浮层（224）
    // 窄 → 浮层两侧各溢出约 26px，左溢部分还被屏幕左缘钳住：实测外框左缘落在窗口
    // x=0、右缘 244，比侧栏（240）还宽 5px，就是「浮层选项超出侧边栏」。
    expect(box.left, trigger.left,
        reason: '浮层必须与触发卡左缘齐平（= 侧栏唯一的那条左边缘）');
    expect(box.width, AppLayout.sidebarMenuWidth,
        reason: '浮层外框宽必须等于令牌；宽度写错通常是因为漏了 popoverChrome 的'
            '主题内边距 + 描边（内容侧会短 20）');
    expect(box.right, lessThanOrEqualTo(sidebar.right),
        reason: '浮层不得超出侧栏右缘');
    expect(box.left, greaterThanOrEqualTo(0),
        reason: '浮层不得被挤出窗口左缘');
  });

  testWidgets('浮层：面板内部只有一条左边缘（选项与 CTA 同缩进）', (tester) async {
    final storage = await makeStorage();
    await pumpShell(tester, storage);

    await tester.tap(find.byType(ParentChildSelector));
    await tester.pumpAndSettle();

    // 选项药丸 = 选项那个 AppFocusableAction（语义标签是娃娃名）里的 Container。
    final option = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is AppFocusableAction && w.semanticLabel == '小明',
      ),
      matching: find.byType(Container),
    );

    expect(tester.getRect(option.first).left,
        tester.getRect(find.byType(AppPrimaryButton)).left,
        reason: 'CTA 与选项同为面板里的「项」，左缘必须同一条；'
            '原先选项缩进 4、CTA 缩进 8、分隔线缩进 12，面板里出现三条左边缘');
  });

  testWidgets('浮层：CTA 高度走标准档令牌（不得被父级约束压扁）', (tester) async {
    final storage = await makeStorage();
    await pumpShell(tester, storage);

    await tester.tap(find.byType(ParentChildSelector));
    await tester.pumpAndSettle();

    final btn = find.byType(AppPrimaryButton);
    final ctx = tester.element(btn);
    // `ShadButton` 内部是 `ConstrainedBox(minHeight == maxHeight == 内容盒高)`：
    // 一旦父级给的 maxHeight 更小，按钮会被**静默压扁**（可见高低于令牌）而不是报错。
    expect(tester.getSize(btn).height, AppControl.heightOf(ctx),
        reason: '浮层里的 CTA 必须与全局标准档同高；被压扁说明外层约束把高度算紧了');
  });

  testWidgets('轨态：浮层向轨右侧飞出、不盖住轨道', (tester) async {
    final storage = await makeStorage();
    await pumpShell(tester, storage);

    await tester.tap(find.byIcon(LucideIcons.panelLeftClose));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(ParentChildSelector));
    await tester.pumpAndSettle();

    final box = tester.getRect(popoverBox());
    final trigger = tester.getRect(find.byType(ParentChildSelector));
    final icon = tester.getRect(find.byIcon(LucideIcons.house));

    // 轨态必然容不下 224 宽的浮层——这是飞出的菜单，允许盖住内容区。
    // 但**不允许**盖住轨道的导航图标：轨态存在的意义就是「收起后信息不能丢」
    // （ADR-0046），浮层压住图标就把这个意义抵消了。
    // 所以浮层从触发头像的右缘飞出、顶端与头像齐平。
    expect(box.left, trigger.right,
        reason: '轨态浮层从触发头像右缘飞出');
    expect(box.top, trigger.top, reason: '轨态浮层与触发头像顶端齐平');
    expect(box.left, greaterThan(icon.right),
        reason: '浮层不得压住导航图标（轨道本体的最后一小条被浮层边缘掠过不影响可读性）');
    expect(box.right, lessThanOrEqualTo(820), reason: '浮层不得溢出窗口右缘');
  });
}
