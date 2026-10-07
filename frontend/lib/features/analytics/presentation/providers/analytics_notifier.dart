import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/analytics_repository.dart';

/// 学情统计页状态（ticket 12）。
///
/// 一次加载聚合：班级列表 + 学生列表（供作用域选择器），以及三份统计结果
/// （错题分布 / 正确率 / 掌握度）。三份统计在作用域/维度/选中项变化时并行重取，
/// 大班下也不重复打全量作答扫描（后端单条 GROUP BY，ADR-0070）。
sealed class AnalyticsState {
  const AnalyticsState();
}

class AnalyticsInitial extends AnalyticsState {
  const AnalyticsInitial();
}

class AnalyticsLoading extends AnalyticsState {
  const AnalyticsLoading();
}

class AnalyticsLoaded extends AnalyticsState {
  final String scope; // all | class | student
  final String dimension; // subject | grade | semester | knowledge_point
  final String? classId;
  final String? studentId;

  final List<ClassModel> classes;
  final List<UserModel> students;

  final WrongDistributionResp wrong;
  final AccuracyResp accuracy;
  final MasteryResp mastery;

  const AnalyticsLoaded({
    required this.scope,
    required this.dimension,
    this.classId,
    this.studentId,
    required this.classes,
    required this.students,
    required this.wrong,
    required this.accuracy,
    required this.mastery,
  });
}

class AnalyticsError extends AnalyticsState {
  final String message;
  const AnalyticsError(this.message);
}

class AnalyticsNotifier extends StateNotifier<AnalyticsState> {
  final AnalyticsRepository _analytics;
  final ClassesRepository _classes;
  final StudentsRepository _students;

  // 选择器用的全量列表：仅在 init 时拉一次，避免每次切维度都重打。
  List<ClassModel> _classesCache = const [];
  List<UserModel> _studentsCache = const [];

  String _scope = 'all';
  String _dimension = 'knowledge_point';
  String? _classId;
  String? _studentId;

  AnalyticsNotifier(this._analytics, this._classes, this._students)
      : super(const AnalyticsInitial());

  /// 首屏：拉班级/学生列表 → 取三份统计。
  Future<void> init() async {
    state = const AnalyticsLoading();
    try {
      final results = await Future.wait([
        _classes.getClasses(),
        _students.getStudents(),
      ]);
      _classesCache = results[0] as List<ClassModel>;
      _studentsCache = results[1] as List<UserModel>;
      await _fetch();
    } catch (e) {
      state = AnalyticsError(e.toString());
    }
  }

  Future<void> _fetch() async {
    state = const AnalyticsLoading();
    try {
      final results = await Future.wait([
        _analytics.getWrongDistribution(
          scope: _scope,
          studentId: _studentId,
          classId: _classId,
          dimension: _dimension,
        ),
        _analytics.getAccuracy(
          scope: _scope,
          studentId: _studentId,
          classId: _classId,
          dimension: _dimension,
        ),
        _analytics.getMastery(
          scope: _scope,
          studentId: _studentId,
          classId: _classId,
        ),
      ]);
      state = AnalyticsLoaded(
        scope: _scope,
        dimension: _dimension,
        classId: _classId,
        studentId: _studentId,
        classes: _classesCache,
        students: _studentsCache,
        wrong: results[0] as WrongDistributionResp,
        accuracy: results[1] as AccuracyResp,
        mastery: results[2] as MasteryResp,
      );
    } catch (e) {
      state = AnalyticsError(e.toString());
    }
  }

  void setScope(String scope) {
    if (scope == _scope) return;
    _scope = scope;
    // 切作用域时清空此前选中的班级/学生，避免把上一份作用域的 id 带进新查询。
    _classId = null;
    _studentId = null;
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

  void setStudent(String? studentId) {
    if (studentId == _studentId) return;
    _studentId = studentId;
    _fetch();
  }
}
