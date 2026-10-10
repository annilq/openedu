import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../figure_library.dart';
import '../figures.dart';
import 'core_providers.dart';

/// 图库（ADR-0083 决策 7）：几何事实源在 DB，**创作 UI（画板 / 画廊）打开时按需拉
/// 一次**，用完即弃。
///
/// 三条纪律（对应 ticket 05 的验收）：
/// - **懒加载**：启动期不拉。运行时渲染零图库依赖（SceneSpec 自带 `points`/`edges`，
///   交互由 kind 外壳给），所以只有真的打开画板 / 画廊才会发这一次请求。
/// - **会话内一次性**：`FutureProvider` **非 autoDispose** → 结果只活在当前
///   ProviderScope（≈ 一次登录会话）的内存里；同一会话里二次打开画廊不会再发请求。
///   只有**写过新图形**（画板保存成功）后才 `ref.invalidate` 一次以看到新行。
/// - **不落盘**：进程退出即失，不写任何本地缓存（决策 5/6：去掉本地缓存）。
///
/// 为什么选址 `shared`：图库是**跨 feature** 的共享数据（home 的画板 / 知识点编辑器、
/// 课件的挑图形都用它），是 scene 域的共享资产。若挂在某个
/// feature 上，另一个 feature 引用它就成横向依赖（R2）。
final figureLibraryProvider = FutureProvider<List<FigureShape>>((ref) async {
  final net = ref.watch(networkServiceProvider);
  return parseFigureLibrary(await net.get('/materials/scene-library/figures'));
});
