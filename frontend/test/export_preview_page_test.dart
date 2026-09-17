import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:kids_learn/features/export/domain/export_repository.dart';
import 'package:kids_learn/features/export/presentation/export_preview_page.dart';
import 'package:kids_learn/features/export/providers/export_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _FailingExportRepository implements ExportRepository {
  @override
  Future<Uint8List> exportSheet(ExportSheetRequest request) async {
    throw Exception('无法连接服务器');
  }
}

/// 字节能拿到，但渲染引擎打不开——复现线上那个崩溃的替身。
class _BytesOnlyExportRepository implements ExportRepository {
  @override
  Future<Uint8List> exportSheet(ExportSheetRequest request) async =>
      Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46, 0x0A]);
}

/// pdfx 在「原生侧没有这个插件」时抛的就是这句话。见 resources 里的
/// `PdfxApi.openDocumentData`：通道没人接 → 返回 null → channel-error。
PdfDocumentOpener _deadChannelOpener() => (_) async => throw PlatformException(
      code: 'channel-error',
      message: 'Unable to establish connection on channel.',
    );

/// 不是通道问题、纯粹打不开这份文档。
PdfDocumentOpener _brokenDocumentOpener() =>
    (_) async => throw Exception('文档已损坏');

ExportSheetRequest _request() =>
    ExportSheetRequest(source: 'bank', ids: const ['q1']);

/// 断言几何/版式必须套真实主题的 ShadApp：不传 theme 会落到 shadcn 默认主题，
/// 量出来的尺寸、按钮 padding 都与产品不符（见 test/adaptive_shell_layout_test.dart）。
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ExportRepository repository = const _Default(),
  PdfDocumentOpener? opener,
}) async {
  // 必须显式设视口：test surface 默认 800×600，宽屏断点会被静默裁到中屏档。
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        exportRepositoryProvider.overrideWithValue(repository),
        if (opener != null) pdfDocumentOpenerProvider.overrideWithValue(opener),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
        appBuilder: (context) => MaterialApp(home: child),
      ),
    ),
  );
  // initState 用 addPostFrameCallback 起导出，跨帧才拿得到结果。
  // 三次而不是两次：第二段 await（把字节交给渲染引擎）自己还要跨一次帧——
  // 少一次就停在加载态，测到的会是「还在转圈」而不是我们要的失败态。
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// 默认替身：后续用例逐个显式换成会失败的那一版，避免「默认就成功」掩盖分支。
class _Default implements ExportRepository {
  const _Default();

  @override
  Future<Uint8List> exportSheet(ExportSheetRequest request) async {
    throw Exception('未覆写：本用例应当显式传入 repository');
  }
}

/// 收尾：把被测页面换成空树并 pump 一秒。
///
/// AppLoading 的转圈是 flutter_animate 的循环动画，会挂一个周期性 Timer；不在这
/// 里把它跑掉，测试结束时的不变式检查会以「Timer is still pending」失败。这与
/// 预览页无关，是测试替身时间模型的要求（放 addTearDown 无效，必须写在用例体内）。
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// 取带指定文字的 ShadButton 本体（`enabled` 字段恒为 true，真正表达禁用的是
/// `onPressed == null`，所以断言要看后者）。
ShadButton _button(WidgetTester tester, String label) => tester.widget<ShadButton>(
      find.widgetWithText(ShadButton, label).first,
    );

/// 把预览页放进**真实路由栈**里（而不是直接当 home）——返回是 `Navigator.maybePop`，
/// 栈里没有可 pop 的路由时它什么都不做：只断言「顶栏有个返回图标」测不出「点了回得去」。
Future<void> _pumpPushed(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        exportRepositoryProvider.overrideWithValue(_FailingExportRepository()),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
        appBuilder: (_) => MaterialApp(
          navigatorKey: navigatorKey,
          home: const Text('来源页'),
        ),
      ),
    ),
  );
  navigatorKey.currentState!.push<void>(
    // 用 MaterialPageRoute 只是为了避免 material/cupertino 的符号冲突；
    // 被测的是「返回键能把这一页 pop 掉」，与转场动画是哪一种无关。
    MaterialPageRoute<void>(
      builder: (_) => ExportPreviewPage(request: _request(), title: '题库练习'),
    ),
  );
  // 转场要跑完再断言：转场期间新旧两页同时在树上，此时「来源页不可见」是不成立的。
  // 这里能安全 settle，是因为替身立刻失败、页面停在 AppError（没有循环动画）。
  await tester.pumpAndSettle();
}

void main() {
  group('ExportPreviewPage（push 整页，ADR-0045）', () {
    testWidgets('后端不可达时显示可重试错误，而不是白屏或假预览', (tester) async {
      await _pump(
        tester,
        repository: _FailingExportRepository(),
        ExportPreviewPage(request: _request(), title: '题库练习'),
      );
      expect(find.textContaining('导出失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      // 关键：错误态下不能同时给出可点的「打印 / 分享」——没有字节可投递，
      // 给一个按下去什么也不会发生的按钮等于承诺一个不可能发生的动作。
      expect(_button(tester, '打印').onPressed, isNull);
      expect(_button(tester, '分享').onPressed, isNull);
      await _drain(tester);
    });

    testWidgets('整页自带 contentWide 宽度约束且内容贴顶（不浮屏幕中间）',
        (tester) async {
      await _pump(
        tester,
        repository: _FailingExportRepository(),
        ExportPreviewPage(request: _request(), title: '题库练习'),
      );

      // 在页面自己的子树里找：**不能**从 ExportPreviewPage 的 element 往上找——
      // Align / ConstrainedBox 是它 build 出来的孩子，不是祖先。
      final align = tester.widget<Align>(
        find
            .descendant(
              of: find.byType(ExportPreviewPage),
              matching: find.byType(Align),
            )
            .first,
      );
      // ADR-0045：push 的整页不在壳的兜底范围内，必须 Align(topCenter) + 宽度上限；
      // 用 Center 会竖向也居中，不足一屏时页面浮到屏幕中间。
      expect(align.alignment, Alignment.topCenter);
      final box = tester.widget<ConstrainedBox>(
        find
            .descendant(
              of: find.byType(ExportPreviewPage),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(box.constraints.maxWidth, AppLayout.contentWide);
      await _drain(tester);
    });

    testWidgets('含降级题时如实提示「已按纯文本打印」', (tester) async {
      await _pump(
        tester,
        repository: _FailingExportRepository(),
        ExportPreviewPage(
          request: _request(),
          title: '题库练习',
          downgradedCount: 3,
        ),
      );
      expect(find.textContaining('3 道题含公式或图片'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('字节到手但渲染引擎不可用 → 可重试失败态，而不是未处理异常',
        (tester) async {
      // 这个用例天然复现线上那个崩溃：widget 测试里没有原生 PdfxPlugin，
      // PdfDocument.openData 抛的正是 PlatformException(channel-error)。
      // 页面必须把它接住；接不住的话测试会因 unhandled exception 直接失败。
      await _pump(
        tester,
        repository: _BytesOnlyExportRepository(),
        opener: _deadChannelOpener(),
        ExportPreviewPage(request: _request(), title: '题库练习'),
      );
      // 关键：这句不能是 `预览失败：PlatformException(...)`。用户看到错误类型
      // 也做不了任何事——真正缺的是「下一步做什么」，所以文案必须落到
      // 「完全退出后重新打开 / 重新构建」上。
      expect(
        find.textContaining('预览引擎没有随这次启动加载进来'),
        findsOneWidget,
      );
      expect(find.text('重试'), findsOneWidget);
      // 失败的时候字节照样在内存里，但这不等于可以投递。
      expect(_button(tester, '打印').onPressed, isNull);
      expect(_button(tester, '分享').onPressed, isNull);
      await _drain(tester);
    });

    testWidgets('非通道原因的渲染失败仍走通用文案', (tester) async {
      await _pump(
        tester,
        repository: _BytesOnlyExportRepository(),
        opener: _brokenDocumentOpener(),
        ExportPreviewPage(request: _request(), title: '题库练习'),
      );
      expect(find.textContaining('预览失败'), findsOneWidget);
      expect(find.textContaining('预览引擎没有随这次启动'), findsNothing);
      await _drain(tester);
    });

    testWidgets('顶栏有返回入口，点了回得去上一页（不会被锁在这一屏）', (tester) async {
      await _pumpPushed(tester);
      // 已经在预览页上，来源页不可见。
      expect(find.text('来源页'), findsNothing);
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();
      expect(find.text('来源页'), findsOneWidget);
    });

    testWidgets('无降级题时不显示降级提示', (tester) async {
      await _pump(
        tester,
        repository: _FailingExportRepository(),
        ExportPreviewPage(request: _request(), title: '题库练习'),
      );
      expect(find.textContaining('已按纯文本打印'), findsNothing);
      await _drain(tester);
    });
  });
}
