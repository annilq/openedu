/// 课件素材：一张要原样投出去的图（ADR-0067 §3.5，ADR-0076 简化为纯教师上传）。
///
/// 与后端 `app/features/courseware/asset_schemas.py::CoursewareAssetResp` 对齐。
///
/// 与「资料（Material）」是两回事：资料是要切分 + 向量化的教材，素材只负责显示，
/// 不进向量库、不参与检索。首版只做图片。ADR-0076 起移除平台预置 CC0，素材库只
/// 收录教师自己上传的图片。
class CoursewareAssetModel {
  final String id;
  final String name;
  final String mime;
  final int sizeBytes;
  final int? width;
  final int? height;
  final DateTime? createdAt;

  /// 可选的知识点关联（T04 素材库按知识点检索）。空 = 不绑特定知识点。
  final String? knowledgePointId;

  /// 读取原图的相对路径（后端下发，前端不自己拼——避免重复实现鉴权前缀）。
  final String url;

  const CoursewareAssetModel({
    this.id = '',
    this.name = '',
    this.mime = '',
    this.sizeBytes = 0,
    this.width,
    this.height,
    this.createdAt,
    this.knowledgePointId,
    this.url = '',
  });

  factory CoursewareAssetModel.fromJson(Map<String, dynamic> json) =>
      CoursewareAssetModel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        mime: json['mime'] as String? ?? '',
        sizeBytes: json['size_bytes'] as int? ?? 0,
        width: json['width'] as int?,
        height: json['height'] as int?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        knowledgePointId: json['knowledge_point_id'] as String?,
        url: json['url'] as String? ?? '',
      );
}
