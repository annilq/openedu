// 图形画板（ADR-0083 T04）：工具栏预设 + 编辑态画布 + 保存。
//
// 守四件事：
// 1. 工具栏预设点击即落画板（顶点 = 预设顶点，edges 按序闭合）；
// 2. 编辑态可拖顶点（几何随拖动改变，且改动会进入保存载荷）；
// 3. 编辑态可移对称轴（拖空白处 → 轴水平位置变化，滑块跟随）；
// 4. 保存内容正确：label + 完整 points + edges，**无任何 axis 属性**；返回 key 有反馈；
//    且编辑态**不报「是不是轴对称」的结论**（ADR-0083 决策 2：判定交给眼睛）。
//
// 挂载纪律：根是 ShadApp + CupertinoApp（不套 Material）；必须显式包 ShadToaster
// （保存成功会弹 toast，否则 AppToast.show 抛错）。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/domain/repositories/material_repository.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/scene_library_view.dart';
import 'package:kids_learn/features/home/providers/home_provider.dart';
import 'package:kids_learn/features/home/providers/knowledge_manage_provider.dart';
import 'package:kids_learn/shared/domain/figures.dart';
import 'package:kids_learn/shared/domain/providers/figure_library_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_actions.dart';
import 'package:kids_learn/shared/widgets/app_buttons.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene_board.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene_data.dart';

/// 挂一棵与生产同构的应用树（根 = ShadApp.custom + CupertinoApp），`home` 由调用方给。
///
/// **关键**：[ShadToaster] 必须装在 Navigator **之上**。`ReflectionSceneBoardDialog`
/// 走的 `showShadDialog` 默认 `useRootNavigator: true`——弹窗内容渲染在**根
/// Navigator** 的 Overlay 里。若 toaster 只包在 `home` 深处（Navigator 之下），
/// 弹窗内的 `AppToast.show` 就找不到它（抛「Could not find ShadToaster」），
/// 于是「保存成功 → onBack 关弹窗」永远走不到。
/// 生产里这件事由 `ShadAppBuilder` 承担（把 toaster 兜在 Navigator 之上），
/// 这里用 `CupertinoApp.builder` 复刻同一层级，保证测试与线上同构。
Future<void> _pumpApp(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(900, 2200),
  List<Override> overrides = const <Override>[],
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          builder: (context, child) =>
              ShadToaster(child: child ?? const SizedBox.shrink()),
          home: home,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpBoard(
  WidgetTester tester, {
  required FigureBoardSave onSave,
}) =>
    _pumpApp(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: ReflectionSceneBoard(onSave: onSave),
      ),
    );

/// 画廊里点开某个图形（按中文名定位卡片）。
Finder _galleryCard(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(AppFocusableAction));

/// 编辑态画布（`ReflectionSceneWidget` 内第一个 CustomPaint = 正方形画布）。
Rect _canvasRect(WidgetTester tester) => tester.getRect(
      find
          .descendant(
            of: find.byType(ReflectionSceneWidget),
            matching: find.byType(CustomPaint),
          )
          .first,
    );

ReflectionSceneData _sceneData(WidgetTester tester) => tester
    .widget<ReflectionSceneWidget>(find.byType(ReflectionSceneWidget))
    .data;

FigureBoardSave _noop() => (label, points, edges) async => 'user_test';

/// 只实现被调用方法的桩（其余走 noSuchMethod）。
class _StubRepo implements MaterialRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('工具栏预设点击即落画板（顶点 = 预设顶点，边按序闭合）', (tester) async {
    await _pumpBoard(tester, onSave: _noop());
    // 空画板：不渲染画布，给「下一步做什么」的空态。
    expect(find.byType(ReflectionSceneWidget), findsNothing);
    expect(find.text('画板是空的'), findsOneWidget);

    final square = figureByKey('square');
    await tester.tap(_galleryCard(square.label));
    await tester.pumpAndSettle();

    final data = _sceneData(tester);
    expect(data.points.length, square.vertices.length);
    expect(
      data.points.first,
      Offset(square.vertices.first.x, square.vertices.first.y),
    );
    expect(data.edges, closedEdges(square.vertices.length));
  });

  testWidgets('编辑态：拖某个顶点会改几何', (tester) async {
    await _pumpBoard(tester, onSave: _noop());
    final square = figureByKey('square');
    await tester.tap(_galleryCard(square.label));
    await tester.pumpAndSettle();

    final rect = _canvasRect(tester);
    // square 顶点 0 = (0.28, 0.28)，把它横向拖 40px。
    final v0 = rect.topLeft + Offset(0.28 * rect.width, 0.28 * rect.height);
    final before = _sceneData(tester).points.first;

    final gesture = await tester.startGesture(v0);
    await tester.pump();
    // 纯横向拖：避免被外层竖向滚动抢走手势。
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final after = _sceneData(tester).points.first;
    expect(after, isNot(before), reason: '拖顶点必须改变几何');
    expect(after.dx, greaterThan(before.dx));
  });

  testWidgets('编辑态：拖空白处移动对称轴，轴滑块跟随', (tester) async {
    await _pumpBoard(tester, onSave: _noop());
    // 房子顶点都远离画布中心 → 从中心拖一定是「移轴」而非抓顶点。
    await tester.tap(_galleryCard(figureByKey('house').label));
    await tester.pumpAndSettle();

    // 初始轴水平 / 垂直都是 0.50。
    expect(find.text('0.50'), findsNWidgets(2));

    final rect = _canvasRect(tester);
    final gesture = await tester.startGesture(rect.center);
    await tester.pump();
    await gesture.moveBy(Offset(0.08 * rect.width, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 轴水平 0.50 → 0.58，垂直不动。
    expect(find.text('0.58'), findsOneWidget);
    expect(find.text('0.50'), findsOneWidget);
  });

  testWidgets('保存：label + 完整 points + edges（无 axis 属性），返回 key 有反馈', (tester) async {
    String? gotLabel;
    List<List<double>>? gotPoints;
    List<List<int>>? gotEdges;
    await _pumpBoard(
      tester,
      onSave: (label, points, edges) async {
        gotLabel = label;
        gotPoints = points;
        gotEdges = edges;
        return 'user_abc123';
      },
    );

    final square = figureByKey('square');
    await tester.tap(_galleryCard(square.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存到图库'));
    await tester.pumpAndSettle();

    // 名称：预设名预填（作者没改就沿用）。
    expect(gotLabel, square.label);
    // 顶点：逐点等于预设几何（自定义图形时为作者拖出来的顶点）。
    expect(gotPoints, isNotNull);
    expect(gotPoints!.length, square.vertices.length);
    for (var i = 0; i < square.vertices.length; i++) {
      expect(gotPoints![i], [square.vertices[i].x, square.vertices[i].y]);
    }
    // 边：按顶点顺序闭合；载荷里**没有任何 axis 字段**（对称判定纯视觉）。
    expect(gotEdges, closedEdges(square.vertices.length));
    // 后端分配的 key 反馈给用户。
    expect(find.textContaining('user_abc123'), findsOneWidget);
  });

  testWidgets('拖过顶点后保存，载荷携带改后的几何', (tester) async {
    List<List<double>>? gotPoints;
    await _pumpBoard(
      tester,
      onSave: (label, points, edges) async {
        gotPoints = points;
        return 'user_x';
      },
    );
    final square = figureByKey('square');
    await tester.tap(_galleryCard(square.label));
    await tester.pumpAndSettle();

    final rect = _canvasRect(tester);
    final v0 = rect.topLeft + Offset(0.28 * rect.width, 0.28 * rect.height);
    final gesture = await tester.startGesture(v0);
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存到图库'));
    await tester.pumpAndSettle();

    expect(gotPoints, isNotNull);
    expect(
      gotPoints![0][0],
      greaterThan(square.vertices.first.x),
      reason: '保存的几何必须是拖过之后的，不是预设原值',
    );
  });

  testWidgets('空画板：保存按钮禁用、不渲染画布', (tester) async {
    await _pumpBoard(tester, onSave: _noop());
    expect(find.byType(ReflectionSceneWidget), findsNothing);
    final button = tester.widget<AppPrimaryButton>(find.byType(AppPrimaryButton));
    expect(button.onPressed, isNull, reason: '没放图形时保存应禁用');
  });

  testWidgets('编辑态不报「是不是轴对称」的结论（决策 2）', (tester) async {
    await _pumpBoard(tester, onSave: _noop());
    await tester.tap(_galleryCard(figureByKey('square').label));
    await tester.pumpAndSettle();

    // 播完对折（1.4s）到 180°：非编辑态这时会报「是轴对称图形」，编辑态不该。
    await tester.tap(find.byType(AppIconAction));
    await tester.pumpAndSettle();

    expect(find.textContaining('对折到 180°'), findsOneWidget);
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>();
    expect(
      texts.any((t) => t.contains('是轴对称图形') || t.contains('不是对称轴')),
      isFalse,
      reason: '画板只演示，不给判定结论（ADR-0083 决策 2）',
    );
  });

  testWidgets('弹窗形态：打开画板，保存走注入回调并在成功后关闭', (tester) async {
    String? savedLabel;
    await _pumpApp(
      tester,
      Builder(
        builder: (ctx) => Center(
          child: AppPrimaryButton(
            label: '打开画板',
            onPressed: () => ReflectionSceneBoardDialog.show(
              ctx,
              onSave: (label, points, edges) async {
                savedLabel = label;
                return 'user_z';
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开画板'));
    await tester.pumpAndSettle();
    expect(find.byType(ReflectionSceneBoard), findsOneWidget);

    final square = figureByKey('square');
    await tester.tap(_galleryCard(square.label));
    await tester.pumpAndSettle();
    final saveBtn = find.text('保存到图库');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(savedLabel, square.label);
    // 保存成功后经 onBack 关闭弹窗。
    expect(find.byType(ReflectionSceneBoard), findsNothing);
  });

  testWidgets('场景库页「图形画板」入口可打开画板', (tester) async {
    await _pumpApp(
      tester,
      TeacherSceneLibraryView(onOpenScene: (_) {}),
      size: const Size(900, 1600),
      overrides: [
        materialRepositoryProvider.overrideWithValue(_StubRepo()),
        // 打开画板前会按需拉图库（ADR-0083 T05）；测试用整库夹具顶掉取数。
        figureLibraryProvider.overrideWith((ref) async => kFigureShapes),
        sceneLibraryProvider.overrideWith(
          (ref) async => SceneLibrary.fromJson(const <String, dynamic>{
            'scenes': <dynamic>[],
          }),
        ),
      ],
    );

    expect(find.text('图形画板'), findsOneWidget);
    await tester.tap(find.text('图形画板'));
    await tester.pumpAndSettle();
    expect(find.byType(ReflectionSceneBoard), findsOneWidget);
  });
}
