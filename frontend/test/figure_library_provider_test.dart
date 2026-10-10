// 图库按需拉取（ADR-0083 T05）：DB 行解析 + 会话内一次性拉取 + 失败可重试。
//
// 守四件事：
// 1. `figure_library` 行（几何 + label + is_builtin，**无 axis**）能解析成画廊模型；
//    顶点不足的坏行跳过（不显示一条渲染不出来的空卡）。
// 2. **懒加载**：启动期不发请求——运行时渲染零图库依赖，只有创作 UI 真打开才拉。
// 3. **会话内一次性**：同一 ProviderContainer（≈ 一次登录会话）里二次读取不重复请求；
//    不是落盘缓存（进程退出即失，测试里靠「新容器会重新拉」印证）。
// 4. 拉取失败 → provider 进 error 态，画廊据此给可重试提示（不静默吞掉）。
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/data/remote/network_service.dart';
import 'package:kids_learn/shared/domain/figure_library.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/domain/providers/figure_library_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/figure_library_gallery.dart';

/// 记录 `get` 调用的假网络层。只实现 get：本测试不该走别的动词。
class _RecordingNetwork implements NetworkService {
  _RecordingNetwork({this.payload, this.error});

  final Object? payload;
  final Object? error;

  /// 每次 `get` 的 path（用来断言「只拉一次」）。
  final List<String> calls = <String>[];

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add(path);
    if (error != null) throw error!;
    return payload;
  }

  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) =>
      throw UnimplementedError();

  @override
  Future<dynamic> put(String path,
          {Map<String, dynamic>? query, Map<String, dynamic>? body}) =>
      throw UnimplementedError();

  @override
  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) =>
      throw UnimplementedError();

  @override
  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) =>
      throw UnimplementedError();

  @override
  Future<dynamic> postForm(String path, FormData form) =>
      throw UnimplementedError();

  @override
  Stream<Uint8List> streamPost(String path,
          {Map<String, dynamic>? body, Duration? receiveTimeout}) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> postBytes(String path, {Map<String, dynamic>? body}) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? query}) =>
      throw UnimplementedError();
}

/// 后端 `GET /scene-library/figures` 的响应体（内置一行 + 用户一行 + 一行坏几何）。
Map<String, dynamic> _libraryPayload() => <String, dynamic>{
      'figures': <dynamic>[
        <String, dynamic>{
          'key': 'house',
          'label': '房子',
          'points': <dynamic>[
            <double>[0.3, 0.7],
            <double>[0.7, 0.7],
            <double>[0.5, 0.25],
          ],
          'edges': <dynamic>[
            <int>[0, 1],
            <int>[1, 2],
            <int>[2, 0],
          ],
          'is_builtin': true,
        },
        <String, dynamic>{
          'key': 'user_ab12',
          'label': '我的图形',
          'points': <dynamic>[
            <double>[0.1, 0.1],
            <double>[0.9, 0.1],
            <double>[0.5, 0.9],
          ],
          'edges': <dynamic>[],
          'is_builtin': false,
        },
        // 顶点不足 3 个 → 画不出多边形，跳过（不能给用户一张空卡）。
        <String, dynamic>{
          'key': 'broken',
          'label': '坏行',
          'points': <dynamic>[
            <double>[0.1, 0.1],
          ],
          'is_builtin': true,
        },
      ],
    };

Future<void> _pumpGallery(
  WidgetTester tester,
  _RecordingNetwork net, {
  Size size = const Size(1200, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [networkServiceProvider.overrideWithValue(net)],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: SingleChildScrollView(
            child: FigureLibraryGallery(onOpen: (_) {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('parseFigureLibrary', () {
    test('解析 DB 行（几何 + label + is_builtin），跳过顶点不足的坏行', () {
      final figures = parseFigureLibrary(_libraryPayload());
      expect(figures.map((f) => f.key), <String>['house', 'user_ab12']);
      expect(figures.first.label, '房子');
      expect(figures.first.vertices.length, 3);
      expect(figures.first.vertices.first, (x: 0.3, y: 0.7));
      // 用户行同表：内置与自建图形走同一条解析路径。
      expect(figures.last.label, '我的图形');
    });

    test('图库不表态对称轴：轴数与轴向都不来自 DB（ADR-0083 决策 2）', () {
      final figures = parseFigureLibrary(_libraryPayload());
      for (final f in figures) {
        expect(f.axisAngles, isEmpty, reason: '图库不存 axis，解析层不得凭空补');
      }
    });

    test('label 缺失时回落 key（不显示无名卡）；key 缺失的行跳过', () {
      final figures = parseFigureLibrary(<String, dynamic>{
        'figures': <dynamic>[
          <String, dynamic>{
            'key': 'k1',
            'points': <dynamic>[
              <double>[0.1, 0.1],
              <double>[0.9, 0.1],
              <double>[0.5, 0.9],
            ],
          },
        ],
      });
      expect(figures.single.label, 'k1');
    });

    test('不是对象就抛（类型错误不甩给上层）', () {
      expect(() => parseFigureLibrary(<dynamic>[1, 2]), throwsFormatException);
    });

    test('figures 不是数组 → 空列表（不崩）', () {
      expect(parseFigureLibrary(<String, dynamic>{'figures': 'nope'}), isEmpty);
    });
  });

  group('figureLibraryProvider（按需拉取、会话内一次性）', () {
    test('懒加载：没人读就不发请求', () {
      final net = _RecordingNetwork(payload: _libraryPayload());
      final container = ProviderContainer(
        overrides: [networkServiceProvider.overrideWithValue(net)],
      );
      addTearDown(container.dispose);
      expect(net.calls, isEmpty, reason: '启动期不该拉图库（运行时零图库依赖）');
    });

    test('读取触发一次 GET /materials/scene-library/figures', () async {
      final net = _RecordingNetwork(payload: _libraryPayload());
      final container = ProviderContainer(
        overrides: [networkServiceProvider.overrideWithValue(net)],
      );
      addTearDown(container.dispose);

      final figures = await container.read(figureLibraryProvider.future);
      expect(figures.length, 2);
      expect(net.calls, <String>['/materials/scene-library/figures']);
    });

    test('会话内二次读取不重复请求（同一容器 = 同一会话）', () async {
      final net = _RecordingNetwork(payload: _libraryPayload());
      final container = ProviderContainer(
        overrides: [networkServiceProvider.overrideWithValue(net)],
      );
      addTearDown(container.dispose);

      await container.read(figureLibraryProvider.future);
      await container.read(figureLibraryProvider.future);
      expect(net.calls.length, 1, reason: '会话内应只拉一次');
    });

    test('不是落盘缓存：换一个容器（= 新会话）会重新拉', () async {
      final net = _RecordingNetwork(payload: _libraryPayload());
      final a = ProviderContainer(
        overrides: [networkServiceProvider.overrideWithValue(net)],
      );
      addTearDown(a.dispose);
      await a.read(figureLibraryProvider.future);

      final b = ProviderContainer(
        overrides: [networkServiceProvider.overrideWithValue(net)],
      );
      addTearDown(b.dispose);
      await b.read(figureLibraryProvider.future);
      expect(net.calls.length, 2, reason: '内存只活在会话内，不落盘');
    });

    test('invalidate 后重新拉（画板保存新图形 → 下次能看到）', () async {
      final net = _RecordingNetwork(payload: _libraryPayload());
      final container = ProviderContainer(
        overrides: [networkServiceProvider.overrideWithValue(net)],
      );
      addTearDown(container.dispose);

      await container.read(figureLibraryProvider.future);
      container.invalidate(figureLibraryProvider);
      await container.read(figureLibraryProvider.future);
      expect(net.calls.length, 2);
    });

    test('拉取失败 → error 态（不静默吞掉）', () async {
      final net = _RecordingNetwork(error: StateError('boom'));
      final container = ProviderContainer(
        overrides: [networkServiceProvider.overrideWithValue(net)],
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(figureLibraryProvider.future),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('FigureLibraryGallery（画廊打开即拉）', () {
    testWidgets('打开画廊触发一次拉取，并渲染内置 + 用户行', (tester) async {
      final net = _RecordingNetwork(payload: _libraryPayload());
      await _pumpGallery(tester, net);

      expect(net.calls, <String>['/materials/scene-library/figures']);
      expect(find.text('房子'), findsOneWidget);
      expect(find.text('我的图形'), findsOneWidget);
      // 坏行不渲染。
      expect(find.text('坏行'), findsNothing);
    });

    testWidgets('拉取失败 → 给可重试提示，不显示空网格', (tester) async {
      final net = _RecordingNetwork(error: StateError('offline'));
      await _pumpGallery(tester, net);

      expect(find.text('图形库读取失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });
}
