import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kids_learn/features/materials/domain/repositories/material_library_repository.dart';
import 'package:kids_learn/features/materials/providers/material_library_provider.dart';

class _MockRepo extends Mock implements MaterialLibraryRepository {}

void main() {
  group('MaterialLibraryNotifier 目录导航', () {
    late _MockRepo repo;
    late MaterialLibraryNotifier notifier;

    // 结构：根 ── 4年级数学上册(a) ── 第一章(b)
    final rootFolder =
        MaterialFolderModel(id: 'a', name: '4年级数学上册');
    final subFolder =
        MaterialFolderModel(id: 'b', name: '第一章', parentFolderId: 'a');
    final matInA = MaterialItemModel(id: 'm1', name: '练习册', folderId: 'a');
    final matRoot =
        MaterialItemModel(id: 'm0', name: '通用资料', folderId: null);

    setUp(() {
      repo = _MockRepo();
      notifier = MaterialLibraryNotifier(repo);
      when(() => repo.getFolders())
          .thenAnswer((_) async => [rootFolder, subFolder]);
    });

    test('openFolder(子目录) 后只显示该目录的资料与其直接子目录', () async {
      when(() => repo.getMaterials(folderId: 'a'))
          .thenAnswer((_) async => [matInA]);

      await notifier.openFolder('a');

      expect(notifier.state.currentFolderId, 'a');
      // parentFolderId 显式写入：a 是根级目录，父为 null。
      expect(notifier.state.parentFolderId, isNull);
      expect(notifier.state.materials.map((m) => m.id), ['m1']);
      expect(
        notifier.state.folders
            .where((f) => f.parentFolderId == 'a')
            .map((f) => f.id),
        ['b'],
      );
    });

    test('点击「返回」(openFolder(b.parentFolderId)) 回上层并改写 parentFolderId',
        () async {
      when(() => repo.getMaterials(folderId: 'a'))
          .thenAnswer((_) async => [matInA]);
      when(() => repo.getMaterials(folderId: 'b'))
          .thenAnswer((_) async => <MaterialItemModel>[]);

      // 先进入 b（父为 a），再点返回回到 a：parentFolderId 应随 a 重写。
      await notifier.openFolder('b');
      expect(notifier.state.currentFolderId, 'b');
      expect(notifier.state.parentFolderId, 'a');

      await notifier.openFolder(notifier.state.parentFolderId); // == 'a'

      expect(notifier.state.currentFolderId, 'a');
      expect(notifier.state.parentFolderId, isNull); // a 是根级 → 父为 null
      expect(
        notifier.state.folders
            .where((f) => f.parentFolderId == 'a')
            .map((f) => f.id),
        ['b'],
      );
    });

    test('根目录无上层：openFolder(null 的 parent) 仍是根', () async {
      when(() => repo.getMaterials(folderId: null))
          .thenAnswer((_) async => [matRoot]);

      // 根目录的 parentFolderId 为 null，点返回即回到根，不报错也不越界。
      await notifier.openFolder(rootFolder.parentFolderId); // == null

      expect(notifier.state.currentFolderId, isNull);
      expect(notifier.state.parentFolderId, isNull);
      expect(notifier.state.materials.map((m) => m.id), ['m0']);
    });

    test('并发 load 守卫：后发起的 load 结果不被早发慢请求覆盖', () async {
      // a 先发起但慢，b 后发起但快：最终 currentFolderId 必须是 b（后者胜出）。
      when(() => repo.getFolders())
          .thenAnswer((_) async => [rootFolder, subFolder]);
      when(() => repo.getMaterials(folderId: 'a'))
          .thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return [matInA];
      });
      when(() => repo.getMaterials(folderId: 'b'))
          .thenAnswer((_) async => <MaterialItemModel>[]);

      final slow = notifier.openFolder('a');
      final fast = notifier.openFolder('b');
      await Future.wait([slow, fast]);

      expect(notifier.state.currentFolderId, 'b');
      expect(notifier.state.parentFolderId, 'a');
    });
  });
}
