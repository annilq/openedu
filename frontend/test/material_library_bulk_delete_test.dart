import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kids_learn/features/materials/domain/repositories/material_library_repository.dart';
import 'package:kids_learn/features/materials/providers/material_library_provider.dart';

class _MockRepo extends Mock implements MaterialLibraryRepository {}

void main() {
  group('MaterialLibraryNotifier 多选删除', () {
    late _MockRepo repo;
    late MaterialLibraryNotifier notifier;

    final m1 = MaterialItemModel(id: 'm1', name: '甲');
    final m2 = MaterialItemModel(id: 'm2', name: '乙');
    final folderA = MaterialFolderModel(id: 'a', name: '目录A');

    setUp(() {
      repo = _MockRepo();
      when(() => repo.getFolders()).thenAnswer((_) async => [folderA]);
      when(() => repo.getMaterials(folderId: any(named: 'folderId')))
          .thenAnswer((_) async => [m1, m2]);
      when(() => repo.bulkDeleteMaterials(any(), cascadeKnowledgePoints: any(named: 'cascadeKnowledgePoints')))
          .thenAnswer((_) async => {
                'deleted': true,
                'deleted_count': 1,
                'chunks_removed': 0,
                'knowledge_points_removed': 2,
              });
      notifier = MaterialLibraryNotifier(repo);
    });

    test('进入多选态清空旧勾选；全选后取消全选', () async {
      await notifier.load();
      notifier.enterSelecting();
      expect(notifier.state.selecting, isTrue);
      expect(notifier.state.selectedMaterialIds, isEmpty);

      notifier.toggleSelectAllMaterials();
      expect(notifier.state.selectedMaterialIds, {'m1', 'm2'});

      notifier.toggleMaterialSelection('m1');
      expect(notifier.state.selectedMaterialIds, {'m2'});
      expect(notifier.state.selecting, isTrue, reason: '单选不改多选态');

      // 部分选中时「全选」= 补齐全部（而不是取消）
      notifier.toggleSelectAllMaterials();
      expect(notifier.state.selectedMaterialIds, {'m1', 'm2'});
      notifier.toggleSelectAllMaterials();
      expect(notifier.state.selectedMaterialIds, isEmpty,
        reason: '已全选再点 = 取消全选');
    });

    test('未进入多选态时 toggle 也能勾选（勾选框可单独点）', () async {
      await notifier.load();
      notifier.toggleMaterialSelection('m1');
      expect(notifier.state.selectedMaterialIds, {'m1'});
      expect(notifier.state.selecting, isFalse);
    });

    test('批量删除：带上全部勾选 id，删完退出多选并报告知识点清理数', () async {
      await notifier.load();
      notifier.enterSelecting();
      notifier.toggleSelectAllMaterials();

      await notifier.bulkDeleteMaterials();

      verify(
        () => repo.bulkDeleteMaterials(
          ['m1', 'm2'],
          cascadeKnowledgePoints: true,
        ),
      ).called(1);
      expect(notifier.state.selecting, isFalse, reason: '删完必须退出多选态');
      expect(notifier.state.selectedMaterialIds, isEmpty);
      expect(notifier.state.notice, contains('已删除 1 份资料'));
      expect(notifier.state.notice, contains('清理 2 个不再被引用的知识点'));
    });

    test('空勾选不发起请求', () async {
      await notifier.load();
      notifier.enterSelecting();
      await notifier.bulkDeleteMaterials();
      verifyNever(() => repo.bulkDeleteMaterials(any(),
          cascadeKnowledgePoints: any(named: 'cascadeKnowledgePoints')));
    });

    test('删除失败保留勾选：教师可直接重试或改选', () async {
      when(() => repo.bulkDeleteMaterials(any(),
              cascadeKnowledgePoints: any(named: 'cascadeKnowledgePoints')))
          .thenThrow(Exception('网络断了'));
      await notifier.load();
      notifier.enterSelecting();
      notifier.toggleMaterialSelection('m1');

      await notifier.bulkDeleteMaterials();

      expect(notifier.state.selectedMaterialIds, {'m1'}, reason: '失败不该丢勾选');
      expect(notifier.state.selecting, isTrue);
      expect(notifier.state.error, contains('删除失败'));
    });

    test('切换目录后看不见的勾选被裁掉（不会误删别的目录资料）', () async {
      final other1 = MaterialItemModel(id: 'o1', name: '别处甲');
      when(() => repo.getMaterials(folderId: 'a')).thenAnswer((_) async => [m1]);
      when(() => repo.getMaterials(folderId: null))
          .thenAnswer((_) async => [other1]);

      await notifier.openFolder('a');
      notifier.enterSelecting();
      notifier.toggleMaterialSelection('m1');
      expect(notifier.state.selectedMaterialIds, {'m1'});

      // 回到根目录：m1 已不在可见列表里，勾选必须随之消失。
      await notifier.openFolder(null);
      expect(notifier.state.selectedMaterialIds, isEmpty);
      expect(notifier.state.selecting, isTrue, reason: '仍处多选态，只是没勾任何东西');
    });
  });
}
