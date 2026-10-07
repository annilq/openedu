/// 课件素材：一张要原样投出去的图（ADR-0067 §3.5）。
///
/// 与后端 `app/features/courseware/asset_schemas.py::CoursewareAssetResp` 对齐。
///
/// 与「资料（Material）」是两回事：资料是要切分 + 向量化的教材，素材只负责显示，
/// 不进向量库、不参与检索。首版只做图片。
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

  /// 来源标记（T08 / ADR-0067 §3.5·§5）：`user_uploaded`=教师自传，
  /// `platform_cc0`=平台预置 CC0 公共素材。
  final String source;

  /// CC0 公共素材的来源 URL（教师可溯源核授权）；非 CC0 为空串。
  final String sourceUrl;

  /// CC0 公共素材的许可类型（如 `CC0 1.0`）；非 CC0 为空串。
  final String license;

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
    this.source = '',
    this.sourceUrl = '',
    this.license = '',
  });

  /// 是否平台预置的 CC0 公共素材（对所有教师可见、不可删除）。
  bool get isPlatformCc0 =>
      source == 'platform_cc0';

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
        source: json['source'] as String? ?? '',
        sourceUrl: json['source_url'] as String? ?? '',
        license: json['license'] as String? ?? '',
      );
}
