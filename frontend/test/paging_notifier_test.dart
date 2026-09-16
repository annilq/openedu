// 守住分页状态机的行为契约（ADR-0053）。
//
// 背景：题库 / 任务 / 错题本三个长列表共用一套 `PagingState` + `PagingNotifier`。
// 这套机器有四条规则是**类型检查照不出来**的，写错就退化成「列表重复/闪一下/清空」：
//   1. 追加不清空已加载数据（失败也不清）；
//   2. 追加失败保留数据 + 底部暴露原因，不整页报错；
//   3. 并发 `loadMore()` 只发一次请求（触底回调在快速滑动时会连发）；
//   4. `load()` 重置后，在途的旧页不许再拼回来。
import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/presentation/paging.dart';

CursorPage<String> _page(List<String> items, {String? next, int total = 0}) =>
    CursorPage<String>(
      items: items,
      total: total,
      pageSize: 20,
      nextCursor: next,
    );

void main() {
  group('PagingNotifier 首屏与追加', () {
    test('首屏进入 Loaded，hasMore 由 nextCursor 决定', () async {
      final notifier = PagingNotifier<String>(
        ({cursor}) async => _page(['a', 'b'], next: 'c1', total: 5),
      );

      await notifier.load();

      final state = notifier.state;
      expect(state.isLoaded, isTrue);
      expect(state.items, ['a', 'b']);
      expect(state.hasMore, isTrue);
      expect(state.remaining, 3);
    });

    test('追加把新页拼到已加载数据后面（不是替换）', () async {
      final requests = <String?>[];
      final notifier = PagingNotifier<String>(({cursor}) async {
        requests.add(cursor);
        return cursor == null
            ? _page(['a'], next: 'c1', total: 3)
            : _page(['b', 'c'], total: 3);
      });

      await notifier.load();
      await notifier.loadMore();

      expect(requests, [null, 'c1']);
      expect(notifier.state.items, ['a', 'b', 'c']);
      expect(notifier.state.hasMore, isFalse);
      expect(notifier.state.remaining, 0, reason: '到底后「还有 N 条」必须是 0');
    });

    test('没有下一页时 loadMore 不发请求', () async {
      var calls = 0;
      final notifier = PagingNotifier<String>(({cursor}) async {
        calls++;
        return _page(['a'], total: 1);
      });

      await notifier.load();
      await notifier.loadMore();

      expect(calls, 1);
    });

    test('并发 loadMore 只发一次（触底回调连发不产生重复页）', () async {
      var calls = 0;
      final notifier = PagingNotifier<String>(({cursor}) async {
        if (cursor == null) return _page(['a'], next: 'c1', total: 3);
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _page(['b'], total: 3);
      });

      await notifier.load();
      await Future.wait([
        notifier.loadMore(),
        notifier.loadMore(),
        notifier.loadMore(),
      ]);

      expect(calls, 1, reason: '_inFlight 挡住重复请求，否则同一页会被拼两次');
      expect(notifier.state.items, ['a', 'b']);
    });
  });

  group('失败处理', () {
    test('首屏失败进 Error，不残留数据', () async {
      final notifier =
          PagingNotifier<String>(({cursor}) async => throw Exception('网络断了'));

      await notifier.load();

      expect(notifier.state.isLoaded, isFalse);
      expect(notifier.state.errorOrNull, isNotNull);
      expect(notifier.state.items, isEmpty);
    });

    test('追加失败保留已加载数据 + 底部给出原因', () async {
      final notifier = PagingNotifier<String>(({cursor}) async {
        if (cursor == null) return _page(['a'], next: 'c1', total: 3);
        throw Exception('网络断了');
      });

      await notifier.load();
      await notifier.loadMore();

      // 用户已经滑到这里了，因为下一页失败就清空整列表是最糟的处理。
      expect(notifier.state.items, ['a']);
      expect(notifier.state.moreError, isNotNull);
      expect(notifier.state.isLoadingMore, isFalse);
      expect(notifier.state.hasMore, isTrue, reason: '失败后仍可再试');
    });
  });

  group('换条件重新加载', () {
    test('load 重置为 Loading：旧数据不会短暂残留', () async {
      final notifier = PagingNotifier<String>(
        ({cursor}) async => _page(['a'], next: 'c1', total: 2),
      );
      await notifier.load();
      final loadAgain = notifier.load();

      expect(notifier.state.isLoading, isTrue);
      expect(notifier.state.items, isEmpty, reason: '换 Tab 时不能先显示上一个 Tab 的数据');

      await loadAgain;
      expect(notifier.state.items, ['a']);
    });

    test('加载期间被 load 打断：旧页不拼回新结果', () async {
      final notifier = PagingNotifier<String>(({cursor}) async {
        if (cursor == null) return _page(['a'], next: 'c1', total: 9);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _page(['STALE'], total: 9);
      });

      await notifier.load();
      final pending = notifier.loadMore();
      // 模拟用户此刻切换 Tab：loadMore 的结果已经与当前条件无关。
      await notifier.load();
      await pending;

      expect(notifier.state.items, ['a']);
      expect(notifier.state.items.contains('STALE'), isFalse);
    });

    test('ParamPagingNotifier 记住入参：loadMore 无需再传', () async {
      final args = <Object?>[];
      final notifier = ParamPagingNotifier<String, String>((arg, {cursor}) async {
        args.add('$arg:$cursor');
        return cursor == null
            ? _page(['$arg-1'], next: 'c1', total: 2)
            : _page(['$arg-2'], total: 2);
      });

      await notifier.load('c1');
      await notifier.loadMore();

      expect(args, ['c1:null', 'c1:c1']);
      expect(notifier.state.items, ['c1-1', 'c1-2']);
    });
  });

  group('CursorPage 信封', () {
    test('append 累加 items 并接管新的 nextCursor', () {
      final first = _page(['a'], next: 'c1', total: 3);
      final second = _page(['b'], next: 'c2', total: 3);

      final merged = first.append(second);

      expect(merged.items, ['a', 'b']);
      expect(merged.nextCursor, 'c2');
      expect(merged.total, 3);
    });

    test('fromJson 解析 next_cursor / page_size', () {
      final page = CursorPage.fromJson(
        const {'items': [], 'total': 128, 'page_size': 20, 'next_cursor': 'abc'},
        (json) => json['id'] as String,
      );

      expect(page.total, 128);
      expect(page.pageSize, 20);
      expect(page.nextCursor, 'abc');
      expect(page.hasMore, isTrue);
    });
  });
}
