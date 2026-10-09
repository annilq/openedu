import 'package:flutter_test/flutter_test.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_practice_block.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_section.dart';

/// 练习内容块 / 环节解析对历史 AI 起草数据的容错（修复「type List is not subtype of
/// string」：旧数据把 practice 的 `hints` 存成字符串数组，新数据（toJson）是单串，
/// 解析层两种都要吃得下，否则单条脏记录会拖垮整份课件列表）。
void main() {
  group('CoursewarePracticeBlock.fromJson 容错', () {
    test('hints 为字符串数组 → 收敛为多行字符串', () {
      final block = CoursewarePracticeBlock.fromJson(<String, dynamic>{
        'qtype': 'choice',
        'count': 3,
        'hints': <dynamic>[
          '先确定亿级数位，再按位读数',
          '注意：亿级数前面的零不读',
        ],
      });
      expect(block.qtype, 'choice');
      expect(block.count, 3);
      expect(
        block.hints,
        '先确定亿级数位，再按位读数\n注意：亿级数前面的零不读',
        reason: 'List 版 hints 被压平成了字符串却没合并',
      );
    });

    test('hints 为单串 → 原样保留', () {
      final block = CoursewarePracticeBlock.fromJson(<String, dynamic>{
        'qtype': 'fill',
        'hints': '提示文案',
      });
      expect(block.hints, '提示文案');
      expect(block.qtype, 'fill');
      expect(block.count, 3);
    });

    test('qtype / hints 缺失或类型异常 → 安全回落，不抛 CastError', () {
      final block = CoursewarePracticeBlock.fromJson(<String, dynamic>{
        'count': '5', // 字符串版 count
      });
      expect(block.qtype, 'choice');
      expect(block.count, 5);
      expect(block.hints, '');
    });
  });

  group('CoursewareSectionModel.fromJson 容错', () {
    test('旧 payload 带 List 版 hints 的环节能解析，不再抛 List→String', () {
      // 复刻用户库里那条炸列表的真实结构：payload 内嵌 qtype + List hints + options。
      final json = <String, dynamic>{
        'id': 's3',
        'title': '练习',
        'script': '试一试',
        'script_segments': <dynamic>[],
        'payload': <String, dynamic>{
          'qtype': 'choice',
          'count': 3,
          'hints': <dynamic>['提示一', '提示二'],
          'options': <dynamic>[],
        },
        'materials': <dynamic>[],
        'scene': null,
      };

      CoursewareSectionModel? section;
      expect(
        () => section = CoursewareSectionModel.fromJson(json),
        returnsNormally,
        reason: '旧数据 List 版 hints 让整份课件列表崩溃',
      );
      expect(section, isNotNull);
      expect(section!.practice, isNotNull);
      expect(
        section!.practice!.hints,
        '提示一\n提示二',
      );
    });
  });
}
