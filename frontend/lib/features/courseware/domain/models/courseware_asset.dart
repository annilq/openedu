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
        url: json['url'] as String? ?? '',
      );
}
