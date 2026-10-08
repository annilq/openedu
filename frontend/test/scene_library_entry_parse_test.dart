import 'package:flutter_test/flutter_test.dart';
import 'package:kids_learn/features/home/domain/repositories/material_repository.dart';

/// T03（ADR-0074）：前端模型须解析后端下发的 `default_figure_key`，
/// 缺省回落 null（与现状一致）。这是「库默认图形」能落到 UI 的前提。
void main() {
  test('SceneLibraryEntry 解析 default_figure_key', () {
    final e = SceneLibraryEntry.fromJson({
      'kind': 'reflection',
      'title': '轴对称',
      'defaults': <String, dynamic>{},
      'associated_knowledge_points': <dynamic>[],
      'instance_count': 0,
      'default_figure_key': 'house',
    });
    expect(e.defaultFigureKey, 'house');
  });

  test('default_figure_key 缺失回落 null（与现状一致）', () {
    final e = SceneLibraryEntry.fromJson({
      'kind': 'reflection',
      'title': '轴对称',
      'defaults': <String, dynamic>{},
    });
    expect(e.defaultFigureKey, isNull);
  });
}
