import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/models.dart';
import 'resource.dart';

/// 分页资源的四态：**Idle / Loading / Loaded / Error**（ADR-0053）。
///
/// 与 [Resource] 同骨架（`shared/presentation/resource.dart`）：「加载 → 错误 → 空 →
/// 有数据」切换时不跳版式（ADR-0051）。差别只在 [PagingLoaded] 多带两组分页信息：
/// - [PagingLoaded.isLoadingMore]：追加下一页中（首屏加载是 [PagingLoading]）。
///   两者必须分开——首屏用整页骨架，追加只在列表底部加一行指示器，不能整页闪一下。
/// - [PagingLoaded.moreError]：追加失败的原因。**它不替换已有数据**：用户已经滑到
///   这里了，因为下一页失败就把整列表清空是最糟的处理；保留数据 + 底部给「重试」。
///
/// 只覆盖「取一页 / 追加一页」这一种形状。带动作的状态机（出题、对话、答题）
/// 不是资源，别硬套。
sealed class PagingState<T> {
  const PagingState();
}

class PagingIdle<T> extends PagingState<T> {
  const PagingIdle();
}

class PagingLoading<T> extends PagingState<T> {
  const PagingLoading();
}

class PagingLoaded<T> extends PagingState<T> {
  /// 已累加的整页结果（不是最后一页——[CursorPage.append] 会把新页拼上去）。
  final CursorPage<T> page;

  /// 正在追加下一页。
  final bool isLoadingMore;

  /// 追加失败的原因；null = 无失败。列表数据仍在。
  final String? moreError;

  /// 首屏最近一次成功取数的时刻；null = 从未成功取过（视为已过期）。
  final DateTime? fetchedAt;

  /// 后台静默刷新（首屏）失败的原因；null = 无。
  ///
  /// 失败时**保留 [page] 继续渲染**，不进错误态、不丢列表，只在此留痕（不静默吞掉）。
  /// 与 [moreError] 区分：后者是「追加下一页」失败，前者是「整页静默刷新」失败。
  final String? error;

  const PagingLoaded(
    this.page, {
    this.isLoadingMore = false,
    this.moreError,
    this.fetchedAt,
    this.error,
  });

  PagingLoaded<T> copyWith({
    CursorPage<T>? page,
    bool? isLoadingMore,
    Object? moreError = _sentinel,
    DateTime? fetchedAt,
    Object? error = _sentinel,
  }) {
    return PagingLoaded<T>(
      page ?? this.page,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      moreError: identical(moreError, _sentinel)
          ? this.moreError
          : moreError as String?,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

/// [copyWith] 的「不改动」哨兵：``moreError`` 允许显式传 null 清空。
const Object _sentinel = Object();

class PagingError<T> extends PagingState<T> {
  final String message;
  const PagingError(this.message);
}

/// [PagingState] 上的常用判定，省掉每个 widget 各写一遍的 `is XxxLoaded`。
extension PagingStateX<T> on PagingState<T> {
  bool get isLoading => this is PagingLoading<T>;

  /// 已加载的条目；其它态为空列表（不要拿它判空态——用 [isLoaded]）。
  List<T> get items => switch (this) {
        PagingLoaded<T>(page: final p) => p.items,
        _ => const [],
      };

  bool get isLoaded => this is PagingLoaded<T>;

  /// 还有下一页（只有已加载态可能为 true）。
  bool get hasMore => switch (this) {
        PagingLoaded<T>(page: final p) => p.hasMore,
        _ => false,
      };

  /// 正在追加下一页。
  bool get isLoadingMore => switch (this) {
        PagingLoaded<T>(isLoadingMore: final v) => v,
        _ => false,
      };

  /// 追加失败的原因。
  String? get moreError => switch (this) {
        PagingLoaded<T>(moreError: final e) => e,
        _ => null,
      };

  /// 总数（服务端快照，只用于「还有 N 条」展示）。
  int get total => switch (this) {
        PagingLoaded<T>(page: final p) => p.total,
        _ => 0,
      };

  /// 还没加载的条数；已到底为 0。
  int get remaining => switch (this) {
        PagingLoaded<T>(page: final p) =>
          p.total - p.loaded > 0 ? p.total - p.loaded : 0,
        _ => 0,
      };

  String? get errorOrNull => switch (this) {
        PagingError<T>(:final message) => message,
        _ => null,
      };
}

// ───────────────────────── 加载器 ─────────────────────────

/// 取一页的函数；``cursor`` 为 null 时取第一页。
typedef PagingFetch<T> = Future<CursorPage<T>> Function({String? cursor});

/// 取一页且依赖入参的函数（如「按 studentId 取错题本」）。
typedef ParamPagingFetch<T, A> = Future<CursorPage<T>> Function(
  A arg, {
  String? cursor,
});

/// 追加式分页的共享流程（ADR-0053）。
///
/// 三个长列表（题库 / 任务 / 错题本）都要「首屏一页 → 触底追加 → 到底给终点」，
/// 各自写一遍必然在防抖与失败处理上分叉，所以收口在这里：
/// - **并发与重复**：`_inFlight` 挡住「上一个请求没回来又触发一次」——触底回调在
///   快速滑动时会连发，不挡就会取到重复页。
/// - **追加失败不清空**：保留已加载数据，只在底部暴露 [PagingLoaded.moreError]。
/// - **换条件即作废在途追加**：见 [_generation]。
mixin _PagingLoader<T> on StateNotifier<PagingState<T>> {
  bool _inFlight = false;

  /// 「查询条件」的世代号：每次 [runFirstPage] 自增。
  ///
  /// 只看 state 类型挡不住这种情况——追加请求在途时用户切了 Tab，`runFirstPage`
  /// 会走完并把状态重新置为 [PagingLoaded]，此时在途的旧页「看起来仍可合并」，
  /// 于是被拼到新 Tab 的结果后面（实测：切 Tab 后多出一条 STALE）。
  /// 所以作废判据必须是「取页时记下的世代号 vs 现在的世代号」，而不是状态类型。
  int _generation = 0;

  DateTime Function() _now = DateTime.now;

  /// 测试可注入假时钟，使过期判定可预测（不依赖真实时间流逝）。
  void debugSetClock(DateTime Function() clock) => _now = clock;

  bool get inFlight => _inFlight;

  Future<void> runFirstPage(Future<CursorPage<T>> Function() fetch) async {
    _generation++;
    _inFlight = true;
    state = const PagingLoading();
    try {
      state = PagingLoaded<T>(await fetch(), fetchedAt: _now());
    } catch (e) {
      state = PagingError<T>(e.toString());
    } finally {
      _inFlight = false;
    }
  }

  Future<void> runNextPage(
    Future<CursorPage<T>> Function(String cursor) fetch,
  ) async {
    final before = state;
    if (before is! PagingLoaded<T> ||
        !before.page.hasMore ||
        _inFlight ||
        before.page.nextCursor == null) {
      return;
    }
    _inFlight = true;
    final generation = _generation;
    state = before.copyWith(isLoadingMore: true, moreError: null);
    try {
      final next = await fetch(before.page.nextCursor!);
      final current = state;
      if (current is! PagingLoaded<T>) return;
      // 期间换过查询条件（切 Tab / 改筛选 / 换学生）→ 这一页已经不属于当前结果。
      if (generation != _generation) return;
      // 追加成功：保留首屏时间戳（fetchedAt），不把整列表重新判为「陈旧」。
      state = current.copyWith(page: current.page.append(next), isLoadingMore: false);
    } catch (e) {
      final current = state;
      if (current is! PagingLoaded<T>) return;
      if (generation != _generation) return;
      state = current.copyWith(isLoadingMore: false, moreError: e.toString());
    } finally {
      _inFlight = false;
    }
  }

  /// 过期则静默刷新首屏：保留已加载列表，不进 [PagingLoading] 整页骨架（ticket 13）。
  ///
  /// 统一的「切回页面刷新」内部实现，教师端与学生端共用同一套状态机，不写两份：
  /// - 正在首屏（[PagingLoading]）→ 不重启，避免 build 期反复推迟触发造成的
  ///   重复请求循环。
  /// - 非 [PagingLoaded]（首次 / 错误态）→ [runFirstPage]（首填或重试，进加载态）。
  /// - 已加载但未过期 → **不发请求**。
  /// - 已加载且已过期 → 后台重取首屏，期间停在 [PagingLoaded]（列表照常渲染）；
  ///   成功替换整页 + 更新时间戳；失败保留列表并在 [PagingLoaded.error] 留痕。
  /// 复用 [_inFlight] 挡掉「上一个刷新没回来又触发一次」；[生成世代] 作废期间
  /// 发生的切 Tab / 换筛选，使这次刷新结果作废。
  ///
  /// 命名带 `Fetch` 后缀以区别于 notifier 对外暴露的 `refreshIfStale()`——
  /// Dart 不允许子类用同名但不同签名的方法覆盖 mixin 方法，故内部实现与对外入口分开。
  Future<void> refreshIfStaleFetch(Future<CursorPage<T>> Function() fetch) async {
    final current = state;
    if (current is PagingLoading<T>) return; // 首屏进行中，不重启。
    if (current is! PagingLoaded<T>) {
      return runFirstPage(fetch); // Idle → 首填；Error → 重试。
    }
    if (_inFlight) return;
    if (!isResourceStale(current.fetchedAt, _now())) return; // 未过期，不发请求。
    final generation = ++_generation;
    _inFlight = true;
    try {
      final page = await fetch();
      if (generation != _generation) return; // 期间换条件，作废本次结果。
      state = PagingLoaded<T>(page, fetchedAt: _now());
    } catch (e) {
      final cur = state;
      if (cur is! PagingLoaded<T>) return;
      if (generation != _generation) return;
      state = cur.copyWith(error: e.toString());
    } finally {
      _inFlight = false;
    }
  }
}

/// 「首屏一页 + 触底追加」的只读资源。
class PagingNotifier<T> extends StateNotifier<PagingState<T>>
    with _PagingLoader<T> {
  PagingNotifier(this._fetch) : super(const PagingIdle());

  final PagingFetch<T> _fetch;

  Future<void> load() => runFirstPage(() => _fetch(cursor: null));

  Future<void> loadMore() =>
      runNextPage((cursor) => _fetch(cursor: cursor));

  /// 过期则静默刷新首屏（见 [_PagingLoader.refreshIfStaleFetch]）。
  Future<void> refreshIfStale() => refreshIfStaleFetch(() => _fetch(cursor: null));
}

/// 取数依赖入参的分页资源（如「按 studentId 取错题本」）。
class ParamPagingNotifier<T, A> extends StateNotifier<PagingState<T>>
    with _PagingLoader<T> {
  ParamPagingNotifier(this._fetch) : super(const PagingIdle());

  final ParamPagingFetch<T, A> _fetch;

  /// 记住入参：[loadMore] 没处传 studentId。
  A? _arg;

  Future<void> load(A arg) {
    _arg = arg;
    return runFirstPage(() => _fetch(arg, cursor: null));
  }

  Future<void> loadMore() {
    final arg = _arg;
    if (arg == null) return Future.value();
    return runNextPage((cursor) => _fetch(arg, cursor: cursor));
  }

  /// 过期则静默刷新首屏（见 [_PagingLoader.refreshIfStaleFetch]）。
  Future<void> refreshIfStale(A arg) {
    _arg = arg;
    return refreshIfStaleFetch(() => _fetch(arg, cursor: null));
  }
}

// ───────────────────────── 触底自动加载 ─────────────────────────

/// 触底预加载距离：距列表底部这么近就提前取下一页（ADR-0053）。
///
/// 取约两行卡片的高度——用户滑到「快到底」时下一页已经在路上，不会看到空白等待。
/// 不用「列表高度的百分比」：短列表会算出几乎为 0、长列表会算出过远。
const double kPagingPrefetchExtent = 240;

/// 给滚动控制器挂「触底自动加载」；返回的回调需在 dispose 里调用以解绑。
///
/// 这里**不做防抖**：连续触发由 notifier 的「有请求在飞就不再发」挡住（见
/// [_PagingLoader.runNextPage]）。在这里再拦一次会重复两道同义的闸，且滚动位置
/// 变化时两者容易不同步。
VoidCallback bindPagingOnScroll(
  ScrollController controller,
  VoidCallback onLoadMore,
) {
  void listener() {
    if (!controller.hasClients) return;
    if (controller.position.extentAfter <= kPagingPrefetchExtent) {
      onLoadMore();
    }
  }

  controller.addListener(listener);
  return () => controller.removeListener(listener);
}
