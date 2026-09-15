import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 取数函数：直接返回**领域模型**（不是原始 JSON）。
///
/// 解析（`JSON → Model`）已下沉到 repository；这里只接「一个能取回领域模型的函数」。
/// 因此本文件不 import 任何 `shared/data/**`——取数实现可以自由替换（HTTP / 缓存 /
/// 内存假数据），presentation 层与传输方式彻底解耦。
typedef ResourceFetch<T> = Future<T> Function();

/// 带入参的取数函数，见 [ResourceFetch]。
typedef ParamResourceFetch<T, A> = Future<T> Function(A arg);

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
  const ResourceLoaded(this.data);
}

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
mixin _ResourceLoader<T> on StateNotifier<Resource<T>> {
  Future<void> _run(Future<T> Function() fetch) async {
    state = ResourceLoading<T>();
    try {
      state = ResourceLoaded<T>(await fetch());
    } catch (e) {
      state = ResourceError<T>(e.toString());
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
    with _ResourceLoader<T> {
  ResourceNotifier(this._fetch) : super(const ResourceIdle());

  final ResourceFetch<T> _fetch;

  Future<void> load() => _run(_fetch);
}

/// 取数依赖入参的只读资源（如「按 childId 取进度」）。
///
/// [A] 是入参类型；不需要入参时用 [ResourceNotifier]。
class ParamResourceNotifier<T, A> extends StateNotifier<Resource<T>>
    with _ResourceLoader<T> {
  ParamResourceNotifier(this._fetch) : super(const ResourceIdle());

  final ParamResourceFetch<T, A> _fetch;

  Future<void> load(A arg) => _run(() => _fetch(arg));
}
