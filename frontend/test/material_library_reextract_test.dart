import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kids_learn/features/materials/domain/repositories/material_library_repository.dart';
import 'package:kids_learn/features/materials/providers/material_library_provider.dart';

class _MockRepo extends Mock implements MaterialLibraryRepository {}

/// 提取失败必须在界面上响（资料库页 notice）。
///
/// 背景：重新提取 / 上传曾把响应顶层的 extraction 四态丢掉，失败也显示
/// 「元数据已更新」——教师照常去点「溯源」，依旧查不到片段，还以为是功能坏了。
void main() {
  group('MaterialLibraryNotifier 提取四态提示', () {
    late _MockRepo repo;
    late MaterialLibraryNotifier notifier;

    final material = const MaterialItemModel(
      id: 'm1',
      name: '数学教材.txt',
      knowledgePoints: ['两位数乘法'],
      textLength: 42000,
    );

    setUp(() {
      repo = _MockRepo();
      when(() => repo.getFolders()).thenAnswer((_) async => []);
      when(() => repo.getMaterials(folderId: any(named: 'folderId')))
          .thenAnswer((_) async => [material]);
      notifier = MaterialLibraryNotifier(repo);
    });

    test('重新提取成功：提示已更新并带出知识点数', () async {
      when(() => repo.reextract('m1')).thenAnswer(
        (_) async => MaterialExtractResult(
          material: material,
          extraction: 'extracted',
        ),
      );

      await notifier.reextract('m1');

      expect(notifier.state.notice, contains('元数据已更新'));
      expect(notifier.state.notice, contains('1 个知识点'));
    });

    test('重新提取失败：提示必须带上失败原因，不能伪装成已更新', () async {
      when(() => repo.reextract('m1')).thenAnswer(
        (_) async => MaterialExtractResult(
          material: material,
          extraction: 'failed',
          error: 'AI 提取失败：provider request failed (auth)',
        ),
      );

      await notifier.reextract('m1');

      expect(notifier.state.notice, contains('重新提取未完成'));
      expect(notifier.state.notice, contains('auth'));
      expect(notifier.state.notice, isNot(contains('元数据已更新')));
    });

    test('上传时提取失败：资料仍入库，但提示说明元数据未提取', () async {
      when(() => repo.upload(
            filename: any(named: 'filename'),
            bytes: any(named: 'bytes'),
            folderId: any(named: 'folderId'),
          )).thenAnswer(
        (_) async => MaterialExtractResult(
          material: material,
          extraction: 'skipped_no_engine',
          error: '未配置 AI 模型，请在「模型管理」中添加并设为默认',
        ),
      );

      await notifier.upload(filename: '数学教材.txt', bytes: [1, 2, 3]);

      expect(notifier.state.notice, contains('元数据提取未完成'));
      expect(notifier.state.notice, contains('模型管理'));
      expect(notifier.state.notice, isNot(contains('向量化后参与出题')));
    });

    test('上传且提取成功：保持原有提示口径', () async {
      when(() => repo.upload(
            filename: any(named: 'filename'),
            bytes: any(named: 'bytes'),
            folderId: any(named: 'folderId'),
          )).thenAnswer(
        (_) async =>
            MaterialExtractResult(material: material, extraction: 'extracted'),
      );

      await notifier.upload(filename: '数学教材.txt', bytes: [1, 2, 3]);

      expect(notifier.state.notice, contains('已上传'));
      expect(notifier.state.notice, contains('向量化后参与出题'));
    });
  });
}
