import 'package:flutter_test/flutter_test.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_section.dart';

/// 环节场景的持久化语义（ADR-0076 · ticket 01：证伪票）。
///
/// 全案（02–05）建立在一条前提上：环节的 `scene` 是**透传的裸 Map**——教师编排的
/// 一组图形（`optionGroup`：`curated` + 有序 `items`，条目内 `points` 是展开好的
/// 二维顶点）在模型层进出不丢键、不重排、不被 `??` 吞掉显式清空。
///
/// 本文件只验证不做功能：只打模型层的公开接缝（`fromJson` / `toJson` / `copyWith`），
/// 不引入编辑器 UI、不改渲染层、不改后端。
void main() {
  /// 一组有序图形（课件编排）。顺序即数组顺序，教学意图落在顺序里，故刻意排成
  /// 非字母序——若模型层重排过，顺序断言就会红。
  ///
  /// 条目形状 == 后端 `extract_option_group` 的产物（label / caption / points /
  /// edges），**没有**图库 key、**没有** axis 字段（ADR-0083 决策 2/6）。
  final items = <Map<String, dynamic>>[
    {
      'label': '',
      'caption': '长方形',
      'points': <List<double>>[
        <double>[-80, -50],
        <double>[80, -50],
        <double>[80, 50],
        <double>[-80, 50],
      ],
      'edges': <List<int>>[
        <int>[0, 1],
        <int>[1, 2],
        <int>[2, 3],
        <int>[3, 0],
      ],
    },
    {
      'label': '',
      'caption': '正方形',
      'points': <List<double>>[
        <double>[-60, -60],
        <double>[60, -60],
        <double>[60, 60],
        <double>[-60, 60],
      ],
      'edges': <List<int>>[
        <int>[0, 1],
        <int>[1, 2],
        <int>[2, 3],
        <int>[3, 0],
      ],
    },
    {
      'label': '',
      'caption': '箭头',
      'points': <List<double>>[
        <double>[-40, 0],
        <double>[10, 0],
        <double>[10, -40],
        <double>[60, 40],
      ],
      'edges': <List<int>>[
        <int>[0, 1],
        <int>[1, 2],
        <int>[2, 3],
        <int>[3, 0],
      ],
    },
  ];

  Map<String, dynamic> sceneWithGroup() => <String, dynamic>{
        'kind': 'reflection',
        'title': '哪些对折后能重合',
        'optionGroup': <String, dynamic>{'curated': true, 'items': items},
      };

  group('scene 往返', () {
    test('toJson → fromJson 后 curated / items / points / 顺序全部保持', () {
      final section = CoursewareSectionModel(
        id: 's1',
        title: '一组图形',
        script: '这些图形有什么共同点？',
        scene: sceneWithGroup(),
      );

      final back = CoursewareSectionModel.fromJson(section.toJson());

      final group = back.scene!['optionGroup'] as Map<String, dynamic>;
      expect(group['curated'], isTrue, reason: 'curated 开关被剥掉了');

      final got = group['items'] as List<dynamic>;
      expect(got.length, items.length);
      expect(
        got.map((e) => (e as Map<String, dynamic>)['caption']).toList(),
        <String>['长方形', '正方形', '箭头'],
        reason: '条目顺序被重排过（教学编排意图就落在顺序里）',
      );

      for (var i = 0; i < items.length; i++) {
        final want = items[i];
        final e = got[i] as Map<String, dynamic>;
        expect(e['label'], '');
        expect(e['caption'], want['caption']);
        // points 必须是二维顶点数组：非空、没被压平成字符串
        final points = e['points'];
        expect(points, isA<List>(), reason: 'points 被改写成了 ${points.runtimeType}');
        expect((points as List).length, (want['points'] as List).length);
        for (final v in points) {
          expect(v, isA<List>(), reason: '顶点被压平了：$v');
          expect((v as List).length, 2);
        }
        expect(points, want['points']);
        expect(e['edges'], want['edges']);
      }
    });

    test('没有 scene 的环节往返后仍是 null（不臆造）', () {
      const section = CoursewareSectionModel(
        id: 's1',
        title: '一组图形',
      );

      final back = CoursewareSectionModel.fromJson(section.toJson());
      expect(back.scene, isNull);
      expect(back.resolvedScene, isNull);
    });
  });

  group('copyWith 的哨兵语义', () {
    test('不传 scene 时保留原值', () {
      final section = CoursewareSectionModel(
        id: 's1',
        scene: sceneWithGroup(),
      );

      final kept = section.copyWith(title: '改个标题');

      expect(kept.title, '改个标题');
      expect(kept.scene, isNotNull);
      expect(
        (kept.scene!['optionGroup'] as Map<String, dynamic>)['curated'],
        isTrue,
      );
    });

    test('copyWith(scene: null) 真的把 scene 清成 null（显式清空不被吞）', () {
      final section = CoursewareSectionModel(
        id: 's1',
        scene: sceneWithGroup(),
      );
      expect(section.resolvedScene, isNotNull, reason: '前置：先有场景');

      final cleared = section.copyWith(scene: null);

      expect(cleared.scene, isNull, reason: '显式清空被吞了（旧值被保留）');
      expect(cleared.resolvedScene, isNull);
      // 清空要落得出去：后端收到的这份 JSON 里 scene 必须是 null
      expect(cleared.toJson()['scene'], isNull);
      expect(cleared.toJson().containsKey('scene'), isTrue);
    });
  });
}
