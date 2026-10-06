import '../models/courseware.dart';
import '../models/courseware_asset.dart';
import '../models/courseware_section.dart';

/// 课件仓库（ADR-0067）：素材 + 课件 + 环节序列。
///
/// 端点契约与后端 `app/features/courseware/` 一一对应，字段形状由
/// `domain/models/*` 钉死——**改任一侧都要同步另一侧**。
abstract class CoursewareRepository {
  // ── 素材 ──
  Future<List<CoursewareAssetModel>> getAssets();

  /// 上传一张图片素材（multipart）。后端按 COURSEWARE_ASSET_MAX_BYTES 与
  /// COURSEWARE_ASSET_MIMES 校验，超限 / 非图片抛错由调用方转提示。
  Future<CoursewareAssetModel> uploadAsset({
    required String filename,
    required List<int> bytes,
  });

  /// 删除素材。**允许删**（决策 10）：不维护引用计数，删后引用它的环节显示
  /// 「素材已移除」占位。
  Future<void> deleteAsset(String assetId);

  // ── 课件 ──
  /// 课件列表。全部参数可空 = 本教师全部课件；[knowledgePointId] 用于知识点行内
  /// 「已有课件 / 未建课件」判定。
  Future<List<CoursewareModel>> listCourseware({
    String? knowledgePointId,
    String? subject,
    int? grade,
    String? semester,
  });

  /// 新建课件：**走 AI 起草**（决策 2）。未配模型时后端返 LLM_UNAVAILABLE，
  /// 由调用方转成「未配置模型」提示（ADR-0039：不静默产出空课件）。
  Future<CoursewareModel> createCourseware({
    required String knowledgePointId,
    String? title,
  });

  /// 最近一份课件（「最近课件」回执用，§3.8 的强制补偿项）。
  /// null = 还没有任何课件。
  Future<CoursewareModel?> getRecentCourseware();

  Future<CoursewareModel> getCourseware(String coursewareId);

  Future<CoursewareModel> updateCourseware(
    String coursewareId, {
    String? title,
    String? status,
  });

  /// 整体覆盖写环节序列（增 / 删 / 改序都在 UI 完成后一次性提交）。
  Future<CoursewareModel> updateSections(
    String coursewareId,
    List<CoursewareSectionModel> sections,
  );

  Future<void> deleteCourseware(String coursewareId);
}
