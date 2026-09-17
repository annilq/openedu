// 守卫（ADR-0045）：内容宽度上限只有一个出口 —— AppContentFrame。
//
// 此前全仓 14 处手抄同一段 `Align` + `ConstrainedBox(maxWidth: contentWide)`，
// 各自微调（壳用 topCenter、页面用 topLeft）。手抄的代价不是重复，而是改一次宽度
// 要记得改十几处，漏一处就是某张页面独自变宽——而且不会报错，只是「看起来不太一样」。
//
// 这条守卫把「各自手抄」挡回去：要么用 AppContentFrame，要么就别用这个宽度令牌。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('内容宽度出口唯一（ADR-0045）', () {
    test('lib/ 下不得再手写 contentWide 约束', () {
      final lib = Directory('lib');
      if (!lib.existsSync()) {
        // 测试须在包根目录运行（flutter test 的默认 cwd）。
        fail('找不到 lib/：请在 frontend/ 下运行');
      }

      // Align + ConstrainedBox(contentWide) 的各种换行写法。
      final handWritten = RegExp(
        r'ConstrainedBox\s*\(\s*constraints:\s*const\s+BoxConstraints\(\s*maxWidth:\s*AppLayout\.contentWide\s*\)',
        multiLine: true,
      );

      final offenders = <String>[];
      for (final entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        if (handWritten.hasMatch(src)) offenders.add(entity.path);
      }

      expect(
        offenders,
        isEmpty,
        reason: '宽度上限请统一走 AppContentFrame（或 AppPushedPage）。'
            '直接手写 Align + ConstrainedBox 会让 contentWide 散落在多处，'
            '改宽度时必漏。违规文件：$offenders',
      );
    });

    test('AppContentFrame 自己不被误当成违规实现', () {
      // 上一条守卫禁止的是「使用者」；定义处当然要用 ConstrainedBox。
      final frame = File('lib/shared/widgets/app_content_frame.dart');
      expect(frame.existsSync(), isTrue);
      expect(frame.readAsStringSync(), contains('class AppContentFrame'));
    });
  });
}
