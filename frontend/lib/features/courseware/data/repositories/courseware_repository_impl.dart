import 'package:dio/dio.dart';

import '../../domain/models/courseware.dart';
import '../../domain/models/courseware_asset.dart';
import '../../domain/models/courseware_redraft_diff.dart';
import '../../domain/models/courseware_section.dart';
import '../../domain/repositories/courseware_repository.dart';
import '../../../../shared/domain/models/knowledge_point_option.dart';
import '../../../../shared/data/remote/network_service.dart';

/// 课件仓库实现：端点不包外层（[NetworkService] 返回 FastAPI 原响应体）。
class CoursewareRepositoryImpl implements CoursewareRepository {
  CoursewareRepositoryImpl(this._network);

  final NetworkService _network;

  // ── 素材 ──

  @override
  Future<List<CoursewareAssetModel>> getAssets({
    String? knowledgePointId,
    String? filename,
  }) async {
    final data = await _network.get(
      '/courseware/assets',
      query: {
        if (knowledgePointId != null) 'knowledge_point': knowledgePointId,
        if (filename != null && filename.isNotEmpty) 'filename': filename,
      },
    );
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
    String? objective,
    bool draft = true,
  }) async {
    final data = await _network.post('/courseware', body: {
      'knowledge_point_id': knowledgePointId,
      if (title != null) 'title': title,
      if (objective != null) 'objective': objective,
      'draft': draft,
    });
    return CoursewareModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<List<KnowledgePointOption>> listKnowledgePoints() async {
    final data =
        await _network.get('/materials/knowledge-points/all');
    final raw = data as Map<String, dynamic>?;
    final items = (raw?['items'] as List? ?? const []);
    return [
      for (final e in items)
        KnowledgePointOption.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
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

  @override
  Future<CoursewareRedraftDiffModel> getRedraftDiff(String coursewareId) async {
    final data = await _network.post('/courseware/$coursewareId/redraft');
    return CoursewareRedraftDiffModel.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  @override
  Future<List<Map<String, dynamic>>?> getKnowledgePointScenes({
    required String kpId,
    required String subject,
    required int grade,
    String semester = '',
  }) async {
    // 改用 /all 端点：返回教师名下**全部**知识点（每项已带 scenes），不按范围过滤。
    // 旧实现用 /knowledge-points + subject/grade/semester 过滤后再按 id 找，一旦课件
    // 的 scope 与知识点真实范围轻微不一致，目标知识点会被过滤掉 → 返回 null → UI 误报
    // 「读取知识点场景失败」。改用 /all 后 id 必然命中（只要属于该教师）。
    // [subject]/[grade]/[semester] 保留为接口上下文、不再参与过滤。
    final data = await _network.get('/materials/knowledge-points/all');
    final raw = data as Map<String, dynamic>?;
    final items = (raw?['items'] as List? ?? const []);
    for (final e in items) {
      final m = Map<String, dynamic>.from(e as Map);
      if (m['id'] == kpId) {
        final scenes = m['scenes'];
        // 知识点存在但 scenes 不是列表（如 null）＝没有可复用模板，归为「空」而非「失败」。
        if (scenes is! List) return const [];
        return [
          for (final s in scenes)
            Map<String, dynamic>.from(s as Map),
        ];
      }
    }
    // 目标 id 不在教师名下（如已删除 / 越权）＝无可关联模板，归为「空」而非「失败」，
    // 让 UI 走「该知识点还没有配置交互讲解模板」引导，而不是「读取失败 + 重试」。
    return const [];
  }
}
