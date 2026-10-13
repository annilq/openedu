import 'package:flutter_test/flutter_test.dart';
import 'package:kids_learn/shared/domain/models/quiz_option.dart';

/// [QuizOption] tolerant 解析契约（ADR-0089-04）：后端选项既可能下发纯字符串
/// （老数据 / 旧端点），也可能是 `{text, figure?}` 新形。两者都必须零回归地落进
/// 同一个模型——解析是「旧形仍可用」的唯一保险，必须有断言钉住。
void main() {
  group('QuizOption.parse', () {
    test('纯字符串 → 带空图形的选项（不臆造几何）', () {
      final o = QuizOption.parse('A. 房子');
      expect(o.text, 'A. 房子');
      expect(o.figure, isNull);
    });

    test('null → 纯文字空选项', () {
      final o = QuizOption.parse(null);
      expect(o.text, '');
      expect(o.figure, isNull);
    });

    test('新形 {text, figure} → 解析出几何', () {
      final o = QuizOption.parse(<String, dynamic>{
        'text': 'A. 正方形',
        'figure': <String, dynamic>{
          'key': 'square',
          'label': '正方形',
          'points': <List<double>>[
            [0.0, 0.0],
            [1.0, 0.0],
            [1.0, 1.0],
            [0.0, 1.0],
          ],
          'edges': <List<int>>[
            [0, 1],
            [1, 2],
            [2, 3],
            [3, 0],
          ],
        },
      });
      expect(o.text, 'A. 正方形');
      expect(o.figure, isNotNull);
      expect(o.figure!.key, 'square');
      expect(o.figure!.vertices.length, 4);
    });

    test('新形无 figure → 纯文字选项', () {
      final o = QuizOption.parse(<String, dynamic>{'text': 'B. 风筝'});
      expect(o.text, 'B. 风筝');
      expect(o.figure, isNull);
    });
  });

  group('QuizOption.parseList', () {
    test('null / 非 List → null', () {
      expect(QuizOption.parseList(null), isNull);
      expect(QuizOption.parseList(42), isNull);
    });

    test('字符串列表逐项转纯文字选项', () {
      final list = QuizOption.parseList(['A. x', 'B. y']);
      expect(list, hasLength(2));
      expect(list!.every((o) => o.figure == null), isTrue);
      expect(list[0].text, 'A. x');
    });

    test('混合形列表：有 figure 的解析几何、没的落纯文字', () {
      final list = QuizOption.parseList(<dynamic>[
        'A. 纯文字',
        <String, dynamic>{
          'text': 'B. 正方形',
          'figure': <String, dynamic>{
            'key': 'square',
            'label': '正方形',
            'points': <List<double>>[
              [0.0, 0.0],
              [1.0, 0.0],
              [1.0, 1.0],
              [0.0, 1.0],
            ],
          },
        },
      ]);
      expect(list, hasLength(2));
      expect(list![0].figure, isNull);
      expect(list[1].figure!.key, 'square');
    });
  });

  group('QuizOption.toJson', () {
    test('纯文字选项 → {text}', () {
      expect(const QuizOption(text: 'A. 房子').toJson(), {'text': 'A. 房子'});
    });

    test('带图形 → {text, figure}', () {
      final o = QuizOption.parse(<String, dynamic>{
        'text': 'A. 正方形',
        'figure': <String, dynamic>{
          'key': 'square',
          'label': '正方形',
          'points': <List<double>>[
            [0.0, 0.0],
            [1.0, 0.0],
            [1.0, 1.0],
            [0.0, 1.0],
          ],
          'edges': <List<int>>[
            [0, 1],
            [1, 2],
            [2, 3],
            [3, 0],
          ],
        },
      });
      final json = o.toJson();
      expect(json['text'], 'A. 正方形');
      expect(json['figure'], isNotNull);
      expect(json['figure']['key'], 'square');
      // 回写再解析应等价（几何不丢）。
      final round = QuizOption.parse(json);
      expect(round.figure!.key, 'square');
      expect(round.figure!.vertices.length, 4);
    });
  });
}
