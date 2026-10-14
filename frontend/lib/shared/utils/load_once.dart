import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 在 build 期间安全地「仅当 provider 处于空闲态时触发一次异步加载」的惯用法。
///
/// ## 反模式（禁止）
/// 在 `build` 内直接调用 `ref.read(provider.notifier).load()` 会**同步修改被本组件
/// `watch` 的 provider**，触发重入重建循环：`Idle → load → Loading → rebuild → Idle …`，
/// 使共享的 provider 永远停在 `Loading`，所有消费它的页面一起卡转圈。
///
/// ## 正确做法
/// 把触发推迟到本帧绘制完成之后（`addPostFrameCallback`），并在回调内再判一次空闲，
/// 确保每次「空闲期」至多触发一次、绝不在 `build` 期间改状态。本扩展即该模式的一行封装。
///
/// ## 用法
/// ```dart
/// ref.loadWhenIdle(
///   teacherTasksNotifierProvider,
///   (s) => s is ResourceIdle,
///   () => ref.read(teacherTasksNotifierProvider.notifier).load(),
/// );
/// ```
///
/// 其它合法触发时机（无需本 helper）：`initState` / `addPostFrameCallback` /
/// 按钮回调 / `ref.listen` 副作用。
extension WidgetRefLoadOnce on WidgetRef {
  void loadWhenIdle(
    ProviderListenable<dynamic> provider,
    bool Function(dynamic state) isIdle,
    void Function() load,
  ) {
    if (!isIdle(read(provider))) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isIdle(read(provider))) load();
    });
  }

  /// build 期间安全地「过期则静默刷新 / 未加载则首填」一站式触发（ticket 13）。
  ///
  /// 推迟到本帧绘制后触发（绝不在 build 期改 provider 状态）；是否真发请求由
  /// 状态机内部的 [ResourceLoader.refreshIfStale] / [_PagingLoader.refreshIfStale]
  /// 裁决：Idle/Error→首填、Loading→不重启（防 build 期反复推迟触发的重复请求）、
  /// 已加载未过期→不发请求、已加载已过期→后台静默刷新（保留旧数据渲染）。
  ///
  /// 用法：
  /// ```dart
  /// ref.refreshWhenStale(() {
  ///   ref.read(teacherTasksNotifierProvider.notifier)
  ///       .refreshIfStale(kAllTaskStatuses);
  /// });
  /// ```
  void refreshWhenStale(void Function() trigger) {
    WidgetsBinding.instance.addPostFrameCallback((_) => trigger());
  }
}
