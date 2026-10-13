// 场景规格的**类型化与单一解析入口**（ADR-0091 ticket 04）。
//
// 守三件事：
// 1. SceneSpec 是一个**类型**（此前前端只有裸 Map），新形直读：几何在 `figure` 里、
//    选项组是 `options[]` 的图形数组；
// 2. **旧形被拒绝**（决策 5：不做双读）——顶层 `points` / `optionGroup` 一律读不出
//    几何，而不是被静默适配成旧形；
// 3. 身份键随几何一起进来（`figure.key`），解析不臆造：没有 key 的图形不入列。
//
// 纯单元：不挂 widget（形状是数据契约，挂载对它没有牙齿）。
import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/shared/domain/figures.dart';
import 'package:kids_learn/shared/domain/scene_spec.dart';

/// 一份**新形** spec：主图形 + 两个选项图形。
Map<String, dynamic> _newSpec() => <String, dynamic>{
      'kind': 'reflection',
      'figure': <String, dynamic>{
        'key': 'para',
        'label': '平行四边形',
        'points': <List<double>>[
          <double>[0.30, 0.40],
          <double>[0.70, 0.40],
          <double>[0.82, 0.70],
          <double>[0.42, 0.70],
        ],
        'edges': <List<int>>[
          <int>[0, 1],
          <int>[1, 2],
          <int>[2, 3],
          <int>[3, 0],
        ],
      },
      'options': <Map<String, dynamic>>[
        <String, dynamic>{
          'key': 'square',
          'label': '正方形',
          'points': <List<double>>[
            <double>[0.28, 0.28],
            <double>[0.72, 0.28],
            <double>[0.72, 0.72],
            <double>[0.28, 0.72],
          ],
          'edges': <List<int>>[
            <int>[0, 1],
            <int>[1, 2],
            <int>[2, 3],
            <int>[3, 0],
          ],
        },
      ],
      'curated': false,
    };

void main() {
  group('新形直读', () {
    test('kind 与主图形（几何在 figure 里，不是顶层）', () {
      final spec = SceneSpec.tryParse(_newSpec())!;
      expect(spec.kind, 'reflection');
      expect(spec.figure!.key, 'para');
      expect(spec.figure!.label, '平行四边形');
      expect(spec.figure!.vertices.length, 4);
      expect(spec.figure!.vertices.first.x, 0.30);
      expect(spec.figure!.vertices.last.y, 0.70);
    });

    test('连接关系随几何进来（与后端 Figure 同构，不再只有顶点）', () {
      final spec = SceneSpec.tryParse(_newSpec())!;
      expect(spec.figure!.edges, <List<int>>[
        <int>[0, 1],
        <int>[1, 2],
        <int>[2, 3],
        <int>[3, 0],
      ]);
      expect(spec.options.single.edges, hasLength(4));
    });

    test('optionGroup 那层嵌套没了：options 就是图形数组', () {
      final spec = SceneSpec.tryParse(_newSpec())!;
      expect(spec.options, hasLength(1));
      expect(spec.options.single.key, 'square');
      // 顺序 = 数组顺序（顺序就是编排意图），解析不得重排。
      expect(spec.options.single.label, '正方形');
      expect(spec.curated, isFalse);
    });

    test('curated 显式开关被读到', () {
      final raw = _newSpec()..['curated'] = true;
      expect(SceneSpec.tryParse(raw)!.curated, isTrue);
    });

    test('缺 edges 时按顶点顺序闭合（不是留空）', () {
      final raw = _newSpec();
      (raw['figure'] as Map).remove('edges');
      final spec = SceneSpec.tryParse(raw)!;
      expect(spec.figure!.edges, closedEdges(4));
    });

    test('顶点不足 3 个 / 无 key 的图形不入列（不臆造身份）', () {
      final raw = <String, dynamic>{
        'kind': 'reflection',
        'figure': <String, dynamic>{
          'key': 'degenerate',
          'points': <List<double>>[
            <double>[0.1, 0.1],
            <double>[0.2, 0.2],
          ],
        },
        'options': <Map<String, dynamic>>[
          <String, dynamic>{
            'label': '没有身份键',
            'points': <List<double>>[
              <double>[0.1, 0.1],
              <double>[0.9, 0.1],
              <double>[0.5, 0.9],
            ],
          },
        ],
      };
      final spec = SceneSpec.tryParse(raw)!;
      expect(spec.figure, isNull);
      expect(spec.options, isEmpty);
    });

    test('toJson 与新形同形（可回写课件草稿 / 知识点）', () {
      final json = SceneSpec.tryParse(_newSpec())!.toJson();
      expect(json['kind'], 'reflection');
      expect((json['figure'] as Map)['key'], 'para');
      expect((json['options'] as List), hasLength(1));
      expect(json.containsKey('optionGroup'), isFalse);
      // 往返：写出去的还能读回来。
      expect(SceneSpec.tryParse(json)!.figure!.key, 'para');
    });
  });

  group('旧形被拒绝（不做双读）', () {
    test('顶层 points / edges 不再是几何（一律读不到 figure）', () {
      final legacy = <String, dynamic>{
        'kind': 'reflection',
        'points': <List<double>>[
          <double>[0.20, 0.80],
          <double>[0.80, 0.80],
          <double>[0.50, 0.30],
        ],
        'edges': <List<int>>[
          <int>[0, 1],
          <int>[1, 2],
          <int>[2, 0],
        ],
      };
      final spec = SceneSpec.tryParse(legacy)!;
      expect(spec.figure, isNull, reason: '旧形不被适配成新形（决策 5）');
      expect(spec.options, isEmpty);
    });

    test('optionGroup 不被识别为选项组', () {
      final legacy = <String, dynamic>{
        'kind': 'reflection',
        'optionGroup': <String, dynamic>{
          'curated': true,
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'label': 'A',
              'caption': '房子',
              'points': <List<double>>[
                <double>[0.30, 0.70],
                <double>[0.70, 0.70],
                <double>[0.50, 0.25],
              ],
            },
          ],
        },
      };
      final spec = SceneSpec.tryParse(legacy)!;
      expect(spec.options, isEmpty);
      expect(spec.curated, isFalse);
    });

    test('不是一份 spec（无 kind / 不是 Map）→ null（连空态都不由解释器背）', () {
      expect(SceneSpec.tryParse(null), isNull);
      expect(SceneSpec.tryParse(<String, dynamic>{'points': []}), isNull);
      expect(SceneSpec.tryParse('reflection'), isNull);
    });
  });
}
