import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 文件规模静态守卫（ADR-0058）。
///
/// 「一个文件装什么 / 多大」不是类型问题，`flutter analyze` 照不出来，只能静态扫。
/// 本守卫只做两件事：
///
/// 1. **未登记的新文件不得超过 400 行**——这是 ADR-0058 的主要执行力：它拦不住
///    历史债务，但能拦住**下一个** `parent_question_bank_view.dart`（838 行）。
/// 2. **已登记的超限文件不得继续增长**（棘轮）——现存 **12** 个超限文件登记在
///    [_baseline] 里（另 `dev/theme_preview.dart` 1189 行走豁免、`parent_child_selector.dart`
///    正好 400 行未越线），基线**只许下调不许上调**：拆小了把基线跟着调小，长回去就失败。
///    它不强迫任何人现在就去拆分，但保证这些文件不会继续变长。
///
/// 为什么用「棘轮」而不是「一次性把 16 个文件都拆完」：ADR-0044 定下的纪律是
/// **渐进迁移，禁止一次性全量重做**。棘轮让债务单向收缩——每拆掉一个文件，
/// 就把 [_baseline] 里那一条删掉（第 3 条断言会在它降到 400 以下时提醒你删）。
///
/// 有意增长某个已登记文件时（例如往 `app_theme.dart` 加一个令牌），必须同步调高
/// 基线并在 commit 正文说明理由——这个摩擦是故意的。
///
/// 豁免：`lib/dev/**`（视觉走查台，长是它的天性，见 ADR-0058 §1）与生成代码
/// （`*.g.dart` / `*.freezed.dart`）。
void main() {
  /// 单行软阈值。
  const int maxLines = 400;

  test('未登记的文件不得超过 400 行（ADR-0058）', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: '请在 frontend/ 目录下运行（flutter test 的 CWD 应为 frontend/）');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !_isDart(entity.path)) continue;
      final rel = _rel(entity.path);
      if (_isExempt(rel) || _baseline.containsKey(rel)) continue;
      final n = entity.readAsLinesSync().length;
      if (n > maxLines) offenders.add('$rel: $n 行');
    }

    expect(
      offenders,
      isEmpty,
      reason: '新文件不得超过 $maxLines 行（ADR-0058 §1）。超了说明这个文件装了\n'
          '不止一个职责——按 §2/§4 拆：Page → Section → Widget，一个文件只暴露\n'
          '一个公开物。确属例外（dev 走查台 / 生成代码）请加进豁免或 [_baseline]。\n'
          '超限文件：\n${offenders.join('\n')}',
    );
  });

  test('已登记的超限文件不得继续增长（ADR-0058 棘轮）', () {
    final grown = <String>[];
    for (final entry in _baseline.entries) {
      final file = File('lib/${entry.key}');
      if (!file.existsSync()) {
        grown.add('${entry.key}: 文件已不存在，请从 _baseline 删除该条');
        continue;
      }
      final n = file.readAsLinesSync().length;
      if (n > entry.value) {
        grown.add('${entry.key}: $n 行 > 基线 ${entry.value} 行');
      }
    }

    expect(
      grown,
      isEmpty,
      reason: '基线只许下调不许上调。要么把多出来的职责拆出去（然后调低基线），\n'
          '要么在 commit 正文说明为什么这个文件必须变长、并同步调高基线。\n'
          '${grown.join('\n')}',
    );
  });

  test('已降到阈值以下的条目必须从 _baseline 删除（ADR-0058 棘轮）', () {
    final stale = <String>[];
    for (final entry in _baseline.entries) {
      final file = File('lib/${entry.key}');
      if (!file.existsSync()) continue; // 上一条断言已报告
      final n = file.readAsLinesSync().length;
      if (n <= maxLines) {
        stale.add('${entry.key}: 已降到 $n 行，请从 _baseline 删除该条');
      }
    }

    expect(
      stale,
      isEmpty,
      reason: '拆完了就要删登记，否则棘轮会停在旧高度、允许它再长回去。\n'
          '${stale.join('\n')}',
    );
  });
}

/// 现存超限文件的基线（2026-09-21 实测）。**只许下调。**
///
/// 拆分批次见 `docs/refactor/2026-09-21-flutter-ui-decomposition.md`（P0–P4）。
const Map<String, int> _baseline = <String, int>{
  'shared/theme/app_theme.dart': 1695,
  'shared/widgets/adaptive_shell.dart': 490,
  'features/home/presentation/widgets/parent/parent_question_bank_view.dart': 838,
  'features/home/presentation/screens/parent_task_review_screen.dart': 732,
  'features/home/presentation/widgets/parent/parent_tasks_view.dart': 649,
  'features/home/presentation/screens/home_screen.dart': 586,
  'features/assistant/presentation/screens/assistant_chat_page.dart': 557,
  'features/home/presentation/widgets/parent/parent_question_card.dart': 511,
  'features/home/presentation/widgets/parent/parent_wrong_questions_view.dart': 442,
  'features/home/presentation/widgets/child_home.dart': 428,
  'features/home/presentation/widgets/parent/parent_overview_view.dart': 401,
  'features/home/presentation/widgets/parent/parent_child_selector.dart': 404,
};

bool _isDart(String path) =>
    path.endsWith('.dart') &&
    !path.endsWith('.g.dart') &&
    !path.endsWith('.freezed.dart');

/// `lib/dev/**` 是视觉走查台，1189 行是它的工作形态，不按业务文件约束。
bool _isExempt(String rel) =>
    rel.startsWith('dev/') || rel.startsWith('generated/');

/// 取相对 `lib/` 的路径，统一分隔符。
String _rel(String path) {
  final norm = path.replaceAll(r'\', '/');
  const prefix = 'lib/';
  return norm.startsWith(prefix) ? norm.substring(prefix.length) : norm;
}
