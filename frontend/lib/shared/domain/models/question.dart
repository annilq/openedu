// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。

import 'date_parse.dart';
import 'paging.dart';

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
        archivedAt: parseDate(json['archived_at']),
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
