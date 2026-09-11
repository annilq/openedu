import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/remote/network_service.dart';

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

// ───────────────────────── 解析守卫（解析容错收一处） ─────────────────────────

/// 把后端 JSON 解成列表；不是数组就报错，而不是把类型错误甩给 UI 层。
///
/// 此前 19 处各自写 `(data as List).map((e) => X.fromJson(e as Map))`，
/// 无类型守卫：后端返回对象时整页白屏，且每处的容错水平不一致。
List<M> decodeList<M>(dynamic data, M Function(Map<String, dynamic>) fromJson) {
  if (data is! List) {
    throw FormatException('期望数组，实际是 ${data.runtimeType}');
  }
  return [
    for (final e in data)
      fromJson(e is Map<String, dynamic> ? e : <String, dynamic>{}),
  ];
}

/// 把后端 JSON 解成对象；不是 Map 就报错。
Map<String, dynamic> decodeMap(dynamic data) {
  if (data is! Map<String, dynamic>) {
    throw FormatException('期望对象，实际是 ${data.runtimeType}');
  }
  return data;
}

// ───────────────────────── 加载器 ─────────────────────────

/// 共享的「取一次 → 解析 → 落状态」流程。
///
/// 子类只提供「去哪儿取」和「怎么解析」；`Loading / Error` 的落法、
/// 异常文案的口径全部在这里定。
mixin _ResourceLoader<T> on StateNotifier<Resource<T>> {
  Future<void> _run(Future<dynamic> Function() fetch, T Function(dynamic) parse) async {
    state = const ResourceLoading();
    try {
      state = ResourceLoaded(parse(await fetch()));
    } catch (e) {
      state = ResourceError(e.toString());
    }
  }
}

/// 固定路径的 GET 资源。
///
/// ```dart
/// final todayTasksProvider = StateNotifierProvider<ResourceNotifier<List<TaskModel>>,
///     Resource<List<TaskModel>>>((ref) => ResourceNotifier(
///           ref.watch(networkServiceProvider),
///           path: '/tasks/today',
///           parse: (d) => decodeList(d, TaskModel.fromJson),
///         ));
/// ```
class ResourceNotifier<T> extends StateNotifier<Resource<T>> with _ResourceLoader<T> {
  ResourceNotifier(
    this._network, {
    required this.path,
    required this.parse,
  }) : super(const ResourceIdle());

  final NetworkService _network;
  final String path;
  final T Function(dynamic data) parse;

  Future<void> load() => _run(() => _network.get(path), parse);
}

/// 路径依赖入参的 GET 资源（如 `/tasks/children/{id}/progress`）。
///
/// [A] 是入参类型；不需要入参时用 [ResourceNotifier]。
class ParamResourceNotifier<T, A> extends StateNotifier<Resource<T>>
    with _ResourceLoader<T> {
  ParamResourceNotifier(
    this._network, {
    required this.pathOf,
    this.queryOf,
    required this.parse,
  }) : super(const ResourceIdle());

  final NetworkService _network;
  final String Function(A arg) pathOf;
  final Map<String, dynamic>? Function(A arg)? queryOf;
  final T Function(dynamic data) parse;

  Future<void> load(A arg) =>
      _run(() => _network.get(pathOf(arg), query: queryOf?.call(arg)), parse);
}
