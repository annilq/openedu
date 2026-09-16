// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。

/// 游标分页信封（ADR-0053）：题库 / 任务 / 错题本三个长列表共用。
///
/// 翻页只看 [nextCursor]——[nextCursor] 为 null 即到底。**不要用 [total] 判断是否
/// 还有下一页**：total 是取页那一刻的快照，期间插入新数据后必然失真。
/// [total] 只用于「还有 N 条」这类展示。
class CursorPage<T> {
  final List<T> items;
  final int total;
  final int pageSize;

  /// 下一页游标；null = 已到底。不透明字符串，只能原样回传，不得解析。
  final String? nextCursor;

  const CursorPage({
    required this.items,
    required this.total,
    required this.pageSize,
    this.nextCursor,
  });

  bool get hasMore => nextCursor != null;

  /// 已加载条数（追加模式下由调用方累计，不在这里记账）。
  int get loaded => items.length;

  /// 追加下一页：只在 [hasMore] 时调用，返回新信封（items 为累加结果）。
  CursorPage<T> append(CursorPage<T> next) => CursorPage<T>(
        items: [...items, ...next.items],
        total: next.total,
        pageSize: next.pageSize,
        nextCursor: next.nextCursor,
      );

  factory CursorPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) =>
      CursorPage<T>(
        items: (json['items'] as List? ?? [])
            .map((e) => parse(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int? ?? 0,
        pageSize: json['page_size'] as int? ?? 20,
        nextCursor: json['next_cursor'] as String?,
      );
}

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

/// 流式出题预览卡（票据 08）：对应统一端点 `/assistant/chat` 的 `DATA` 事件
/// （type=question，result 字段为 snake_case 出题结果，无 id）。仅用于预览展示，
/// 不落库；确认后走 `/tasks/from-generated` 持久化。
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
  /// 出题推理过程（ADR-0017）：仅预览态展示，不落库；旧服务端不下发时为空。
  final String reasoning;

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
    this.reasoning = '',
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
        reasoning: json['reasoning'] as String? ?? '',
      );

  /// 回传后端 /tasks/from-generated 落库（snake_case，与 QuestionOut 对齐）。
  Map<String, dynamic> toJson() => {
        'subject': subject,
        'grade': grade,
        'stem': stem,
        'options': options,
        'qtype': qtype,
        'knowledge_point': knowledgePoint,
        'explanation': explanation,
        'answer': answer,
        'difficulty': difficulty,
        'reasoning': reasoning,
      };
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

  /// 创建时间（ISO8601 字符串，列表排序/展示用）。
  final String? createdAt;

  /// 兴趣题模式聚焦主题（WF-4），整卷共享，用于审阅打标与整卷重生成复现。
  final List<String>? focusInterest;

  /// 列表摘要的题目数（ADR-0053）。
  ///
  /// 只有列表接口（`GET /tasks`）给——它不再内嵌题目，卡片上的「N 题」改用这个字段。
  /// 详情接口给的是完整 [questions]。展示一律走 [displayQuestionCount]，
  /// 不要直接读 [questionCount]（详情响应里它是 null）。
  final int? questionCount;

  /// 本卷涉及的学科（按题数降序），列表摘要用；详情接口为空。
  final List<String> subjects;

  bool get isDraft => status == 'draft';
  bool get isReady => status == 'ready';
  bool get isAssigned => status == 'assigned';
  bool get isDone => status == 'done';

  /// 展示用题数：列表摘要取 question_count，详情取 questions.length。
  int get displayQuestionCount => questionCount ?? questions.length;

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
    this.createdAt,
    this.focusInterest,
    this.questionCount,
    this.subjects = const [],
  });

  TaskModel copyWith({
    String? id,
    String? title,
    String? status,
    List<QuestionModel>? questions,
    List<TaskSpecModel>? specs,
    String? childId,
    String? createdAt,
    List<String>? focusInterest,
    int? questionCount,
    List<String>? subjects,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      questions: questions ?? this.questions,
      specs: specs ?? this.specs,
      childId: childId ?? this.childId,
      createdAt: createdAt ?? this.createdAt,
      focusInterest: focusInterest ?? this.focusInterest,
      questionCount: questionCount ?? this.questionCount,
      subjects: subjects ?? this.subjects,
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
      createdAt: json['created_at'] as String?,
      specs: specList,
      focusInterest: (json['focus_interest'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      questions: (json['questions'] as List? ?? [])
          .map((e) => QuestionModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      questionCount: json['question_count'] as int?,
      subjects: (json['subjects'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }
}

/// 各状态任务数（家长任务页三个 Tab 的徽标，ADR-0053）。
///
/// 由服务端在分页响应里带出——徽标若靠客户端统计已加载页，就只有第一页的数。
class TaskCounts {
  final int draft;
  final int ready;
  final int assigned;
  final int done;

  const TaskCounts({
    this.draft = 0,
    this.ready = 0,
    this.assigned = 0,
    this.done = 0,
  });

  /// 「草稿」Tab 的实际内容 = draft + ready（与前端 Tab 划分一致）。
  int get draftTab => draft + ready;

  factory TaskCounts.fromJson(Map<String, dynamic> json) => TaskCounts(
        draft: json['draft'] as int? ?? 0,
        ready: json['ready'] as int? ?? 0,
        assigned: json['assigned'] as int? ?? 0,
        done: json['done'] as int? ?? 0,
      );
}

/// 任务列表响应（ADR-0053）：游标信封 + 三个 Tab 的状态计数。
///
/// 做成 [CursorPage] 的子类而不是并列类型：分页 notifier 只认 [CursorPage]，
/// 计数作为「这一页额外的东西」跟着走，不必为任务单独再写一套分页状态机。
class TaskPage extends CursorPage<TaskModel> {
  final TaskCounts counts;

  const TaskPage({
    required super.items,
    required super.total,
    required super.pageSize,
    super.nextCursor,
    this.counts = const TaskCounts(),
  });

  /// 空页（首屏前的占位 / 取数失败时的兜底）。
  const TaskPage.empty()
      : counts = const TaskCounts(),
        super(items: const [], total: 0, pageSize: 20);

  @override
  CursorPage<TaskModel> append(CursorPage<TaskModel> next) => TaskPage(
        items: [...items, ...next.items],
        total: next.total,
        pageSize: next.pageSize,
        nextCursor: next.nextCursor,
        counts: next is TaskPage ? next.counts : counts,
      );

  factory TaskPage.fromJson(Map<String, dynamic> json) {
    final page = CursorPage.fromJson(json, TaskModel.fromJson);
    return TaskPage(
      items: page.items,
      total: page.total,
      pageSize: page.pageSize,
      nextCursor: page.nextCursor,
      counts: TaskCounts.fromJson(
        (json['counts'] as Map? ?? const {}).cast<String, dynamic>(),
      ),
    );
  }
}

/// 错题本响应（ADR-0053 P2）：游标信封 + 「已掌握」全量计数。
///
/// 与 [TaskPage] 同理，做成 [CursorPage] 的子类：分页 notifier 只认 [CursorPage]，
/// 「已掌握（N）」作为这一页额外的东西跟着走，不必为错题再写一套分页状态机。
class WrongQuestionPage extends CursorPage<WrongQuestionModel> {
  /// 该孩子已毕业（已掌握）的错题总数；只在「只看未毕业」时由服务端下发。
  final int graduatedTotal;

  const WrongQuestionPage({
    required super.items,
    required super.total,
    required super.pageSize,
    super.nextCursor,
    this.graduatedTotal = 0,
  });

  @override
  CursorPage<WrongQuestionModel> append(CursorPage<WrongQuestionModel> next) =>
      WrongQuestionPage(
        items: [...items, ...next.items],
        total: next.total,
        pageSize: next.pageSize,
        nextCursor: next.nextCursor,
        graduatedTotal: next is WrongQuestionPage ? next.graduatedTotal : 0,
      );

  factory WrongQuestionPage.fromJson(Map<String, dynamic> json) {
    final page = CursorPage.fromJson(json, WrongQuestionModel.fromJson);
    return WrongQuestionPage(
      items: page.items,
      total: page.total,
      pageSize: page.pageSize,
      nextCursor: page.nextCursor,
      graduatedTotal: json['graduated_total'] as int? ?? 0,
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

  /// 归档时间（ADR-0053 P2）；null = 在用。前端据此给「已归档」徽标。
  final DateTime? archivedAt;

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
    this.archivedAt,
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
        archivedAt: _parseDate(json['archived_at']),
      );
}

/// 批量删除题库题的结果：deleted / skippedInUse / skippedForbidden 分别给出 id 列表。
class DeleteQuestionsResult {
  final List<String> deleted;
  final List<String> skippedInUse;
  final List<String> skippedForbidden;

  const DeleteQuestionsResult({
    this.deleted = const [],
    this.skippedInUse = const [],
    this.skippedForbidden = const [],
  });

  factory DeleteQuestionsResult.fromJson(Map<String, dynamic> json) =>
      DeleteQuestionsResult(
        deleted:
            (json['deleted'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        skippedInUse: (json['skipped_in_use'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        skippedForbidden: (json['skipped_forbidden'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

/// 批量归档 / 恢复结果（ADR-0053 P2）。
///
/// 与 [DeleteQuestionsResult] 的差别就是归档的意义：没有「被引用所以跳过」这一组——
/// 被任务引用的题也能归档，因为归档不破坏历史任务、且随时能恢复。
class ArchiveQuestionsResult {
  final List<String> updated;
  final List<String> skippedForbidden;

  const ArchiveQuestionsResult({
    this.updated = const [],
    this.skippedForbidden = const [],
  });

  factory ArchiveQuestionsResult.fromJson(Map<String, dynamic> json) =>
      ArchiveQuestionsResult(
        updated:
            (json['updated'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        skippedForbidden: (json['skipped_forbidden'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

/// 题库题被某任务引用的反查结果项（GET /questions/{id}/usages）。
/// 闭环「用过 N 次 → 在哪里用」。
class QuestionUsageItem {
  final String taskId;
  final String title;
  final String status; // draft | ready | assigned | done
  final String? createdAt;

  const QuestionUsageItem({
    required this.taskId,
    required this.title,
    required this.status,
    this.createdAt,
  });

  factory QuestionUsageItem.fromJson(Map<String, dynamic> json) =>
      QuestionUsageItem(
        taskId: json['task_id'] as String,
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? 'draft',
        createdAt: json['created_at'] as String?,
      );
}

/// 题库列表响应 = 通用游标信封（ADR-0053）。
typedef BankListResp = CursorPage<BankQuestionItem>;

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

  /// 毕业（已掌握）时间（ADR-0053 P2）；null = 仍在复习队列里。
  final DateTime? graduatedAt;

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
    this.graduatedAt,
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
      graduatedAt: _parseDate(json['graduated_at']),
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
