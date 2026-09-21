// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。

class AnswerResultModel {
  final bool correct;
  final double score;
  final String explanation;

  AnswerResultModel({
    required this.correct,
    required this.score,
    this.explanation = '',
  });

  factory AnswerResultModel.fromJson(Map<String, dynamic> json) {
    return AnswerResultModel(
      correct: json['correct'] as bool,
      score: (json['score'] as num).toDouble(),
      explanation: json['explanation'] as String? ?? '',
    );
  }
}

class CheckinResultModel {
  final bool ok;
  final String checkinDate;

  CheckinResultModel({required this.ok, required this.checkinDate});

  factory CheckinResultModel.fromJson(Map<String, dynamic> json) {
    return CheckinResultModel(
      ok: json['ok'] as bool,
      checkinDate: json['checkin_date'] as String,
    );
  }
}
