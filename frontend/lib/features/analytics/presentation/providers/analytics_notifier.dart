import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../../../../shared/presentation/resource.dart';

/// 学情统计页状态（ticket 12）。
///
/// 一次加载聚合：班级列表 + 学生列表（学生列表仅用于页头「X 名学生」总量徽标），
/// 以及三份统计结果（错题分布 / 正确率 / 掌握度）。三份统计在作用域/维度/选中项
/// 变化时并行重取，大班下也不重复打全量作答扫描（后端单条 GROUP BY，ADR-0070）。
///
/// 作用域仅 two 态：all（全体学生）/ class（单个班级）。单学生统计已移除。
/// 学情统计页聚合载荷（LCC-08）：作用域/维度/选中班级 + 班级列表 + 学生列表 + 三份
/// 统计，包成 [Resource] 的 `T`。班级/学生列表缓存在 notifier 字段，仅首屏拉一次。
class AnalyticsData {
  final String scope; // all | class
  final String dimension; // subject | grade | semester | knowledge_point
  final String? classId;

  final List<ClassModel> classes;
  final List<UserModel> students;

  final WrongDistributionResp wrong;
  final AccuracyResp accuracy;
  final MasteryResp mastery;

  const AnalyticsData({
    required this.scope,
    required this.dimension,
    this.classId,
    required this.classes,
    required this.students,
    required this.wrong,
    required this.accuracy,
    required this.mastery,
  });
}

/// 学情统计加载态统一为 [Resource]：带下钻动作（切作用域/维度/班级触发 _fetch 重载
/// 三份统计），故 `with ResourceLoader` 复用四态落法（LCC-08）。
class AnalyticsNotifier extends StateNotifier<Resource<AnalyticsData>>
    with ResourceLoader<AnalyticsData> {
  final AnalyticsRepository _analytics;
  final ClassesRepository _classes;
  final StudentsRepository _students;

  // 选择器用的全量列表：仅在 init 时拉一次，避免每次切维度都重打。
  List<ClassModel> _classesCache = const [];
  List<UserModel> _studentsCache = const [];

  String _scope = 'all';
  String _dimension = 'knowledge_point';
  String? _classId;

  AnalyticsNotifier(this._analytics, this._classes, this._students)
      : super(const ResourceIdle());

  /// 首屏：拉班级/学生列表 → 取三份统计。
  Future<void> init() async {
    state = const ResourceLoading();
    try {
      final results = await Future.wait([
        _classes.getClasses(),
        _students.getStudents(),
      ]);
      _classesCache = results[0] as List<ClassModel>;
      _studentsCache = results[1] as List<UserModel>;
      await _fetch();
    } catch (e) {
      state = ResourceError(e.toString());
    }
  }

  Future<void> _fetch() => runLoad(() async {
        final results = await Future.wait([
          _analytics.getWrongDistribution(
            scope: _scope,
            classId: _classId,
            dimension: _dimension,
          ),
          _analytics.getAccuracy(
            scope: _scope,
            classId: _classId,
            dimension: _dimension,
          ),
          _analytics.getMastery(
            scope: _scope,
            classId: _classId,
          ),
        ]);
        return AnalyticsData(
          scope: _scope,
          dimension: _dimension,
          classId: _classId,
          classes: _classesCache,
          students: _studentsCache,
          wrong: results[0] as WrongDistributionResp,
          accuracy: results[1] as AccuracyResp,
          mastery: results[2] as MasteryResp,
        );
      });

  void setScope(String scope) {
    if (scope == _scope) return;
    _scope = scope;
    // 切作用域时清空此前选中的班级，避免把上一份作用域的 id 带进新查询。
    _classId = null;
    _fetch();
  }

  void setDimension(String dimension) {
    if (dimension == _dimension) return;
    _dimension = dimension;
    _fetch();
  }

  void setClass(String? classId) {
    if (classId == _classId) return;
    _classId = classId;
    _fetch();
  }
}
