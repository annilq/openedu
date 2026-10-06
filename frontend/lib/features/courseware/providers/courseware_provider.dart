import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/courseware_repository_impl.dart';
import '../domain/models/courseware.dart';
import '../domain/models/courseware_asset.dart';
import '../domain/repositories/courseware_repository.dart';
import '../../../shared/domain/providers/core_providers.dart';

/// courseware feature 组合根（ADR-0027 / ADR-0067）。
final coursewareRepositoryProvider = Provider<CoursewareRepository>(
    (ref) => CoursewareRepositoryImpl(ref.watch(networkServiceProvider)));

/// 课件列表查询条件。用记录类型而非单独建类：它只是四个可空筛选项的搬运，
/// 建一个类会为 ADR-0058「一个文件一个公开物」多占一个文件。
typedef CoursewareListQuery = ({
  String? knowledgePointId,
  String? subject,
  int? grade,
  String? semester,
});

/// 课件列表。全部为空 = 本教师全部课件。
final coursewareListProvider = FutureProvider.autoDispose.family<
    List<CoursewareModel>, CoursewareListQuery>((ref, query) async {
  return ref.watch(coursewareRepositoryProvider).listCourseware(
        knowledgePointId: query.knowledgePointId,
        subject: query.subject,
        grade: query.grade,
        semester: query.semester,
      );
});

/// 单份课件（含环节序列）。
final coursewareDetailProvider =
    FutureProvider.autoDispose.family<CoursewareModel?, String>(
        (ref, coursewareId) async {
  return ref.watch(coursewareRepositoryProvider).getCourseware(coursewareId);
});

/// 最近一份课件——「最近课件」回执的数据源（§3.8 强制补偿项）。
/// null = 还没建过任何课件，此时回执不显示。
final coursewareRecentProvider = FutureProvider.autoDispose<CoursewareModel?>(
    (ref) => ref.watch(coursewareRepositoryProvider).getRecentCourseware());

/// 素材库（图片）。演示与编辑页共用同一份缓存。
final coursewareAssetsProvider =
    FutureProvider.autoDispose<List<CoursewareAssetModel>>(
        (ref) => ref.watch(coursewareRepositoryProvider).getAssets());
