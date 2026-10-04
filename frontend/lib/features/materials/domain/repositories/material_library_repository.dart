/// 资料库领域模型与仓库（ADR-0055）。
///
/// 命名红线：不叫 Resource（前端 `Resource<T>` 是加载态三态包装）。
class MaterialFolderModel {
  final String id;
  final String name;
  final String? parentFolderId;
  final String? subject;
  final int? grade;
  final String? semester;
  final int materialCount;
  final int subfolderCount;

  const MaterialFolderModel({
    required this.id,
    required this.name,
    this.parentFolderId,
    this.subject,
    this.grade,
    this.semester,
    this.materialCount = 0,
    this.subfolderCount = 0,
  });

  factory MaterialFolderModel.fromJson(Map<String, dynamic> json) =>
      MaterialFolderModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        parentFolderId: json['parent_folder_id'] as String?,
        subject: json['subject'] as String?,
        grade: json['grade'] as int?,
        semester: json['semester'] as String?,
        materialCount: json['material_count'] as int? ?? 0,
        subfolderCount: json['subfolder_count'] as int? ?? 0,
      );
}

/// 向量化状态（与后端 INDEX_STATES 对齐）。
const kIndexStateLabels = <String, String>{
  'pending': '未向量化',
  'ready': '已就绪',
  'failed': '失败',
  'stale': '已过期',
};

class MaterialItemModel {
  final String id;
  final String? folderId;
  final String name;
  final int sizeBytes;
  final String? subject;
  final int? grade;
  final String? semester;
  final List<String> knowledgePoints;

  /// pending / ready / failed / stale —— 状态徽标的数据源（ADR-0055 §5）。
  final String indexState;
  final String? embedModel;
  final String? indexError;
  final int textLength;

  const MaterialItemModel({
    required this.id,
    this.folderId,
    required this.name,
    this.sizeBytes = 0,
    this.subject,
    this.grade,
    this.semester,
    this.knowledgePoints = const [],
    this.indexState = 'pending',
    this.embedModel,
    this.indexError,
    this.textLength = 0,
  });

  factory MaterialItemModel.fromJson(Map<String, dynamic> json) =>
      MaterialItemModel(
        id: json['id'] as String,
        folderId: json['folder_id'] as String?,
        name: json['name'] as String? ?? '',
        sizeBytes: json['size_bytes'] as int? ?? 0,
        subject: json['subject'] as String?,
        grade: json['grade'] as int?,
        semester: json['semester'] as String?,
        knowledgePoints: (json['knowledge_points'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        indexState: json['index_state'] as String? ?? 'pending',
        embedModel: json['embed_model'] as String?,
        indexError: json['index_error'] as String?,
        textLength: json['text_length'] as int? ?? 0,
      );
}

/// 家长端资料库仓库：目录 + 文件 + 向量化动作。
abstract class MaterialLibraryRepository {
  Future<List<MaterialFolderModel>> getFolders();

  Future<void> createFolder({
    required String name,
    String? parentFolderId,
    String? subject,
    int? grade,
    String? semester,
  });

  Future<void> deleteFolder(String folderId);

  Future<List<MaterialItemModel>> getMaterials({String? folderId});

  /// 上传一份资料（multipart）。返回提取状态四态之一（extracted /
  /// skipped_unsafe / skipped_no_engine / failed）——失败不阻塞入库。
  Future<MaterialItemModel> upload({
    required String filename,
    required List<int> bytes,
    String? folderId,
  });

  /// 手动向量化 / 重新向量化。
  Future<MaterialItemModel> vectorize(String materialId);

  /// 手动重新提取元数据。
  Future<MaterialItemModel> reextract(String materialId);

  Future<void> deleteMaterial(String materialId);

  /// 移动资料到指定目录（[folderId] 为 null = 移回根目录，ADR-0055 B6 补全）。
  Future<MaterialItemModel> moveMaterial(String materialId, String? folderId);

  /// 改目录：重命名 / 改元数据 / 移动到其它目录。只传非空字段（PATCH 语义）。
  Future<MaterialFolderModel> updateFolder(
    String folderId, {
    String? name,
    String? subject,
    int? grade,
    String? semester,
    String? parentFolderId,
  });
}
