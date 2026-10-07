import 'courseware_section.dart';

/// 逐段 diff 的状态（ADR-0067 第二轮 T07）。
enum CoursewareSectionDiffStatus {
  /// 草稿有、当前稿没有 → 新增。
  added('added'),

  /// 当前稿有、草稿没有 → 待删除（默认保留）。
  removed('removed'),

  /// 同名同类型、内容不同 → 可二选一。
  modified('modified'),

  /// 同名同类型、内容一致 → 无需选择。
  unchanged('unchanged');

  const CoursewareSectionDiffStatus(this.value);

  final String value;

  static CoursewareSectionDiffStatus tryParse(String? raw) => switch (raw) {
        'added' => added,
        'removed' => removed,
        'modified' => modified,
        _ => unchanged,
      };
}

/// 重起草时新草稿相对当前稿的一处差异（后端 `SectionDiffItem` 的同构模型）。
class CoursewareSectionDiffModel {
  final CoursewareSectionDiffStatus status;
  final CoursewareSectionModel? current;
  final CoursewareSectionModel? drafted;

  const CoursewareSectionDiffModel({
    this.status = CoursewareSectionDiffStatus.unchanged,
    this.current,
    this.drafted,
  });

  factory CoursewareSectionDiffModel.fromJson(Map<String, dynamic> json) {
    final c = json['current'];
    final d = json['drafted'];
    return CoursewareSectionDiffModel(
      status: CoursewareSectionDiffStatus.tryParse(json['status'] as String?),
      current: c is Map
          ? CoursewareSectionModel.fromJson(Map<String, dynamic>.from(c))
          : null,
      drafted: d is Map
          ? CoursewareSectionModel.fromJson(Map<String, dynamic>.from(d))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status.value,
        if (current != null) 'current': current!.toJson(),
        if (drafted != null) 'drafted': drafted!.toJson(),
      };
}

/// 整份逐段 diff（后端 `CoursewareRedraftDiff` 的同构模型）。
class CoursewareRedraftDiffModel {
  final List<CoursewareSectionDiffModel> diff;

  const CoursewareRedraftDiffModel({this.diff = const []});

  factory CoursewareRedraftDiffModel.fromJson(Map<String, dynamic> json) {
    final raw = json['diff'];
    final items = <CoursewareSectionDiffModel>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          items.add(CoursewareSectionDiffModel.fromJson(e as Map<String, dynamic>));
        }
      }
    }
    return CoursewareRedraftDiffModel(diff: items);
  }
}

/// 把教师的逐段选择合并成最终环节序列（写回同一课件，不新建副本）。
///
/// [choices] 与 [diff.diff] 等长：true 的语义按状态分派——
/// - [CoursewareSectionDiffStatus.added]：true=采用草稿段；
/// - [removed]：true=删除（丢弃当前段），false=保留；
/// - [modified]：true=用草稿段，false=留当前段；
/// - [unchanged]：忽略，恒取当前段。
List<CoursewareSectionModel> mergeRedraftChoices(
  CoursewareRedraftDiffModel diff,
  List<bool> choices,
) {
  final out = <CoursewareSectionModel>[];
  for (var i = 0; i < diff.diff.length; i++) {
    final item = diff.diff[i];
    final useNew = i < choices.length ? choices[i] : true;
    switch (item.status) {
      case CoursewareSectionDiffStatus.added:
        if (useNew && item.drafted != null) out.add(item.drafted!);
      case CoursewareSectionDiffStatus.removed:
        if (!useNew && item.current != null) out.add(item.current!);
      case CoursewareSectionDiffStatus.modified:
        out.add(useNew ? item.drafted! : item.current!);
      case CoursewareSectionDiffStatus.unchanged:
        if (item.current != null) out.add(item.current!);
    }
  }
  return out;
}
