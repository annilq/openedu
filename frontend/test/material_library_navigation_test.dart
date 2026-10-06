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
        MaterialFolderModel(id: 'b', name: '第一章', teacherFolderId: 'a');
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
      // teacherFolderId 显式写入：a 是根级目录，父为 null。
      expect(notifier.state.teacherFolderId, isNull);
      expect(notifier.state.materials.map((m) => m.id), ['m1']);
      expect(
        notifier.state.folders
            .where((f) => f.teacherFolderId == 'a')
            .map((f) => f.id),
        ['b'],
      );
    });

    test('点击「返回」(openFolder(b.teacherFolderId)) 回上层并改写 teacherFolderId',
        () async {
      when(() => repo.getMaterials(folderId: 'a'))
          .thenAnswer((_) async => [matInA]);
      when(() => repo.getMaterials(folderId: 'b'))
          .thenAnswer((_) async => <MaterialItemModel>[]);

      // 先进入 b（父为 a），再点返回回到 a：teacherFolderId 应随 a 重写。
      await notifier.openFolder('b');
      expect(notifier.state.currentFolderId, 'b');
      expect(notifier.state.teacherFolderId, 'a');

      await notifier.openFolder(notifier.state.teacherFolderId); // == 'a'

      expect(notifier.state.currentFolderId, 'a');
      expect(notifier.state.teacherFolderId, isNull); // a 是根级 → 父为 null
      expect(
        notifier.state.folders
            .where((f) => f.teacherFolderId == 'a')
            .map((f) => f.id),
        ['b'],
      );
    });

    test('根目录无上层：openFolder(null 的 teacher) 仍是根', () async {
      when(() => repo.getMaterials(folderId: null))
          .thenAnswer((_) async => [matRoot]);

      // 根目录的 teacherFolderId 为 null，点返回即回到根，不报错也不越界。
      await notifier.openFolder(rootFolder.teacherFolderId); // == null

      expect(notifier.state.currentFolderId, isNull);
      expect(notifier.state.teacherFolderId, isNull);
      expect(notifier.state.materials.map((m) => m.id), ['m0']);
    });

    test('从「根级子目录」点返回 → 回到根且 header 状态清空', () async {
      // 复现用户场景：进入根级目录 a（teacherFolderId=null），再点返回
      // （a.teacherFolderId=null）→ 应回到根；此时 currentFolderId/teacherFolderId
      // 都为 null，视图侧 folderById 必须返回 null（否则会残留返回键 + 目录名）。
      when(() => repo.getMaterials(folderId: 'a'))
          .thenAnswer((_) async => [matInA]);
      when(() => repo.getMaterials(folderId: null))
          .thenAnswer((_) async => [matRoot]);

      await notifier.openFolder('a');
      expect(notifier.state.currentFolderId, 'a');
      expect(notifier.state.teacherFolderId, isNull);

      await notifier.openFolder(notifier.state.teacherFolderId); // == null

      expect(notifier.state.currentFolderId, isNull);
      expect(notifier.state.teacherFolderId, isNull);
      // 视图契约：根目录时 folderById(null) 必须返回 null，head（返回键 + 目录名）才会隐藏。
      expect(notifier.state.folderById(notifier.state.currentFolderId), isNull);
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
      expect(notifier.state.teacherFolderId, 'a');
    });
  });
}
