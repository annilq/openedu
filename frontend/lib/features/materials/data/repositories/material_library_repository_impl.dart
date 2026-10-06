import 'package:dio/dio.dart';

import '../../domain/repositories/material_library_repository.dart';
import '../../../../shared/data/remote/network_service.dart';

/// 资料库仓库实现：端点不包外层（[NetworkService] 返回 FastAPI 原响应体）。
class MaterialLibraryRepositoryImpl implements MaterialLibraryRepository {
  MaterialLibraryRepositoryImpl(this._network);

  final NetworkService _network;

  @override
  Future<List<MaterialFolderModel>> getFolders() async {
    final data = await _network.get('/materials/folders');
    return (data as List? ?? const [])
        .map((e) => MaterialFolderModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<void> createFolder({
    required String name,
    String? parentFolderId,
    String? subject,
    int? grade,
    String? semester,
  }) async {
    await _network.post('/materials/folders', body: {
      'name': name,
      if (parentFolderId != null) 'parent_folder_id': parentFolderId,
      'subject': subject,
      'grade': grade,
      'semester': semester,
    });
  }

  @override
  Future<void> deleteFolder(String folderId) =>
      _network.delete('/materials/folders/$folderId');

  @override
  Future<List<MaterialItemModel>> getMaterials({String? folderId}) async {
    final data = await _network.get(
      '/materials',
      query: {if (folderId != null) 'folder_id': folderId},
    );
    return (data as List? ?? const [])
        .map((e) => MaterialItemModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<MaterialItemModel> upload({
    required String filename,
    required List<int> bytes,
    String? folderId,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      if (folderId != null) 'folder_id': folderId,
    });
    final data = await _network.postForm('/materials/upload', form);
    return MaterialItemModel.fromJson(
        Map<String, dynamic>.from((data as Map)['material'] as Map));
  }

  @override
  Future<MaterialItemModel> vectorize(String materialId) async {
    final data = await _network.post('/materials/$materialId/vectorize');
    return MaterialItemModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<MaterialItemModel> reextract(String materialId) async {
    final data = await _network.post('/materials/$materialId/extract');
    return MaterialItemModel.fromJson(
        Map<String, dynamic>.from((data as Map)['material'] as Map));
  }

  @override
  Future<Map<String, dynamic>> bulkDeleteMaterials(
    List<String> ids, {
    bool cascadeKnowledgePoints = false,
  }) async {
    final data = await _network.post(
      '/materials/bulk-delete',
      body: {'ids': ids, 'cascade_knowledge_points': cascadeKnowledgePoints},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  @override
  Future<void> deleteMaterial(String materialId) =>
      _network.delete('/materials/$materialId');

  @override
  Future<MaterialItemModel> moveMaterial(
    String materialId,
    String? folderId,
  ) async {
    final data = await _network.patch(
      '/materials/$materialId',
      body: {if (folderId != null) 'folder_id': folderId},
    );
    return MaterialItemModel.fromJson(
        Map<String, dynamic>.from((data as Map)));
  }

  @override
  Future<MaterialFolderModel> updateFolder(
    String folderId, {
    String? name,
    String? subject,
    int? grade,
    String? semester,
    String? parentFolderId,
  }) async {
    // 只传非空字段：PATCH 语义下，后端按「出现即改写」处理（含显式 null）。
    // 本客户端不提供「清空某字段」入口，故 null 一律省略，避免误清空既有值。
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (subject != null) body['subject'] = subject;
    if (grade != null) body['grade'] = grade;
    if (semester != null) body['semester'] = semester;
    if (parentFolderId != null) body['parent_folder_id'] = parentFolderId;
    final data = await _network.patch('/folders/$folderId', body: body);
    return MaterialFolderModel.fromJson(
        Map<String, dynamic>.from((data as Map)));
  }
}
