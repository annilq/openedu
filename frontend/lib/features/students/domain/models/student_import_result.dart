/// 批量导入学生回执（对接后端 `StudentImportResult`，ADR-0068 §2.2 / ticket 06）。
///
/// 整体 HTTP 200 即文件合法；单行的失败落在 [errors]，由 UI 逐行提示，
/// 便于教师修正表格重新导入。
class StudentImportRowErrorModel {
  final int row;
  final String reason;

  const StudentImportRowErrorModel({required this.row, required this.reason});

  factory StudentImportRowErrorModel.fromJson(Map<String, dynamic> m) =>
      StudentImportRowErrorModel(
        row: (m['row'] as num?)?.toInt() ?? 0,
        reason: (m['reason'] as String?) ?? '',
      );
}

class StudentImportResultModel {
  final int created;
  final int skipped;
  final List<StudentImportRowErrorModel> errors;

  const StudentImportResultModel({
    required this.created,
    required this.skipped,
    required this.errors,
  });

  factory StudentImportResultModel.fromJson(Map<String, dynamic> m) =>
      StudentImportResultModel(
        created: (m['created'] as num?)?.toInt() ?? 0,
        skipped: (m['skipped'] as num?)?.toInt() ?? 0,
        errors: (m['errors'] as List? ?? const [])
            .map((e) => StudentImportRowErrorModel.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
