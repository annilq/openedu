import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 静态守卫（ADR-0044「Row(stretch) 必须有界高度」条目）。
///
/// `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` 会要求**高度有界**；
/// 一旦它落在高度无界的上下文里（Column 的子项、ListView / CustomScrollView 内），
/// 就会抛 `BoxConstraints forces an infinite height`（`h=Infinity`）。
/// 本仓的既有解法是把该 Row 包进 `IntrinsicHeight`，给它一个有界高度。
///
/// 用**棘轮**守住：允许集合只许变短、不许变长。
///
/// 下面登记的 5 个站点是「裸语法但安全」的：这些行的左侧学科色条靠 Row(stretch)
/// 撑满卡片，已在**调用点**用 `IntrinsicHeight` 包住了对应 widget（见各处注释）。
/// 新增裸站点会直接红 → 请改为在**行内**直接用 `IntrinsicHeight` 包住 Row。
const _knownBareRowStretch = <String>{
  'features/home/presentation/widgets/child_home.dart::_TaskCard',
  'features/practice/presentation/widgets/practice_question_view.dart::PracticeQuestionView',
  'features/practice/presentation/widgets/practice_review_view.dart::_WrongToFixCard',
  'features/review/presentation/screens/wrong_questions_screen.dart::_WrongQuestionCard',
  'features/assistant/presentation/widgets/assistant_cards.dart::_QuestionCard',
};

void main() {
  test('裸 Row(stretch) 站点只减不增（ADR-0044）', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: '请在 frontend/ 目录下运行（flutter test 的 CWD 应为 frontend/）');

    final found = <String>{};
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trim() != 'crossAxisAlignment: CrossAxisAlignment.stretch,') {
          continue;
        }
        // 该属性属于 Row 还是 Column？看它上面最近一次的 Row(/Column( 开启。
        if (_ownerOf(lines, i) != 'Row') continue;
        // 直接在行内包了 IntrinsicHeight 的（Row 前 1~3 行），不算裸站点。
        if (_hasIntrinsicHeightAbove(lines, i)) continue;
        found.add('${_rel(entity.path)}::${_enclosingClass(lines, i)}');
      }
    }

    final added = found.difference(_knownBareRowStretch);
    final removed = _knownBareRowStretch.difference(found);

    expect(
      added,
      isEmpty,
      reason: '发现新的「裸 Row(crossAxisAlignment: stretch)」站点：\n${added.join('\n')}\n'
          '无界高度下这类 Row 必崩（BoxConstraints forces an infinite height）。\n'
          '请在行内用 IntrinsicHeight 包住该 Row，或把该约束改到有界高度的父级里。',
    );
    expect(
      removed,
      isEmpty,
      reason: '以下站点已消失或已修复，请从 _knownBareRowStretch 里删除：\n${removed.join('\n')}',
    );
  });
}

/// 找到第 [i] 行 `crossAxisAlignment: ...` 所属的 widget 构造器名（`Row`/`Column`）。
String _ownerOf(List<String> lines, int i) {
  for (var j = i - 1; j >= 0 && j >= i - 4; j--) {
    final t = lines[j];
    // 只看开启语法的形态：`Row(` / `child: Row(` 之类。
    if (RegExp(r'\bRow\(').hasMatch(t)) return 'Row';
    if (RegExp(r'\bColumn\(').hasMatch(t)) return 'Column';
  }
  return '';
}

bool _hasIntrinsicHeightAbove(List<String> lines, int i) {
  for (var j = i - 1; j >= 0 && j >= i - 3; j--) {
    if (lines[j].contains('IntrinsicHeight(')) return true;
  }
  return false;
}

/// 第 [i] 行所属的顶层 class 名（向上找最近一个列 0 的 `class X`）。
String _enclosingClass(List<String> lines, int i) {
  for (var j = i - 1; j >= 0; j--) {
    final m = RegExp(r'^class\s+(\w+)').firstMatch(lines[j]);
    if (m != null) return m.group(1)!;
  }
  return '<unknown>';
}

String _rel(String path) {
  final norm = path.replaceAll(r'\', '/');
  final idx = norm.indexOf('lib/');
  return idx >= 0 ? norm.substring(idx + 4) : norm;
}
