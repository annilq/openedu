// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。


class ProgressModel {
  final String childId;
  final int total;
  final int correct;
  final double accuracy;
  final int streakDays;
  final int checkinDays;

  ProgressModel({
    required this.childId,
    required this.total,
    required this.correct,
    required this.accuracy,
    required this.streakDays,
    required this.checkinDays,
  });

  factory ProgressModel.fromJson(Map<String, dynamic> json) {
    return ProgressModel(
      childId: json['child_id'] as String,
      total: json['total'] as int,
      correct: json['correct'] as int,
      accuracy: (json['accuracy'] as num).toDouble(),
      streakDays: json['streak_days'] as int,
      checkinDays: json['checkin_days'] as int,
    );
  }
}

class KnowledgeMasteryModel {
  /// 单个知识点的掌握度（家长看板）。
  final String knowledgePoint;
  final String subject;
  final int grade;
  final int totalAnswers;
  final int correctAnswers;
  final double accuracy;
  final int activeWrong;
  final int maxReviewStage;
  final double score;
  final String level;

  KnowledgeMasteryModel({
    required this.knowledgePoint,
    required this.subject,
    required this.grade,
    required this.totalAnswers,
    required this.correctAnswers,
    required this.accuracy,
    required this.activeWrong,
    required this.maxReviewStage,
    required this.score,
    required this.level,
  });

  factory KnowledgeMasteryModel.fromJson(Map<String, dynamic> json) {
    return KnowledgeMasteryModel(
      knowledgePoint: json['knowledge_point'] as String,
      subject: json['subject'] as String,
      grade: json['grade'] as int,
      totalAnswers: json['total_answers'] as int? ?? 0,
      correctAnswers: json['correct_answers'] as int? ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      activeWrong: json['active_wrong'] as int? ?? 0,
      maxReviewStage: json['max_review_stage'] as int? ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      level: json['level'] as String? ?? '',
    );
  }
}

class MasteryModel {
  /// 知识点掌握度看板（家长端）。
  final String childId;
  final int totalKnowledgePoints;
  final int masteredCount;
  final List<KnowledgeMasteryModel> items;

  MasteryModel({
    required this.childId,
    required this.totalKnowledgePoints,
    required this.masteredCount,
    required this.items,
  });

  factory MasteryModel.fromJson(Map<String, dynamic> json) {
    return MasteryModel(
      childId: json['child_id'] as String,
      totalKnowledgePoints: json['total_knowledge_points'] as int? ?? 0,
      masteredCount: json['mastered_count'] as int? ?? 0,
      items: (json['items'] as List? ?? [])
          .map((e) => KnowledgeMasteryModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
