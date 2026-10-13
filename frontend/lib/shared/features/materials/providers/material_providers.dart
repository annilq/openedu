import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/material_repository_impl.dart';
import '../domain/repositories/material_repository.dart';
import '../../../domain/providers/core_providers.dart';

/// 资料库仓库（场景库 / 知识点管理）的组合根，落在中性层 `shared/features/materials`。
///
/// 为什么在这里而不是 home：场景库编辑器与画板是跨 feature 的素材能力
/// （courseware 也要用），provider 定义放在中性层，home / courseware 都只依赖它，
/// 不再反向穿透到彼此的 feature 内部（ADR 分层 R2 / 破 home↔courseware 循环依赖）。
///
/// 为保留 home 组合根的公开面，[materialRepositoryProvider] 仍由
/// `features/home/providers/home_provider.dart` 再导出（同 assistant_provider 的
/// 既有约定）；新代码可直接引本文件。
final materialRepositoryProvider = Provider<MaterialRepository>((ref) {
  return MaterialRepositoryImpl(ref.watch(networkServiceProvider));
});

/// 内置交互讲解场景库（ADR-0073）：后端登记了哪些 kind + 本教师的关联知识点。
///
/// 场景是**代码内置**（无 DB 表），清单内容只随发版变，一次拉取即可，不必做成
/// 带状态的管理器。
///
/// 重要边界：渲染与出题**从不读这里**——它们读的是 `KnowledgePoint.scenes`
/// （唯一事实源）。本 provider 只服务于编辑器下拉（选 kind → 拿 `defaults` 预填）
/// 与场景库浏览页枚举；拉失败也不影响任何既有行为。
///
/// 同 [materialRepositoryProvider]，[sceneLibraryProvider] 也由
/// `features/home/providers/knowledge_manage_provider.dart` 再导出，维持既有
/// 调用方的 import 路径不变。
final sceneLibraryProvider = FutureProvider<SceneLibrary>((ref) async =>
    ref.watch(materialRepositoryProvider).fetchSceneLibrary());
