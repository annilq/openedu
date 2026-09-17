import 'package:flutter_test/flutter_test.dart';
import 'package:kids_learn/features/export/domain/export_repository.dart';

void main() {
  group('ExportSheetRequest', () {
    test('bank 来源只带 ids，不带 child_id', () {
      final json = const ExportSheetRequest(source: 'bank', ids: ['a', 'b'])
          .toJson();
      expect(json, {
        'source': 'bank',
        'ids': ['a', 'b'],
        'due_only': false,
      });
    });

    test('wrong_book 来源带 child_id 与 due_only，title 缺省不下发', () {
      final json = const ExportSheetRequest(
        source: 'wrong_book',
        childId: 'child-1',
        dueOnly: true,
      ).toJson();
      expect(json['source'], 'wrong_book');
      expect(json['child_id'], 'child-1');
      expect(json['due_only'], true);
      expect(json.containsKey('title'), isFalse);
    });

    test('title 显式给出时下发', () {
      final json =
          const ExportSheetRequest(source: 'task', ids: ['t1'], title: '周末练习')
              .toJson();
      expect(json['title'], '周末练习');
    });
  });

  group('降级统计（ADR-0052：纸面按纯文本打印，须如实提示）', () {
    test('含公式或图片的题面被识别', () {
      expect(looksLikeRichText(r'计算 $1/2$'), isTrue);
      expect(looksLikeRichText('看图 ![示意图](http://x/y.png)'), isTrue);
      expect(looksLikeRichText('纯文本 1/2 + 1/2'), isFalse);
      expect(looksLikeRichText(null), isFalse);
      expect(looksLikeRichText(''), isFalse);
    });

    test('一道题的题干或任一选项命中即算一道', () {
      final count = countDowngradedQuestions(
        stems: ['纯文本', r'含公式 $x^2$', '也是纯文本'],
        optionLists: [
          ['A', 'B'],
          null,
          ['C', r'$\frac{1}{2}$'],
        ],
      );
      expect(count, 2);
    });

    test('空列表为 0', () {
      expect(countDowngradedQuestions(stems: const []), 0);
    });
  });

  group('软提示阈值', () {
    test('60 题以上建议分批（但不拦截）', () {
      expect(kExportSoftLimit, 60);
    });
  });
}
