// 溯源视图（ADR-0093）：命中集渲染、零命中诚实兜底、高亮、空白折叠。
// 同 assistant_sources_bar_test 的纪律：App 根没有 Material 祖先，这里刻意
// 不套 Material，构建期抛异常就是失败。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/widgets/teacher/knowledge_point_source_view.dart';
import 'package:kids_learn/shared/features/materials/domain/repositories/material_repository.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

KnowledgePointSourceMaterial _src({
  required String name,
  required List<KnowledgePointSourceChunk> chunks,
  int totalChunks = 0,
  bool matched = true,
}) =>
    KnowledgePointSourceMaterial(
      materialId: 'm1',
      materialName: name,
      chunks: chunks,
      totalChunks: totalChunks,
      matched: matched,
    );

Future<void> _pump(WidgetTester tester, List<KnowledgePointSourceMaterial> sources,
    {String kpName = '加法交换律'}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: KnowledgePointSourceView(
                    kpName: kpName,
                    sources: sources,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('命中时显示「命中 N / 共 M 段」且只铺命中的段', (tester) async {
    await _pump(
      tester,
      [
        _src(
          name: '四下.pdf',
          totalChunks: 12,
          matched: true,
          chunks: const [
            KnowledgePointSourceChunk(seq: 7, content: '例：用加法交换律验算'),
            KnowledgePointSourceChunk(seq: 3, content: '加法交换律：和不变'),
          ],
        )
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('命中 2 / 共 12 段'), findsOneWidget);
    expect(find.text('例：用加法交换律验算'), findsOneWidget);
    // 兜底文案不出现在命中场景
    expect(find.textContaining('没有出现'), findsNothing);
    expect(find.text('展开其余'), findsNothing);
  });

  testWidgets('零命中兜底全本：照实说明 + 首屏 10 段 + 可展开', (tester) async {
    final chunks = [
      for (var i = 0; i < 12; i++)
        KnowledgePointSourceChunk(seq: i, content: '第$i段正文'),
    ];
    await _pump(
      tester,
      [_src(name: '一上.pdf', totalChunks: 12, matched: false, chunks: chunks)],
      kpName: '5以内的加法',
    );

    expect(find.text('全文 12 段'), findsOneWidget);
    expect(find.textContaining('没有出现「5以内的加法」的原词'), findsOneWidget);
    expect(find.text('第9段正文'), findsOneWidget);
    expect(find.text('第10段正文'), findsNothing);
    expect(find.text('展开其余 2 段'), findsOneWidget);

    await tester.tap(find.text('展开其余 2 段'));
    await tester.pumpAndSettle();
    expect(find.text('第11段正文'), findsOneWidget);
  });

  testWidgets('片段渲染前折叠空白，并高亮知识点名（全角孪生容差）', (tester) async {
    await _pump(
      tester,
      [
        _src(
          name: '一上.pdf',
          totalChunks: 2,
          chunks: const [
            KnowledgePointSourceChunk(
              seq: 0,
              content: '本段出现\n  1～5的认识\t标题（全角波浪号）',
            ),
          ],
        )
      ],
      kpName: '1~5的认识',
    );

    // 换行/制表符折叠成单空格，原文形态找不到
    expect(find.text('本段出现 1～5的认识 标题（全角波浪号）'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 高亮段吃下全角差异：名字是半角 ~，正文是全角 ～
    expect(_highlightedTexts(tester), contains('1～5的认识'));
  });

  testWidgets('高亮容许 PDF 断行把术语劈成两半', (tester) async {
    await _pump(
      tester,
      [
        _src(
          name: '四下.pdf',
          totalChunks: 1,
          chunks: const [
            KnowledgePointSourceChunk(seq: 0, content: '例：用加法\n交换律验算'),
          ],
        )
      ],
      kpName: '加法交换律',
    );

    expect(find.text('例：用加法 交换律验算'), findsOneWidget);
    expect(_highlightedTexts(tester), contains('加法 交换律'));
  });

  testWidgets('没有来源资料时走空态文案', (tester) async {
    await _pump(tester, const [], kpName: '亿级');
    expect(find.textContaining('没有资料引用「亿级」'), findsOneWidget);
  });

  test('模型解析：缺省 totalChunks/matched 的旧载荷不炸', () {
    final m = KnowledgePointSourceMaterial.fromJson(const {
      'material_id': 'm1',
      'material_name': 'x',
      'chunks': [
        {'seq': 0, 'content': 'c'}
      ],
    });
    expect(m.totalChunks, 0);
    expect(m.matched, isTrue);
    expect(m.chunks.single.seq, 0);

    final full = KnowledgePointSourceMaterial.fromJson(const {
      'material_id': 'm1',
      'material_name': 'x',
      'chunks': [
        {'seq': 0, 'content': 'c'}
      ],
      'total_chunks': 9,
      'matched': false,
    });
    expect(full.totalChunks, 9);
    expect(full.matched, isFalse);
  });
}

List<InlineSpan> _collect(InlineSpan span) => [
      span,
      if (span is TextSpan) ...?span.children?.expand(_collect),
    ];

/// 所有被高亮（w600）的片段文本——按名字匹配上的那几截。
List<String?> _highlightedTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .where((w) => w.textSpan != null)
    .expand((w) => _collect(w.textSpan!))
    .whereType<TextSpan>()
    .where((s) => s.style?.fontWeight == FontWeight.w600)
    .map((s) => s.text)
    .toList();
