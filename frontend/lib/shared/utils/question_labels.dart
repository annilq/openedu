/// 题型 / 难度枚举 → 中文短标签。
///
/// 取值域由后端定义（`backend/app/domain/provider.py#GeneratedQuestion`）：
/// `qtype ∈ {choice, fill, calc, open}`、`difficulty ∈ {easy, medium, hard}`。
///
/// 放在 `shared/` 是因为消费方横跨 feature（home 的出题预览、assistant 的题目卡）——
/// feature 之间不得横向互引（ADR-0037），共用文案只能落此处。
///
/// 已知重复（未在本次统一）：`parent_task_review_screen.dart:1016` 与
/// `parent_question_bank_view.dart:321` 各自维护了一份**长**标签（「计算题 / 选择题」），
/// 与本文的短标签（「计算 / 选择」）构成同一枚举的两套文案。统一文案会改变现有页面
/// 的可见字面量，属产品决定，不顺手改。
library;

/// 题型短标签：`calc` → 「计算」。
String qtypeLabel(String qtype) => switch (qtype) {
      'calc' => '计算',
      'fill' => '填空',
      'choice' => '选择',
      'open' => '应用',
      _ => qtype,
    };

/// 难度短标签：`medium` → 「中等」。
String difficultyLabel(String difficulty) => switch (difficulty) {
      'easy' => '简单',
      'medium' => '中等',
      'hard' => '困难',
      _ => difficulty,
    };
