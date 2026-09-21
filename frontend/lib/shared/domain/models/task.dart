// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。

import 'paging.dart';
import 'question.dart';

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
