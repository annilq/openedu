/// 题型 / 难度枚举 → 中文短标签。
///
/// 取值域由后端定义（`backend/app/domain/provider.py#GeneratedQuestion`）：
/// `qtype ∈ {choice, fill, calc, open}`、`difficulty ∈ {easy, medium, hard}`。
///
/// 放在 `shared/` 是因为消费方横跨 feature（home 的出题预览、assistant 的题目卡）——
/// feature 之间不得横向互引（ADR-0037），共用文案只能落此处。
///
/// 已知重复（未在本次统一）：`parent_question_bank_view.dart` 的筛选条用的是**短**标签列表
/// （`_qtypeLabels`），与本文的 [qtypeLabel] 是同一套；题目卡 / 题库卡用的是**长**标签
/// （[qtypeLabelFull]）。两套文案长短不同是**刻意的**——筛选条要窄、卡片要自解释，
/// 不要顺手统一成长短一致。
library;

/// 题型短标签：`calc` → 「计算」。用于筛选条、紧凑标签这类横向空间紧张的位置。
String qtypeLabel(String qtype) => switch (qtype) {
      'calc' => '计算',
      'fill' => '填空',
      'choice' => '选择',
      'open' => '应用',
      _ => qtype,
    };

/// 题型长标签：`calc` → 「计算题」。用于题目卡这类需要自解释的位置。
///
/// ⚠️ 后端权威取值域只有 `choice | fill | calc | open`（`provider.py:42` /
/// `tasks/schemas.py:15`，`grader.py:32` 与 Typst 模板都按 `== "open"` 分支）。
/// 早前 `parent_question_card.dart` 里写的是 `'word' => '应用题'`——那个键不存在，
/// 导致 `open` 题在卡片上直接显示英文原值；本次收口一并修掉。
String qtypeLabelFull(String qtype) => switch (qtype) {
      'calc' => '计算题',
      'fill' => '填空题',
      'choice' => '选择题',
      'open' => '应用题',
      _ => qtype,
    };

/// 难度短标签：`medium` → 「中等」。
String difficultyLabel(String difficulty) => switch (difficulty) {
      'easy' => '简单',
      'medium' => '中等',
      'hard' => '困难',
      _ => difficulty,
    };

/// 任务状态 → 中文：`draft` → 「草稿」。
///
/// 取值域见后端任务状态机（`draft` 草稿 / `ready` 已锁定 / `assigned` 已派发 /
/// `done` 已完成）。收口前 `assistant_cards.dart` 缺 `ready` 分支、`question_bank_view`
/// 有，两份不一致；统一后助手卡遇到 `ready` 也能正确显示。
String statusLabel(String status) => switch (status) {
      'draft' => '草稿',
      'ready' => '已锁定',
      'assigned' => '已派发',
      'done' => '已完成',
      _ => status,
    };
