// 学情统计聚合响应模型（消费 ticket 11 的三个端点）。
//
// 字段与后端 `app/features/analytics/schemas.py` 对齐。关键口径（ADR-0070）：
// - orphanCount：孤儿错题（原题被硬删，JOIN 不到）数量，界面须以「未知」分组
//   显式标注、不混入任何有效分组。
// - 空学期在后端已收敛为「整学年」，"整学年" 原样展示即可。
// - MasteryGroup.grade 是**题目的年级**（非学生年级），「年级」维度下须显式标注。

class WrongDistributionGroup {
  final String group;
  final int active;
  final int graduated;
  final int total;

  const WrongDistributionGroup({
    required this.group,
    required this.active,
    required this.graduated,
    required this.total,
  });

  factory WrongDistributionGroup.fromJson(Map<String, dynamic> j) =>
      WrongDistributionGroup(
        group: (j['group'] as String?) ?? '',
        active: (j['active'] as int?) ?? 0,
        graduated: (j['graduated'] as int?) ?? 0,
        total: (j['total'] as int?) ?? 0,
      );
}

class WrongDistributionResp {
  final String scope;
  final String dimension;
  final int totalActive;
  final int totalGraduated;
  final int total;
  final List<WrongDistributionGroup> groups;
  final int orphanCount;

  const WrongDistributionResp({
    required this.scope,
    required this.dimension,
    required this.totalActive,
    required this.totalGraduated,
    required this.total,
    required this.groups,
    required this.orphanCount,
  });

  factory WrongDistributionResp.fromJson(Map<String, dynamic> j) =>
      WrongDistributionResp(
        scope: (j['scope'] as String?) ?? '',
        dimension: (j['dimension'] as String?) ?? '',
        totalActive: (j['total_active'] as int?) ?? 0,
        totalGraduated: (j['total_graduated'] as int?) ?? 0,
        total: (j['total'] as int?) ?? 0,
        groups: (j['groups'] as List? ?? [])
            .map((e) => WrongDistributionGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
        orphanCount: (j['orphan_count'] as int?) ?? 0,
      );
}

class AccuracyBreakdown {
  final int total;
  final int correct;
  final double accuracy;

  const AccuracyBreakdown({
    required this.total,
    required this.correct,
    required this.accuracy,
  });

  factory AccuracyBreakdown.fromJson(Map<String, dynamic> j) => AccuracyBreakdown(
        total: (j['total'] as int?) ?? 0,
        correct: (j['correct'] as int?) ?? 0,
        accuracy: (j['accuracy'] as double?) ?? 0.0,
      );
}

class AccuracyGroup {
  final String group;
  final AccuracyBreakdown practice;
  final AccuracyBreakdown review;
  final AccuracyBreakdown overall;

  const AccuracyGroup({
    required this.group,
    required this.practice,
    required this.review,
    required this.overall,
  });

  factory AccuracyGroup.fromJson(Map<String, dynamic> j) => AccuracyGroup(
        group: (j['group'] as String?) ?? '',
        practice: AccuracyBreakdown.fromJson(j['practice'] as Map<String, dynamic>),
        review: AccuracyBreakdown.fromJson(j['review'] as Map<String, dynamic>),
        overall: AccuracyBreakdown.fromJson(j['overall'] as Map<String, dynamic>),
      );
}

class AccuracyResp {
  final String scope;
  final String dimension;
  final String source;
  final List<AccuracyGroup> groups;
  final int orphanCount;

  const AccuracyResp({
    required this.scope,
    required this.dimension,
    required this.source,
    required this.groups,
    required this.orphanCount,
  });

  factory AccuracyResp.fromJson(Map<String, dynamic> j) => AccuracyResp(
        scope: (j['scope'] as String?) ?? '',
        dimension: (j['dimension'] as String?) ?? '',
        source: (j['source'] as String?) ?? 'all',
        groups: (j['groups'] as List? ?? [])
            .map((e) => AccuracyGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
        orphanCount: (j['orphan_count'] as int?) ?? 0,
      );
}

class MasteryGroup {
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

  const MasteryGroup({
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

  factory MasteryGroup.fromJson(Map<String, dynamic> j) => MasteryGroup(
        knowledgePoint: (j['knowledge_point'] as String?) ?? '',
        subject: (j['subject'] as String?) ?? '',
        grade: (j['grade'] as int?) ?? 0,
        totalAnswers: (j['total_answers'] as int?) ?? 0,
        correctAnswers: (j['correct_answers'] as int?) ?? 0,
        accuracy: (j['accuracy'] as double?) ?? 0.0,
        activeWrong: (j['active_wrong'] as int?) ?? 0,
        maxReviewStage: (j['max_review_stage'] as int?) ?? 0,
        score: (j['score'] as double?) ?? 0.0,
        level: (j['level'] as String?) ?? '',
      );
}

class MasteryResp {
  final String scope;
  final int totalKnowledgePoints;
  final int masteredCount;
  final List<MasteryGroup> items;
  final int orphanCount;

  const MasteryResp({
    required this.scope,
    required this.totalKnowledgePoints,
    required this.masteredCount,
    required this.items,
    required this.orphanCount,
  });

  factory MasteryResp.fromJson(Map<String, dynamic> j) => MasteryResp(
        scope: (j['scope'] as String?) ?? '',
        totalKnowledgePoints: (j['total_knowledge_points'] as int?) ?? 0,
        masteredCount: (j['mastered_count'] as int?) ?? 0,
        items: (j['items'] as List? ?? [])
            .map((e) => MasteryGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
        orphanCount: (j['orphan_count'] as int?) ?? 0,
      );
}
