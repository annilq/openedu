import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/material_library_repository_impl.dart';
import '../domain/repositories/material_library_repository.dart';
import '../../../shared/domain/providers/core_providers.dart';

/// materials feature 组合根（ADR-0027）。
final materialLibraryRepositoryProvider = Provider<MaterialLibraryRepository>(
    (ref) => MaterialLibraryRepositoryImpl(ref.watch(networkServiceProvider)));

/// 资料库页状态：目录 + 当前目录下的资料 + 动作提示。
class MaterialLibraryState {
  final List<MaterialFolderModel> folders;

  /// null = 根目录（显示全部资料，含未归目录的）。
  final String? currentFolderId;
  final List<MaterialItemModel> materials;
  final bool loading;
  final String? error;

  /// 动作结果提示（上传 / 向量化 / 删除），一次一条、展示后由 UI 消费清空。
  final String? notice;

  const MaterialLibraryState({
    this.folders = const [],
    this.currentFolderId,
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
    String? currentFolderId,
    bool clearFolder = false,
    List<MaterialItemModel>? materials,
    bool? loading,
    String? error,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
  }) =>
      MaterialLibraryState(
        folders: folders ?? this.folders,
        currentFolderId:
            clearFolder ? null : (currentFolderId ?? this.currentFolderId),
        materials: materials ?? this.materials,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        notice: clearNotice ? null : (notice ?? this.notice),
      );
}

class MaterialLibraryNotifier extends StateNotifier<MaterialLibraryState> {
  MaterialLibraryNotifier(this._repo) : super(const MaterialLibraryState());

  final MaterialLibraryRepository _repo;

  Future<void> load({String? folderId, bool keepFolder = false}) async {
    final target = keepFolder ? state.currentFolderId : folderId;
    state = state.copyWith(loading: true, clearError: true, clearNotice: true);
    try {
      final folders = await _repo.getFolders();
      final materials = await _repo.getMaterials(folderId: target);
      state = state.copyWith(
        folders: folders,
        currentFolderId: target,
        materials: materials,
        loading: false,
      );
    } catch (e) {
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
      await load();
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

  void openFolder(String? folderId) => load(folderId: folderId);

  void consumeNotice() => state = state.copyWith(clearNotice: true);
}

final materialLibraryNotifierProvider =
    StateNotifierProvider<MaterialLibraryNotifier, MaterialLibraryState>((ref) {
  return MaterialLibraryNotifier(ref.watch(materialLibraryRepositoryProvider));
});
