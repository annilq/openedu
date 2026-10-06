import 'package:dio/dio.dart';

import '../../domain/models/courseware.dart';
import '../../domain/models/courseware_asset.dart';
import '../../domain/models/courseware_section.dart';
import '../../domain/repositories/courseware_repository.dart';
import '../../../../shared/data/remote/network_service.dart';

/// 课件仓库实现：端点不包外层（[NetworkService] 返回 FastAPI 原响应体）。
class CoursewareRepositoryImpl implements CoursewareRepository {
  CoursewareRepositoryImpl(this._network);

  final NetworkService _network;

  // ── 素材 ──

  @override
  Future<List<CoursewareAssetModel>> getAssets() async {
    final data = await _network.get('/courseware/assets');
    return (data as List? ?? const [])
        .map((e) =>
            CoursewareAssetModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<CoursewareAssetModel> uploadAsset({
    required String filename,
    required List<int> bytes,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final data = await _network.postForm('/courseware/assets', form);
    return CoursewareAssetModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<void> deleteAsset(String assetId) async {
    await _network.delete('/courseware/assets/$assetId');
  }

  // ── 课件 ──

  @override
  Future<List<CoursewareModel>> listCourseware({
    String? knowledgePointId,
    String? subject,
    int? grade,
    String? semester,
  }) async {
    final data = await _network.get(
      '/courseware',
      query: {
        if (knowledgePointId != null) 'knowledge_point_id': knowledgePointId,
        if (subject != null) 'subject': subject,
        if (grade != null) 'grade': grade,
        if (semester != null) 'semester': semester,
      },
    );
    return (data as List? ?? const [])
        .map((e) => CoursewareModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<CoursewareModel> createCourseware({
    required String knowledgePointId,
    String? title,
  }) async {
    final data = await _network.post('/courseware', body: {
      'knowledge_point_id': knowledgePointId,
      if (title != null) 'title': title,
    });
    return CoursewareModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<CoursewareModel?> getRecentCourseware() async {
    final data = await _network.get('/courseware/recent');
    if (data == null) return null;
    return CoursewareModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<CoursewareModel> getCourseware(String coursewareId) async {
    final data = await _network.get('/courseware/$coursewareId');
    return CoursewareModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<CoursewareModel> updateCourseware(
    String coursewareId, {
    String? title,
    String? status,
  }) async {
    final data = await _network.patch('/courseware/$coursewareId', body: {
      if (title != null) 'title': title,
      if (status != null) 'status': status,
    });
    return CoursewareModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<CoursewareModel> updateSections(
    String coursewareId,
    List<CoursewareSectionModel> sections,
  ) async {
    final data = await _network.put(
      '/courseware/$coursewareId/sections',
      body: {
        'sections': sections.map((s) => s.toJson()).toList(),
      },
    );
    return CoursewareModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<void> deleteCourseware(String coursewareId) async {
    await _network.delete('/courseware/$coursewareId');
  }
}
