import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/material_library_repository_impl.dart';
import '../domain/repositories/material_library_repository.dart';
import '../../../shared/domain/providers/core_providers.dart';

/// materials feature 组合根（ADR-0027）。
final materialLibraryRepositoryProvider = Provider<MaterialLibraryRepository>(
    (ref) => MaterialLibraryRepositoryImpl(ref.watch(networkServiceProvider)));

/// copyWith 里区分「调用方未传该字段」与「显式传 null」的哨兵（避免 null 歧义）。
const Object _kUnset = Object();

/// 资料库页状态：目录 + 当前目录下的资料 + 动作提示。
class MaterialLibraryState {
  final List<MaterialFolderModel> folders;

  /// null = 根目录（显示全部资料，含未归目录的）。
  final String? currentFolderId;

  /// 当前目录的父级 id（null = 当前就在根目录）。与 currentFolderId 一并写入，
  /// 返回按钮直接读它，不再依赖从 [folders] 反查——避免并发刷新时序下
  /// folders 未含当前目录导致返回失效（ADR-0055 B6 修复）。
  final String? parentFolderId;
  final List<MaterialItemModel> materials;
  final bool loading;
  final String? error;

  /// 动作结果提示（上传 / 向量化 / 删除），一次一条、展示后由 UI 消费清空。
  final String? notice;

  const MaterialLibraryState({
    this.folders = const [],
    this.currentFolderId,
    this.parentFolderId,
    this.materials = const [],
    this.loading = false,
    this.error,
    this.notice,
  });

  /// 当前目录（null = 根）。
  MaterialFolderModel? folderById(String? id) {
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  MaterialLibraryState copyWith({
    List<MaterialFolderModel>? folders,
    Object? currentFolderId = _kUnset,
    bool clearFolder = false,
    Object? parentFolderId = _kUnset,
    List<MaterialItemModel>? materials,
    bool? loading,
    String? error,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
  }) =>
      MaterialLibraryState(
        folders: folders ?? this.folders,
        // 与 parentFolderId 同用哨兵：显式传 null（如 load 回到根）必须清掉旧 id，
        // 否则 `null ?? this.currentFolderId` 会把旧目录 id 留下，导致「回到根却仍显示子目录」。
        currentFolderId: clearFolder
            ? null
            : (identical(currentFolderId, _kUnset)
                ? this.currentFolderId
                : currentFolderId as String?),
        parentFolderId: identical(parentFolderId, _kUnset)
            ? this.parentFolderId
            : parentFolderId as String?,
        materials: materials ?? this.materials,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        notice: clearNotice ? null : (notice ?? this.notice),
      );
}

class MaterialLibraryNotifier extends StateNotifier<MaterialLibraryState> {
  MaterialLibraryNotifier(this._repo) : super(const MaterialLibraryState());

  final MaterialLibraryRepository _repo;

  /// 并发 load 守卫：每次 load 递增序号，await 后若已被更新的 load 取代则丢弃结果，
  /// 避免慢的早发请求回写旧 state 把目录卡在错误层级（ADR-0055 B6）。
  int _loadSeq = 0;

  Future<void> load({String? folderId, bool keepFolder = false}) async {
    final target = keepFolder ? state.currentFolderId : folderId;
    final seq = ++_loadSeq;
    state = state.copyWith(loading: true, clearError: true, clearNotice: true);
    try {
      final folders = await _repo.getFolders();
      if (seq != _loadSeq) return; // 已有更新的 load 发起，丢弃本次陈旧结果
      final materials = await _repo.getMaterials(folderId: target);
      if (seq != _loadSeq) return;
      MaterialFolderModel? current;
      for (final f in folders) {
        if (f.id == target) {
          current = f;
          break;
        }
      }
      state = state.copyWith(
        folders: folders,
        currentFolderId: target,
        parentFolderId: current?.parentFolderId,
        materials: materials,
        loading: false,
      );
    } catch (e) {
      if (seq != _loadSeq) return;
      state = state.copyWith(loading: false, error: '加载失败：$e');
    }
  }

  Future<void> createFolder({
    required String name,
    String? subject,
    int? grade,
    String? semester,
  }) async {
    try {
      await _repo.createFolder(
        name: name,
        parentFolderId: state.currentFolderId,
        subject: subject,
        grade: grade,
        semester: semester,
      );
      // 保持当前所在目录：若在某目录内新建子目录，建完应停留并看到新子目录，
      // 而不是被弹回根目录（否则新建的子目录会“消失”，ADR-0055 B6 修复）。
      await load(keepFolder: true);
      state = state.copyWith(notice: '目录「$name」已创建');
    } catch (e) {
      state = state.copyWith(error: '创建目录失败：$e');
    }
  }

  Future<void> deleteFolder(String folderId) async {
    try {
      await _repo.deleteFolder(folderId);
      // 删的是当前目录则回根（后端拒绝非空目录，能删到这的一定是空的）
      final back = state.currentFolderId == folderId;
      await load(folderId: back ? null : state.currentFolderId);
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  Future<void> upload({
    required String filename,
    required List<int> bytes,
  }) async {
    state = state.copyWith(loading: true, clearError: true, clearNotice: true);
    try {
      final mat = await _repo.upload(
        filename: filename,
        bytes: bytes,
        folderId: state.currentFolderId,
      );
      await load(keepFolder: true);
      final hint = switch (mat.indexState) {
        _ when mat.textLength == 0 => '「${mat.name}」上传成功，但未解析出文字',
        _ => '「${mat.name}」已上传，向量化后参与出题',
      };
      state = state.copyWith(loading: false, notice: hint);
    } catch (e) {
      state = state.copyWith(loading: false, error: '上传失败：$e');
    }
  }

  Future<void> vectorize(String materialId) async {
    state = state.copyWith(loading: true, clearError: true, clearNotice: true);
    try {
      final mat = await _repo.vectorize(materialId);
      await load(keepFolder: true);
      state = state.copyWith(
        loading: false,
        notice: mat.indexState == 'ready'
            ? '「${mat.name}」向量化完成'
            : '「${mat.name}」向量化失败：${mat.indexError ?? '未知原因'}',
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '向量化失败：$e');
    }
  }

  Future<void> reextract(String materialId) async {
    state = state.copyWith(loading: true, clearError: true, clearNotice: true);
    try {
      final mat = await _repo.reextract(materialId);
      await load(keepFolder: true);
      state = state.copyWith(loading: false, notice: '「${mat.name}」元数据已更新');
    } catch (e) {
      state = state.copyWith(loading: false, error: '重新提取失败：$e');
    }
  }

  Future<void> deleteMaterial(String materialId) async {
    try {
      await _repo.deleteMaterial(materialId);
      await load(keepFolder: true);
    } catch (e) {
      state = state.copyWith(error: '删除失败：$e');
    }
  }

  /// 移动资料到指定目录（[folderId] 为 null = 移回根目录）。停留当前目录以刷新视图。
  Future<void> moveMaterial(String materialId, String? folderId) async {
    try {
      await _repo.moveMaterial(materialId, folderId);
      await load(keepFolder: true);
      state = state.copyWith(
        notice: folderId == null ? '资料已移回根目录' : '资料已移动到指定目录',
      );
    } catch (e) {
      state = state.copyWith(error: '移动资料失败：$e');
    }
  }

  /// 重命名 / 改目录元数据（学科 / 年级 / 学期）。
  Future<void> renameFolder(
    String folderId, {
    required String name,
    String? subject,
    int? grade,
    String? semester,
  }) async {
    try {
      await _repo.updateFolder(
        folderId,
        name: name,
        subject: subject,
        grade: grade,
        semester: semester,
      );
      await load(keepFolder: true);
      state = state.copyWith(notice: '目录已更新');
    } catch (e) {
      state = state.copyWith(error: '更新目录失败：$e');
    }
  }

  /// 移动目录到其它目录（[parentFolderId] 为 null = 移到根目录）。
  Future<void> moveFolder(String folderId, String? parentFolderId) async {
    try {
      await _repo.updateFolder(folderId, parentFolderId: parentFolderId);
      await load(keepFolder: true);
      state = state.copyWith(
        notice: parentFolderId == null ? '目录已移到根目录' : '目录已移动',
      );
    } catch (e) {
      state = state.copyWith(error: '移动目录失败：$e');
    }
  }

  Future<void> openFolder(String? folderId) => load(folderId: folderId);

  void consumeNotice() => state = state.copyWith(clearNotice: true);
}

final materialLibraryNotifierProvider =
    StateNotifierProvider<MaterialLibraryNotifier, MaterialLibraryState>((ref) {
  return MaterialLibraryNotifier(ref.watch(materialLibraryRepositoryProvider));
});
