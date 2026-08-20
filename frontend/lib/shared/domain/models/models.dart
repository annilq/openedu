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

DateTime? _parseDate(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

class WrongQuestionModel {
  /// 错题项（错题本）。`answer` 在娃娃端恒为 null（防作弊），家长端含答案。
  final String id;
  final String questionId;
  final String subject;
  final int grade;
  final String knowledgePoint;
  final String qtype;
  final String stem;
  final List<String>? options;
  final String? answer;
  final String explanation;
  final int wrongCount;
  final DateTime? firstWrongAt;
  final int reviewStage;
  final DateTime? dueAt;

  WrongQuestionModel({
    required this.id,
    required this.questionId,
    required this.subject,
    required this.grade,
    required this.knowledgePoint,
    required this.qtype,
    required this.stem,
    this.options,
    this.answer,
    this.explanation = '',
    required this.wrongCount,
    this.firstWrongAt,
    this.reviewStage = 0,
    this.dueAt,
  });

  factory WrongQuestionModel.fromJson(Map<String, dynamic> json) {
    return WrongQuestionModel(
      id: json['id'] as String,
      questionId: json['question_id'] as String,
      subject: json['subject'] as String,
      grade: json['grade'] as int,
      knowledgePoint: json['knowledge_point'] as String,
      qtype: json['qtype'] as String,
      stem: json['stem'] as String,
      options: (json['options'] as List?)?.map((e) => e.toString()).toList(),
      answer: json['answer'] as String?,
      explanation: json['explanation'] as String? ?? '',
      wrongCount: json['wrong_count'] as int? ?? 1,
      firstWrongAt: _parseDate(json['first_wrong_at']),
      reviewStage: json['review_stage'] as int? ?? 0,
      dueAt: _parseDate(json['due_at']),
    );
  }
}

class ReviewItemModel {
  /// 到期复习项（娃娃端）：含题干、不含答案，附调度进度。
  final String wrongQuestionId;
  final String questionId;
  final String subject;
  final int grade;
  final String knowledgePoint;
  final String qtype;
  final String stem;
  final List<String>? options;
  final String explanation;
  final int wrongCount;
  final int reviewStage;
  final int nextIntervalDays;
  final DateTime? dueAt;

  ReviewItemModel({
    required this.wrongQuestionId,
    required this.questionId,
    required this.subject,
    required this.grade,
    required this.knowledgePoint,
    required this.qtype,
    required this.stem,
    this.options,
    this.explanation = '',
    required this.wrongCount,
    required this.reviewStage,
    required this.nextIntervalDays,
    this.dueAt,
  });

  factory ReviewItemModel.fromJson(Map<String, dynamic> json) {
    return ReviewItemModel(
      wrongQuestionId: json['wrong_question_id'] as String,
      questionId: json['question_id'] as String,
      subject: json['subject'] as String,
      grade: json['grade'] as int,
      knowledgePoint: json['knowledge_point'] as String,
      qtype: json['qtype'] as String,
      stem: json['stem'] as String,
      options: (json['options'] as List?)?.map((e) => e.toString()).toList(),
      explanation: json['explanation'] as String? ?? '',
      wrongCount: json['wrong_count'] as int? ?? 1,
      reviewStage: json['review_stage'] as int? ?? 0,
      nextIntervalDays: json['next_interval_days'] as int? ?? 1,
      dueAt: _parseDate(json['due_at']),
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

// ───────── AI 伴学答疑（三期 F-302~305） ─────────
class TutorAskReq {
  final String subject;
  final int grade;
  final String knowledgePoint;
  final String? context;
  final String question;

  TutorAskReq({
    required this.subject,
    required this.grade,
    required this.knowledgePoint,
    this.context,
    required this.question,
  });

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'grade': grade,
        'knowledge_point': knowledgePoint,
        'context': context,
        'question': question,
      };
}

class TutorAnswer {
  final String answer;
  final bool blocked;
  final String? reason;

  TutorAnswer({required this.answer, required this.blocked, this.reason});

  factory TutorAnswer.fromJson(Map<String, dynamic> json) {
    return TutorAnswer(
      answer: json['answer'] as String,
      blocked: json['blocked'] as bool? ?? false,
      reason: json['reason'] as String?,
    );
  }
}

class TutorLogModel {
  final String id;
  final int grade;
  final String subject;
  final String knowledgePoint;
  final String question;
  final String answer;
  final bool inputSafe;
  final bool outputSafe;
  final bool blocked;
  final String? createdAt;

  TutorLogModel({
    required this.id,
    required this.grade,
    required this.subject,
    required this.knowledgePoint,
    required this.question,
    required this.answer,
    required this.inputSafe,
    required this.outputSafe,
    required this.blocked,
    this.createdAt,
  });

  factory TutorLogModel.fromJson(Map<String, dynamic> json) {
    return TutorLogModel(
      id: json['id'] as String,
      grade: json['grade'] as int,
      subject: json['subject'] as String,
      knowledgePoint: json['knowledge_point'] as String? ?? '',
      question: json['question'] as String,
      answer: json['answer'] as String,
      inputSafe: json['input_safe'] as bool? ?? true,
      outputSafe: json['output_safe'] as bool? ?? true,
      blocked: json['blocked'] as bool? ?? false,
      createdAt: json['created_at'] as String?,
    );
  }
}

// ───────── AI 使用管控（T10，故事 23/26） ─────────
/// 家长按娃配置的 AI 管控；null 表示该项不启用（走全局默认/不限）。
class TutorQuotaModel {
  final String childId;
  final int? dailyAskLimit;
  final int? dailyMinutesLimit;
  final List<String>? allowedSubjects;

  TutorQuotaModel({
    required this.childId,
    this.dailyAskLimit,
    this.dailyMinutesLimit,
    this.allowedSubjects,
  });

  factory TutorQuotaModel.fromJson(Map<String, dynamic> json) {
    return TutorQuotaModel(
      childId: json['child_id'] as String,
      dailyAskLimit: json['daily_ask_limit'] as int?,
      dailyMinutesLimit: json['daily_minutes_limit'] as int?,
      allowedSubjects: (json['allowed_subjects'] as List?)
          ?.map((e) => e as String)
          .toList(),
    );
  }
}

/// 设置请求体； toJson 时 null 字段也会显式传出（整体覆盖语义）。
class TutorQuotaUpdateReq {
  final int? dailyAskLimit;
  final int? dailyMinutesLimit;
  final List<String>? allowedSubjects;

  TutorQuotaUpdateReq({
    this.dailyAskLimit,
    this.dailyMinutesLimit,
    this.allowedSubjects,
  });

  Map<String, dynamic> toJson() => {
        'daily_ask_limit': dailyAskLimit,
        'daily_minutes_limit': dailyMinutesLimit,
        'allowed_subjects': allowedSubjects,
      };
}

/// 当日用量 + 生效限额（家长端展示剩余）。
class TutorUsageModel {
  final String childId;
  final String date;
  final int asksToday;
  final int usedSeconds;
  final int? askLimit;
  final int? minutesLimit;
  final List<String>? allowedSubjects;

  TutorUsageModel({
    required this.childId,
    required this.date,
    required this.asksToday,
    required this.usedSeconds,
    this.askLimit,
    this.minutesLimit,
    this.allowedSubjects,
  });

  factory TutorUsageModel.fromJson(Map<String, dynamic> json) {
    return TutorUsageModel(
      childId: json['child_id'] as String,
      date: json['date'] as String? ?? '',
      asksToday: json['asks_today'] as int? ?? 0,
      usedSeconds: json['used_seconds'] as int? ?? 0,
      askLimit: json['ask_limit'] as int?,
      minutesLimit: json['minutes_limit'] as int?,
      allowedSubjects: (json['allowed_subjects'] as List?)
          ?.map((e) => e as String)
          .toList(),
    );
  }
}
