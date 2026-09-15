// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。

/// `features/tutor` 独占的领域模型：家长端 AI 伴学答疑日志（F-305）。
///
/// 从 `shared/domain/models/models.dart` 拆出——它是 tutor 一个 feature 的概念，
/// 放在 shared 里会让「改 tutor 的模型」变成「动全工程的共享模型文件」。
// ───────── AI 伴学答疑日志（三期 F-305） ─────────
library;
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
