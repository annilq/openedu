import '../models/courseware.dart';
import '../models/courseware_asset.dart';
import '../models/courseware_redraft_diff.dart';
import '../models/courseware_section.dart';

/// 课件仓库（ADR-0067）：素材 + 课件 + 环节序列。
///
/// 端点契约与后端 `app/features/courseware/` 一一对应，字段形状由
/// `domain/models/*` 钉死——**改任一侧都要同步另一侧**。
abstract class CoursewareRepository {
  // ── 素材 ──
  /// 素材库检索（T04）：默认返回本人全部素材；可传 [knowledgePointId] / [filename]
  /// 在服务端过滤（按知识点 / 文件名子串）。两者皆空 = 全部。
  Future<List<CoursewareAssetModel>> getAssets({
    String? knowledgePointId,
    String? filename,
  });

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

  /// 重起草：取新草稿相对当前稿的逐段 diff（不新建副本）。教师逐段选完后把合并
  /// 结果经 [updateSections] 写回同一课件。
  Future<CoursewareRedraftDiffModel> getRedraftDiff(String coursewareId);

  /// 取某知识点已配置的交互讲解模板（KnowledgePoint.scenes）。
  ///
  /// 复用资料库目录端点（每项已带 scenes，后端 `KnowledgePointResp.scenes`），按
  /// id 命中返回；无模板 / 找不到返回 null。课件编辑器「关联知识点场景」用它列出
  /// 可复用模板（ADR-0067 §3.3 / 方案 A）——使「知识点没配就选不到」在课件里也成立。
  ///
  /// ⚠️ 这里跨 feature 直连了 materials 端点：同一个后端、shared 的 [NetworkService]，
  /// 比让 courseware 表现层 import home provider 更干净（数据层收口端点契约）。
  Future<List<Map<String, dynamic>>?> getKnowledgePointScenes({
    required String kpId,
    required String subject,
    required int grade,
    String semester = '',
  });
}
