/// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
/// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。

class UserModel {
  final String id;
  final String username;
  final String displayName;
  final String role; // parent | child
  final int? grade;
  final bool isActive;

  UserModel({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    this.grade,
    this.isActive = true,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      role: json['role'] as String,
      grade: json['grade'] as int?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'role': role,
    'grade': grade,
    'is_active': isActive,
  };

  bool get isParent => role == 'parent';
}

class QuestionModel {
  final String id;
  final String stem;
  final List<String>? options;
  final String qtype;
  final String knowledgePoint;
  final String explanation;
  final String? answer; // 娃娃端恒为 null（防作弊）

  QuestionModel({
    required this.id,
    required this.stem,
    this.options,
    required this.qtype,
    required this.knowledgePoint,
    this.explanation = '',
    this.answer,
  });

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    return QuestionModel(
      id: json['id'] as String,
      stem: json['stem'] as String,
      options: (json['options'] as List?)?.map((e) => e.toString()).toList(),
      qtype: json['qtype'] as String,
      knowledgePoint: json['knowledge_point'] as String,
      explanation: json['explanation'] as String? ?? '',
      answer: json['answer'] as String?,
    );
  }
}

class TaskModel {
  final String id;
  final String title;
  final String subject;
  final int grade;
  final String knowledgePoint;
  final String qtype;
  final String difficulty;
  final int count;
  final String status; // pending | done
  final List<QuestionModel> questions;

  TaskModel({
    required this.id,
    required this.title,
    required this.subject,
    required this.grade,
    required this.knowledgePoint,
    required this.qtype,
    required this.difficulty,
    required this.count,
    required this.status,
    required this.questions,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: json['id'] as String,
      title: json['title'] as String,
      subject: json['subject'] as String,
      grade: json['grade'] as int,
      knowledgePoint: json['knowledge_point'] as String,
      qtype: json['qtype'] as String,
      difficulty: json['difficulty'] as String,
      count: json['count'] as int,
      status: json['status'] as String,
      questions: (json['questions'] as List? ?? [])
          .map((e) => QuestionModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

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
