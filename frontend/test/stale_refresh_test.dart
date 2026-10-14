import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/shared/domain/models/paging.dart';
import 'package:kids_learn/shared/presentation/paging.dart';
import 'package:kids_learn/shared/presentation/resource.dart';
import 'package:kids_learn/shared/utils/load_once.dart';

/// 过期则静默刷新（ticket 13，nav-ia-review）。
///
/// 统一的「切回页面刷新」入口，教师端与学生端共用同一套状态机（Resource / Paging），
/// **不写两份**。本文件钉死核心不变量：
///   1. 未过期 → 不发任何请求。
///   2. 已过期 → 后台静默刷新，**不进加载态**（状态始终停在 Loaded），保留旧数据、
///      成功后替换数据 + 时间戳。
///   3. 刷新失败 → 保留旧数据并在 `error` 留痕（不丢数据、不吞失败）。
///   4. 首填（Idle）/ 错误态 → 走正常加载（必要时进加载态）。
void main() {
  final base = DateTime(2026, 1, 1);

  group('ResourceNotifier.refreshIfStale', () {
    test('首填：Idle → 进加载态并落到 Loaded（fetchedAt 被写入）', () async {
      var calls = 0;
      final n = ResourceNotifier<int>(() async {
        calls++;
        return 1;
      });
      n.debugSetClock(() => base);
      final seen = <Resource<int>>[];
      n.addListener((s) => seen.add(s));

      await n.refreshIfStale();
      await Future<void>.value();

      expect(calls, 1);
      expect(n.state, isA<ResourceLoaded<int>>());
      expect((n.state as ResourceLoaded<int>).data, 1);
      expect((n.state as ResourceLoaded<int>).fetchedAt, base);
      expect(seen.whereType<ResourceLoading<int>>(), isNotEmpty,
          reason: '首填必须进加载态');
      expect(seen.whereType<ResourceLoaded<int>>(), isNotEmpty);
    });

    test('未过期 → 不发请求', () async {
      var calls = 0;
      final n = ResourceNotifier<int>(() async {
        calls++;
        return 1;
      });
      n.debugSetClock(() => base);
      await n.load(); // 首填，fetchedAt = base
      expect(calls, 1);

      // 时钟不变 → 未过期。
      await n.refreshIfStale();
      expect(calls, 1, reason: '未过期时不应发起请求');
      expect(n.state, isA<ResourceLoaded<int>>());
    });

    test('已过期 → 静默刷新：不进加载态、保留旧数据、成功后替换', () async {
      var calls = 0;
      final n = ResourceNotifier<int>(() async {
        calls++;
        return calls; // 第 1 次=1，第 2 次=2
      });
      n.debugSetClock(() => base);
      await n.load(); // fetchedAt = base, data = 1

      final seen = <Resource<int>>[];
      n.addListener((s) => seen.add(s));

      // 推进时钟到过期之后。
      n.debugSetClock(() => base.add(const Duration(minutes: 10)));
      await n.refreshIfStale();
      await Future<void>.value();

      expect(calls, 2, reason: '已过期应发起一次刷新');
      expect(n.state, isA<ResourceLoaded<int>>());
      expect((n.state as ResourceLoaded<int>).data, 2); // 新数据
      // 关键：刷新期间从未进入加载态。
      expect(seen.whereType<ResourceLoading<int>>(), isEmpty,
          reason: '静默刷新不得出现 ResourceLoading');
    });

    test('已过期刷新失败 → 保留旧数据并在 error 留痕', () async {
      var calls = 0;
      final n = ResourceNotifier<int>(() async {
        calls++;
        if (calls == 2) throw Exception('boom');
        return 1;
      });
      n.debugSetClock(() => base);
      await n.load(); // data = 1
      final oldData = (n.state as ResourceLoaded<int>).data;

      n.debugSetClock(() => base.add(const Duration(minutes: 10)));
      await n.refreshIfStale();
      await Future<void>.value();

      expect(calls, 2);
      final loaded = n.state as ResourceLoaded<int>;
      expect(loaded.data, oldData, reason: '失败须保留旧数据');
      expect(loaded.error, contains('boom'), reason: '失败须留痕、不吞');
    });

    test('错误态 → 刷新重试成功落到 Loaded', () async {
      var calls = 0;
      final n = ResourceNotifier<int>(() async {
        calls++;
        if (calls == 1) throw Exception('first fail');
        return 42;
      });
      n.debugSetClock(() => base);
      await n.load(); // Error
      expect(n.state, isA<ResourceError<int>>());

      await n.refreshIfStale();
      await Future<void>.value();

      expect(calls, 2);
      expect(n.state, isA<ResourceLoaded<int>>());
      expect((n.state as ResourceLoaded<int>).data, 42);
    });
  });

  group('ParamResourceNotifier.refreshIfStale', () {
    test('带参：未过期不发请求，已过期静默刷新', () async {
      var calls = 0;
      String? lastArg;
      final n = ParamResourceNotifier<int, String>((arg) async {
        calls++;
        lastArg = arg;
        return arg == 'a' ? 1 : 2;
      });
      n.debugSetClock(() => base);
      await n.load('a'); // data=1, fetchedAt=base
      expect(calls, 1);

      await n.refreshIfStale('a'); // 未过期
      expect(calls, 1);

      n.debugSetClock(() => base.add(const Duration(minutes: 10)));
      await n.refreshIfStale('a'); // 过期
      expect(calls, 2);
      expect(lastArg, 'a');
      expect((n.state as ResourceLoaded<int>).data, 1);
    });
  });

  group('PagingNotifier.refreshIfStale', () {
    CursorPage<int> page(int n, {String? cursor}) => CursorPage<int>(
          items: List.generate(n, (i) => i),
          total: n,
          pageSize: n,
          nextCursor: cursor,
        );

    test('首填：Idle → 进加载态并落到 PagingLoaded（fetchedAt 写入）', () async {
      var calls = 0;
      final n = PagingNotifier<int>(({cursor}) async {
        calls++;
        return page(3);
      });
      n.debugSetClock(() => base);
      final seen = <PagingState<int>>[];
      n.addListener((s) => seen.add(s));

      await n.refreshIfStale();
      await Future<void>.value();

      expect(calls, 1);
      expect(n.state, isA<PagingLoaded<int>>());
      expect((n.state as PagingLoaded<int>).fetchedAt, base);
      expect(seen.whereType<PagingLoading<int>>(), isNotEmpty,
          reason: '首填必须进加载态');
      expect(seen.whereType<PagingLoaded<int>>(), isNotEmpty);
    });

    test('未过期 → 不发请求', () async {
      var calls = 0;
      final n = PagingNotifier<int>(({cursor}) async {
        calls++;
        return page(3);
      });
      n.debugSetClock(() => base);
      await n.load();
      expect(calls, 1);

      await n.refreshIfStale();
      expect(calls, 1);
      expect(n.state, isA<PagingLoaded<int>>());
    });

    test('已过期 → 静默刷新：不进 PagingLoading、保留旧列表、成功后替换', () async {
      var calls = 0;
      final n = PagingNotifier<int>(({cursor}) async {
        calls++;
        return page(3, cursor: calls == 2 ? null : 'c');
      });
      n.debugSetClock(() => base);
      await n.load(); // fetchedAt = base

      final seen = <PagingState<int>>[];
      n.addListener((s) => seen.add(s));

      n.debugSetClock(() => base.add(const Duration(minutes: 10)));
      await n.refreshIfStale();
      await Future<void>.value();

      expect(calls, 2);
      expect(n.state, isA<PagingLoaded<int>>());
      expect((n.state as PagingLoaded<int>).items.length, 3);
      expect(seen.whereType<PagingLoading<int>>(), isEmpty,
          reason: '静默刷新不得出现 PagingLoading');
    });

    test('已过期刷新失败 → 保留列表并在 error 留痕', () async {
      var calls = 0;
      final n = PagingNotifier<int>(({cursor}) async {
        calls++;
        if (calls == 2) throw Exception('boom');
        return page(3);
      });
      n.debugSetClock(() => base);
      await n.load();
      final oldLen = (n.state as PagingLoaded<int>).items.length;

      n.debugSetClock(() => base.add(const Duration(minutes: 10)));
      await n.refreshIfStale();
      await Future<void>.value();

      expect(calls, 2);
      final loaded = n.state as PagingLoaded<int>;
      expect(loaded.items.length, oldLen, reason: '失败须保留旧列表');
      expect(loaded.error, contains('boom'));
    });
  });

  group('ParamPagingNotifier.refreshIfStale', () {
    CursorPage<int> page(int n) => CursorPage<int>(
          items: List.generate(n, (i) => i),
          total: n,
          pageSize: n,
        );

    test('带参：未过期不发请求，已过期静默刷新', () async {
      var calls = 0;
      String? lastArg;
      final n = ParamPagingNotifier<int, String>((arg, {cursor}) async {
        calls++;
        lastArg = arg;
        return page(2);
      });
      n.debugSetClock(() => base);
      await n.load('a');
      expect(calls, 1);

      await n.refreshIfStale('a'); // 未过期
      expect(calls, 1);

      n.debugSetClock(() => base.add(const Duration(minutes: 10)));
      await n.refreshIfStale('a'); // 过期
      expect(calls, 2);
      expect(lastArg, 'a');
      expect(n.state, isA<PagingLoaded<int>>());
    });
  });

  // ─────────────────────── widget 层 ───────────────────────
  // 验证「未过期不请求 / 已过期不进加载态」在真实组件树上成立。

  group('widget 层 refreshWhenStale 接线', () {
    testWidgets('已加载未过期不发起请求、不闪加载态', (tester) async {
      var calls = 0;
      final n = ResourceNotifier<List<String>>(() async {
        calls++;
        return ['a', 'b'];
      });
      n.debugSetClock(() => base);
      final provider = StateNotifierProvider<
          ResourceNotifier<List<String>>, Resource<List<String>>>((_) => n);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [provider],
          child: MaterialApp(home: _RefreshHarness(provider: provider)),
        ),
      );

      // 首帧后触发首次刷新（Idle → 首填）。
      await tester.pumpAndSettle();
      expect(calls, 1, reason: '首次应拉取一次');
      expect(find.text('data:a,b'), findsOneWidget);

      // 未过期再触发（按钮）。
      await tester.tap(find.byKey(const Key('refresh')));
      await tester.pumpAndSettle();
      expect(calls, 1, reason: '未过期不应再请求');
      expect(find.text('data:a,b'), findsOneWidget);
      expect(find.text('loading'), findsNothing,
          reason: '未过期刷新不得出现加载态');
    });

    testWidgets('已过期静默刷新——全程不出现加载态', (tester) async {
      var calls = 0;
      final n = ResourceNotifier<List<String>>(() async {
        calls++;
        return calls == 1 ? ['a', 'b'] : ['c', 'd'];
      });
      n.debugSetClock(() => base);
      final provider = StateNotifierProvider<
          ResourceNotifier<List<String>>, Resource<List<String>>>((_) => n);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [provider],
          child: MaterialApp(home: _RefreshHarness(provider: provider)),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('data:a,b'), findsOneWidget);

      // 推进时钟到过期之后，再触发（按钮）。
      n.debugSetClock(() => base.add(const Duration(minutes: 10)));
      await tester.tap(find.byKey(const Key('refresh')));
      // 多泵几帧，确认刷新过程中（后台取数）不渲染加载态。
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(calls, 2, reason: '已过期应发起一次刷新');
      expect(find.text('loading'), findsNothing,
          reason: '静默刷新不得出现加载态');
      expect(find.text('data:c,d'), findsOneWidget,
          reason: '成功后应渲染新数据');
    });
  });
}

/// 受测组件：watch 一个 ResourceNotifier，build 期经 [refreshWhenStale] 推迟触发刷新，
/// 并用文字区分四态，便于断言「是否出现过加载态」。
class _RefreshHarness extends ConsumerStatefulWidget {
  const _RefreshHarness({
    required this.provider,
  });
  final StateNotifierProvider<ResourceNotifier<List<String>>, Resource<List<String>>>
      provider;

  @override
  ConsumerState<_RefreshHarness> createState() => _RefreshHarnessState();
}

class _RefreshHarnessState extends ConsumerState<_RefreshHarness> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.provider);
    // 模拟真实接线：build 期经 refreshWhenStale 推迟触发（首填 + 切回过期刷新）。
    ref.refreshWhenStale(
        () => ref.read(widget.provider.notifier).refreshIfStale());
    return Scaffold(
      body: Column(
        children: [
          if (state is ResourceIdle<List<String>>) const Text('idle'),
          if (state is ResourceLoading<List<String>>) const Text('loading'),
          if (state is ResourceLoaded<List<String>>)
            Text('data:${state.data.join(',')}'),
          if (state is ResourceError<List<String>>) const Text('error'),
          ElevatedButton(
            key: const Key('refresh'),
            onPressed: () =>
                ref.read(widget.provider.notifier).refreshIfStale(),
            child: const Text('refresh'),
          ),
        ],
      ),
    );
  }
}
