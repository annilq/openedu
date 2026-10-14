import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 取数函数：直接返回**领域模型**（不是原始 JSON）。
///
/// 解析（`JSON → Model`）已下沉到 repository；这里只接「一个能取回领域模型的函数」。
/// 因此本文件不 import 任何 `shared/data/**`——取数实现可以自由替换（HTTP / 缓存 /
/// 内存假数据），presentation 层与传输方式彻底解耦。
typedef ResourceFetch<T> = Future<T> Function();

/// 带入参的取数函数，见 [ResourceFetch]。
typedef ParamResourceFetch<T, A> = Future<T> Function(A arg);

/// 资源「过期」阈值——全局只此一处（ticket 13，nav-ia-review）。
///
/// 距上次成功取数超过这个时长，就认为数据可能陈旧：切回页面时后台静默刷新一次。
/// 改这个值等于同时改两端所有资源/分页列表的刷新节奏，所以只许写在一处。
const Duration kResourceStaleAfter = Duration(minutes: 5);

/// 距上次取数是否已过 [kResourceStaleAfter]。
///
/// [fetchedAt] 为 null（从未成功取过）一律视为「已过期」——首次进入必然要拉一次。
bool isResourceStale(DateTime? fetchedAt, DateTime now) {
  if (fetchedAt == null) return true;
  return now.difference(fetchedAt) > kResourceStaleAfter;
}

/// 异步资源的四态：**Idle / Loading / Loaded / Error**。
///
/// 此前全工程有 19 份同构的 sealed 四态类（`XxxInitial / XxxLoading /
/// XxxLoaded / XxxError`），每份配一个形状完全相同的 `load()`：
/// `Loading → get → fromJson → Loaded / catch → Error(e.toString())`。
/// 差别只有「路径」和「解析器」，但解析容错与空态判定被复制了 19 遍——
/// 一处修不会传到下一处。这里收成一个泛型状态。
///
/// 只覆盖「取一次资源」这一种形状。**带动作的状态机**（流式生成、对话、
/// 答题、登录）不是资源，别硬套——它们各有自己的事件来源。
sealed class Resource<T> {
  const Resource();
}

class ResourceIdle<T> extends Resource<T> {
  const ResourceIdle();
}

class ResourceLoading<T> extends Resource<T> {
  const ResourceLoading();
}

class ResourceLoaded<T> extends Resource<T> {
  final T data;

  /// 上次成功取数的时刻；null = 从未成功取过（视为已过期）。
  final DateTime? fetchedAt;

  /// 后台静默刷新失败的原因；null = 无。
  ///
  /// 失败时**保留 [data] 继续渲染**，不进错误态、不丢数据，只在此记一笔供 UI
  /// 选择性提示——既不闪错误态吓用户，也不静默吞掉（仍可重试）。
  final String? error;

  const ResourceLoaded(
    this.data, {
    this.fetchedAt,
    this.error,
  });

  ResourceLoaded<T> copyWith({
    T? data,
    DateTime? fetchedAt,
    Object? error = _sentinel,
  }) {
    return ResourceLoaded<T>(
      data ?? this.data,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

/// [copyWith] 的「不改动」哨兵：``error`` 允许显式传 null 清空。
const Object _sentinel = Object();

class ResourceError<T> extends Resource<T> {
  final String message;
  const ResourceError(this.message);
}

/// [Resource] 上的常用判定，省掉每个 widget 各写一遍的 `is XxxLoaded`。
extension ResourceX<T> on Resource<T> {
  bool get isLoading => this is ResourceLoading<T>;

  /// 已加载的数据；其它态为 null。
  T? get dataOrNull => switch (this) {
        ResourceLoaded<T>(:final data) => data,
        _ => null,
      };

  String? get errorOrNull => switch (this) {
        ResourceError<T>(:final message) => message,
        _ => null,
      };
}

// ───────────────────────── 加载器 ─────────────────────────

/// 共享的「取一次 → 落状态」流程。
///
/// `Loading / Error` 的落法、异常文案的口径全部在这里定，子类只提供「去哪儿取」。
///
/// 暴露为公开 mixin：只读资源用现成的 [ResourceNotifier] / [ParamResourceNotifier]，
/// 但凡还带写动作（增 / 改 / 删后重载）的页面，自定义 notifier 也 `with ResourceLoader`
/// 即可复用同一套四态落法，不必再手写 `Loading → get → Loaded / catch → Error`。
mixin ResourceLoader<T> on StateNotifier<Resource<T>> {
  DateTime Function() _now = DateTime.now;

  /// 测试可注入假时钟，使过期判定可预测（不依赖真实时间流逝）。
  void debugSetClock(DateTime Function() clock) => _now = clock;

  /// 后台静默刷新是否已有一次在飞；挡掉「上一个没回来又触发一次」。
  bool _refreshing = false;

  /// 取一次 → 落四态。公开以便自定义 notifier 在写动作后调它重载。
  Future<void> runLoad(Future<T> Function() fetch) async {
    state = ResourceLoading<T>();
    try {
      state = ResourceLoaded<T>(await fetch(), fetchedAt: _now());
    } catch (e) {
      state = ResourceError<T>(e.toString());
    }
  }

  /// 过期则静默刷新：保留旧数据，不进加载态、不闪骨架屏（ticket 13）。
  ///
  /// 统一的「切回页面刷新」内部实现，教师端与学生端共用同一套状态机，不写两份：
  /// - 正在首填（[ResourceLoading]）→ 不重启，避免 build 期反复推迟触发造成的
  ///   重复请求循环。
  /// - 从未加载（[ResourceIdle]）/ 当前是错误态（[ResourceError]）→ 走正常
  ///   [runLoad]（首填或错误重试，必要时进加载态）。
  /// - 已加载但未过期 → **不发任何请求**。
  /// - 已加载且已过期 → 后台重新取数，期间状态停在 [ResourceLoaded]（数据照常渲染）；
  ///   成功则更新数据 + 时间戳；失败则保留数据并在 [ResourceLoaded.error] 留痕
  ///   （不丢数据、不吞失败）。并发保护：已有刷新在飞时直接返回。
  ///
  /// 命名带 `Fetch` 后缀以区别于 notifier 对外暴露的 `refreshIfStale()`——
  /// Dart 不允许子类用同名但不同签名的方法覆盖 mixin 方法，故内部实现与对外入口分开。
  Future<void> refreshIfStaleFetch(Future<T> Function() fetch) async {
    final current = state;
    if (current is ResourceLoading<T>) return; // 首填进行中，不重启。
    if (current is! ResourceLoaded<T>) {
      return runLoad(fetch); // Idle → 首填；Error → 重试。
    }
    if (_refreshing) return;
    if (!isResourceStale(current.fetchedAt, _now())) return; // 未过期，不发请求。
    _refreshing = true;
    try {
      final data = await fetch();
      state = ResourceLoaded<T>(data, fetchedAt: _now());
    } catch (e) {
      state = current.copyWith(error: e.toString());
    } finally {
      _refreshing = false;
    }
  }
}

/// 「取一次就完事」的只读资源。
///
/// 构造只吃一个 [ResourceFetch]，不认识 `NetworkService`、也不做解析——
/// 去哪儿取、怎么解析都由装配方（repository）决定。示例：
///
/// ```dart
/// final todayTasksProvider = StateNotifierProvider<ResourceNotifier<List<TaskModel>>,
///     Resource<List<TaskModel>>>(
///   (ref) => ResourceNotifier(
///     () => ref.watch(tasksRepositoryProvider).todayTasks(),
///   ),
/// );
/// ```
class ResourceNotifier<T> extends StateNotifier<Resource<T>>
    with ResourceLoader<T> {
  ResourceNotifier(this._fetch) : super(const ResourceIdle());

  final ResourceFetch<T> _fetch;

  Future<void> load() => runLoad(_fetch);

  /// 过期则静默刷新（见 [ResourceLoader.refreshIfStaleFetch]）。
  Future<void> refreshIfStale() => refreshIfStaleFetch(_fetch);
}

/// 取数依赖入参的只读资源（如「按 studentId 取进度」）。
///
/// [A] 是入参类型；不需要入参时用 [ResourceNotifier]。
class ParamResourceNotifier<T, A> extends StateNotifier<Resource<T>>
    with ResourceLoader<T> {
  ParamResourceNotifier(this._fetch) : super(const ResourceIdle());

  final ParamResourceFetch<T, A> _fetch;

  Future<void> load(A arg) => runLoad(() => _fetch(arg));

  /// 过期则静默刷新（见 [ResourceLoader.refreshIfStaleFetch]）。
  Future<void> refreshIfStale(A arg) => refreshIfStaleFetch(() => _fetch(arg));
}
