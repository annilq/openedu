// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。

/// 娃娃兴趣画像（WF-1 定稿）：受控分类叶子 key 列表 + 「其他爱好」自由文本（≤50 字）。
/// 与后端 `User.interests` 的 {categories, free_text} 形态对齐。
class InterestsModel {
  final List<String> categories; // 受控分类叶子 key（含二级，如 "恐龙"）
  final String? freeText; // 「其他爱好」自由文本

  InterestsModel({this.categories = const [], this.freeText});

  factory InterestsModel.fromJson(Map<String, dynamic> json) {
    final cats = (json['categories'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    return InterestsModel(
      categories: cats,
      freeText: json['free_text'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'categories': categories,
        'free_text': freeText,
      };

  /// 全空（无分类、无自由文本）视为未设置。
  bool get isEmpty =>
      categories.isEmpty && (freeText == null || freeText!.isEmpty);
}

class UserModel {
  final String id;
  final String username;
  final String displayName;
  final String role; // parent | child
  final int? grade;
  final bool isActive;
  final InterestsModel? interests; // 兴趣画像（WF-1/WF-2）

  UserModel({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    this.grade,
    this.isActive = true,
    this.interests,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      role: json['role'] as String,
      grade: json['grade'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      interests: json['interests'] == null
          ? null
          : InterestsModel.fromJson(
              json['interests'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'role': role,
    'grade': grade,
    'is_active': isActive,
    'interests': interests?.toJson(),
  };

  bool get isParent => role == 'parent';
}

class QuestionModel {
  /// 题目（娃娃端读 TaskQuestion 快照）。`id` = TaskQuestion.id，
  /// `questionId` = 源 Question.id（作答提交与错题归集用，ADR-0004 D3）。
  /// `answer` 在娃娃端恒为 null（防作弊）。
  final String id;
  final String? questionId;
  final String subject;
  final int grade;
  final String stem;
  final List<String>? options;
  final String qtype;
  final String knowledgePoint;
  final String explanation;
  final String? answer;
  final String difficulty;

  /// 是否已加入题库（草稿审核用）：questionId != null。
  bool get inQuestionBank => questionId != null;

  QuestionModel({
    required this.id,
    this.questionId,
    this.subject = '',
    this.grade = 0,
    required this.stem,
    this.options,
    required this.qtype,
    required this.knowledgePoint,
    this.explanation = '',
    this.answer,
    this.difficulty = 'medium',
  });

  /// 草稿审核仅允许的编辑字段（R-Q4）。
  Map<String, dynamic> editablePatch({
    String? stem,
    List<String>? options,
    String? answer,
    String? explanation,
  }) {
    final patch = <String, dynamic>{};
    if (stem != null) patch['stem'] = stem;
    if (options != null) patch['options'] = options;
    if (answer != null) patch['answer'] = answer;
    if (explanation != null) patch['explanation'] = explanation;
    return patch;
  }

  QuestionModel copyWith({
    String? id,
    String? questionId,
    String? subject,
    int? grade,
    String? stem,
    List<String>? options,
    String? qtype,
    String? knowledgePoint,
    String? explanation,
    String? answer,
    String? difficulty,
  }) {
    return QuestionModel(
      id: id ?? this.id,
      questionId: questionId ?? this.questionId,
      subject: subject ?? this.subject,
      grade: grade ?? this.grade,
      stem: stem ?? this.stem,
      options: options ?? this.options,
      qtype: qtype ?? this.qtype,
      knowledgePoint: knowledgePoint ?? this.knowledgePoint,
      explanation: explanation ?? this.explanation,
      answer: answer ?? this.answer,
      difficulty: difficulty ?? this.difficulty,
    );
  }

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    return QuestionModel(
      id: json['id'] as String,
      questionId: json['question_id'] as String?,
      subject: json['subject'] as String? ?? '',
      grade: json['grade'] as int? ?? 0,
      stem: json['stem'] as String,
      options: (json['options'] as List?)?.map((e) => e.toString()).toList(),
      qtype: json['qtype'] as String,
      knowledgePoint: json['knowledge_point'] as String,
      explanation: json['explanation'] as String? ?? '',
      answer: json['answer'] as String?,
      difficulty: json['difficulty'] as String? ?? 'medium',
    );
  }
}

/// 流式出题预览卡（票据 08）：对应后端 `/stream/tasks/generate` 的 `question` 事件
/// （snake_case，无 id）。仅用于预览展示，不落库；确认后走 batch-generate 持久化。
class QuestionPreview {
  final String subject;
  final int grade;
  final String stem;
  final List<String>? options;
  final String qtype;
  final String knowledgePoint;
  final String explanation;
  final String? answer;
  final String difficulty;

  const QuestionPreview({
    this.subject = '',
    this.grade = 0,
    this.stem = '',
    this.options,
    this.qtype = 'open',
    this.knowledgePoint = '',
    this.explanation = '',
    this.answer,
    this.difficulty = 'medium',
  });

  factory QuestionPreview.fromJson(Map<String, dynamic> json) => QuestionPreview(
        subject: json['subject'] as String? ?? '',
        grade: json['grade'] as int? ?? 0,
        stem: json['stem'] as String? ?? '',
        options: (json['options'] as List?)?.map((e) => e.toString()).toList(),
        qtype: json['qtype'] as String? ?? 'open',
        knowledgePoint: json['knowledge_point'] as String? ?? '',
        explanation: json['explanation'] as String? ?? '',
        answer: json['answer'] as String?,
        difficulty: json['difficulty'] as String? ?? 'medium',
      );
}

/// 多学科一卷批量生成的一条规格（ADR-0004 D4）。
class TaskSpecModel {
  final String subject;
  final int grade;
  final String knowledgePoint;
  final String qtype;
  final String difficulty;
  final int count;

  TaskSpecModel({
    required this.subject,
    required this.grade,
    required this.knowledgePoint,
    required this.qtype,
    this.difficulty = 'medium',
    required this.count,
  });

  factory TaskSpecModel.fromJson(Map<String, dynamic> json) {
    return TaskSpecModel(
      subject: json['subject'] as String,
      grade: json['grade'] as int,
      knowledgePoint: json['knowledge_point'] as String,
      qtype: json['qtype'] as String,
      difficulty: json['difficulty'] as String? ?? 'medium',
      count: json['count'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'grade': grade,
        'knowledge_point': knowledgePoint,
        'qtype': qtype,
        'difficulty': difficulty,
        'count': count,
      };
}

class TaskModel {
  /// 出题派发容器（ADR-0004）。学科下沉到题，Task 仅存 title/status/questions。
  /// status: draft | ready | assigned | done。
  final String id;
  final String title;
  final String status;
  final List<QuestionModel> questions;

  /// 草稿原始规格，供整卷重生成（R-Q2=c）与审核页摘要展示。
  final List<TaskSpecModel> specs;

  /// 派发对象（创建时可选预先绑定，锁定→派发时强制绑定）。
  final String? childId;

  /// 兴趣题模式聚焦主题（WF-4），整卷共享，用于审阅打标与整卷重生成复现。
  final List<String>? focusInterest;

  bool get isDraft => status == 'draft';
  bool get isReady => status == 'ready';
  bool get isAssigned => status == 'assigned';
  bool get isDone => status == 'done';

  /// 草稿审核：已入库数量（用于展示「X / 总数 已加入题库」）。
  int get promotedCount =>
      questions.where((q) => q.inQuestionBank).length;

  TaskModel({
    required this.id,
    required this.title,
    required this.status,
    required this.questions,
    this.specs = const [],
    this.childId,
    this.focusInterest,
  });

  TaskModel copyWith({
    String? id,
    String? title,
    String? status,
    List<QuestionModel>? questions,
    List<TaskSpecModel>? specs,
    String? childId,
    List<String>? focusInterest,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      questions: questions ?? this.questions,
      specs: specs ?? this.specs,
      childId: childId ?? this.childId,
      focusInterest: focusInterest ?? this.focusInterest,
    );
  }

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    final specList = (json['specs'] as List? ?? [])
        .map((e) => TaskSpecModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return TaskModel(
      id: json['id'] as String,
      title: json['title'] as String,
      status: json['status'] as String? ?? 'draft',
      childId: json['child_id'] as String?,
      specs: specList,
      focusInterest: (json['focus_interest'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      questions: (json['questions'] as List? ?? [])
          .map((e) => QuestionModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ───────── 题库复用闭环（GET /questions / POST /tasks/from-bank 等） ─────────
class BankQuestionItem {
  final String id;
  final String subject;
  final int grade;
  final String stem;
  final List<String>? options;
  final String qtype;
  final String knowledgePoint;
  final String? difficulty;
  final String? answer;
  final String? explanation;
  final int usageCount;

  BankQuestionItem({
    required this.id,
    required this.subject,
    required this.grade,
    required this.stem,
    this.options,
    required this.qtype,
    required this.knowledgePoint,
    this.difficulty,
    this.answer,
    this.explanation,
    this.usageCount = 0,
  });

  factory BankQuestionItem.fromJson(Map<String, dynamic> json) => BankQuestionItem(
        id: json['id'] as String,
        subject: json['subject'] as String? ?? '',
        grade: json['grade'] as int? ?? 0,
        stem: json['stem'] as String,
        options: (json['options'] as List?)?.map((e) => e.toString()).toList(),
        qtype: json['qtype'] as String,
        knowledgePoint: json['knowledge_point'] as String,
        difficulty: json['difficulty'] as String?,
        answer: json['answer'] as String?,
        explanation: json['explanation'] as String?,
        usageCount: (json['usage_count'] as int?) ?? 0,
      );
}

class BankListResp {
  final List<BankQuestionItem> items;
  final int total;
  final int page;
  final int pageSize;
  BankListResp({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });
  factory BankListResp.fromJson(Map<String, dynamic> json) => BankListResp(
        items: (json['items'] as List)
            .map((e) => BankQuestionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        page: json['page'] as int,
        pageSize: json['page_size'] as int,
      );
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
  /// 可选模型 id（内置字符串 id 或家长自定义 UUID）。null = 后端自动（默认/全局）。
  final String? model;

  TutorAskReq({
    required this.subject,
    required this.grade,
    required this.knowledgePoint,
    this.context,
    required this.question,
    this.model,
  });

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'grade': grade,
        'knowledge_point': knowledgePoint,
        'context': context,
        'question': question,
        if (model != null) 'model': model,
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

// ───────── AI 模型（票据 08 多模型流式） ─────────
/// 单个可选模型：内置（builtin=true，id 为字符串）或家长自定义（id 为 UUID 字符串）。
class ModelInfo {
  final String id;
  final String label;
  final String provider; // ollama | openai_compat
  final String? baseUrl;
  final String modelName;
  final bool isBuiltin;
  final bool isDefault;

  const ModelInfo({
    required this.id,
    required this.label,
    required this.provider,
    this.baseUrl,
    required this.modelName,
    this.isBuiltin = false,
    this.isDefault = false,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json, {bool builtin = false}) {
    return ModelInfo(
      id: json['id'].toString(),
      label: json['label'] as String,
      provider: json['provider'] as String,
      baseUrl: json['base_url'] as String?,
      modelName: json['model_name'] as String,
      isBuiltin: builtin,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }
}

class ModelListResp {
  final List<ModelInfo> builtin;
  final List<ModelInfo> custom;

  const ModelListResp({this.builtin = const [], this.custom = const []});

  factory ModelListResp.fromJson(Map<String, dynamic> json) {
    return ModelListResp(
      builtin: (json['builtin'] as List? ?? [])
          .map((e) => ModelInfo.fromJson(e as Map<String, dynamic>, builtin: true))
          .toList(),
      custom: (json['custom'] as List? ?? [])
          .map((e) => ModelInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
