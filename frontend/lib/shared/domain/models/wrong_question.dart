// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。

import 'date_parse.dart';
import 'paging.dart';

class WrongQuestionPage extends CursorPage<WrongQuestionModel> {
  /// 该学生已毕业（已掌握）的错题总数；只在「只看未毕业」时由服务端下发。
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

class WrongQuestionModel {
  /// 错题项（错题本）。`answer` 在学生端恒为 null（防作弊），教师端含答案。
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

  /// 交互式讲解实例（ADR-0061）：题目知识点命中教师私有知识点模板时由后端附带，
  /// 错题卡据此内联渲染交互演示。可空 = 该知识点暂无图形化讲解。
  final Map<String, dynamic>? sceneSpec;

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
    this.sceneSpec,
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
      firstWrongAt: parseDate(json['first_wrong_at']),
      reviewStage: json['review_stage'] as int? ?? 0,
      dueAt: parseDate(json['due_at']),
      graduatedAt: parseDate(json['graduated_at']),
      sceneSpec: json['scene_spec'] as Map<String, dynamic>?,
    );
  }
}

class ReviewItemModel {
  /// 到期复习项（学生端）：含题干、不含答案，附调度进度。
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

  /// 是否多选题（ADR-0004 D5）：渲染复选 / 单选，由后端随题下发。
  final bool multi;

  /// 几何选项组（ADR-0061 §O）：选择题每个选项本身是图形时下发，前端渲染成每个图形
  /// 一个可交互场景；无则 Null。复用 Question.scene_spec 快照，前端只消费不解释。
  final Map<String, dynamic>? sceneSpec;

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
    this.multi = false,
    this.sceneSpec,
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
      dueAt: parseDate(json['due_at']),
      multi: json['multi'] as bool? ?? false,
      sceneSpec: json['scene_spec'] as Map<String, dynamic>?,
    );
  }
}
