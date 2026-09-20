import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/home/domain/expected_question_count.dart';
import 'package:kids_learn/shared/domain/models/models.dart';

TaskSpecModel spec(int count) => TaskSpecModel(
      subject: '数学',
      grade: 2,
      knowledgePoint: '两位数加减法',
      qtype: 'calc',
      count: count,
    );

void main() {
  group('expectedQuestionCount', () {
    test('空规格 → 0（未知，调用方不得当作「应出 0 题」）', () {
      expect(expectedQuestionCount(const []), 0);
    });

    test('多条规格按 count 求和', () {
      expect(expectedQuestionCount([spec(5), spec(3)]), 8);
    });

    test('单条 0 题不影响其它条', () {
      expect(expectedQuestionCount([spec(0), spec(4)]), 4);
    });
  });

  group('isUnderdelivered', () {
    test('实际不足即少题', () {
      expect(isUnderdelivered(expected: 8, actualCount: 6), isTrue);
    });

    test('刚好出齐不算少题', () {
      expect(isUnderdelivered(expected: 8, actualCount: 8), isFalse);
    });

    test('应出题数未知（0）时不判少题——未知不能冒充故障', () {
      expect(isUnderdelivered(expected: 0, actualCount: 0), isFalse);
      expect(isUnderdelivered(expected: 0, actualCount: 10), isFalse);
    });
  });
}
