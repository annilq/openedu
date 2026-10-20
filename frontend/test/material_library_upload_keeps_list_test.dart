// 资料库「上传中不隐藏已上传列表」回归（用户实测：上传资料时页面空白
// loading、已上传的列表不显示）。
//
// 根因：视图曾把 `state.loading` 为真的整个列表区替换成居中 AppLoading，
// 而上传 / 向量化 / 删除 / 移动每个动作都会经历一段 loading → 已上传的
// 资料集体从屏上消失，页面像坏了一样。现行为：有内容时列表常驻屏上，
// 只在列表上方挂「正在刷新…」行内提示；只有首屏 / 空目录（确实什么都
// 还没有）才走整块转圈。
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as loc;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/widgets/teacher/material_library_view.dart';
import 'package:kids_learn/features/materials/domain/repositories/material_library_repository.dart';
import 'package:kids_learn/features/materials/providers/material_library_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_loading.dart';

/// 可控 future 的假仓库：[upload] 挂起直到 [uploadGate] 被补完，用来在
/// 「上传在飞」窗口里断言界面；[gateMaterials] 为真时 getMaterials 挂起直到
/// [materialsGate] 被补完，用来观测首屏空列表的加载态。
class _FakeRepo implements MaterialLibraryRepository {
  _FakeRepo({this.materials = const [], this.gateMaterials = false});

  final List<MaterialItemModel> materials;
  final bool gateMaterials;
  final Completer<void> materialsGate = Completer<void>();
  final Completer<MaterialExtractResult> uploadGate =
      Completer<MaterialExtractResult>();

  @override
  Future<List<MaterialFolderModel>> getFolders() async => const [];

  @override
  Future<void> createFolder({
    required String name,
    String? teacherFolderId,
    String? subject,
    int? grade,
    String? semester,
  }) async {}

  @override
  Future<void> deleteFolder(String folderId) async {}

  @override
  Future<List<MaterialItemModel>> getMaterials({String? folderId}) async {
    if (gateMaterials) await materialsGate.future;
    return materials;
  }

  @override
  Future<MaterialExtractResult> upload({
    required String filename,
    required List<int> bytes,
    String? folderId,
  }) =>
      uploadGate.future;

  @override
  Future<MaterialItemModel> vectorize(String materialId) async =>
      throw UnimplementedError();

  @override
  Future<MaterialExtractResult> reextract(String materialId) async =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> bulkDeleteMaterials(
    List<String> ids, {
    bool cascadeKnowledgePoints = false,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteMaterial(String materialId) async {}

  @override
  Future<MaterialItemModel> moveMaterial(
          String materialId, String? folderId) async =>
      throw UnimplementedError();

  @override
  Future<MaterialFolderModel> updateFolder(
    String folderId, {
    String? name,
    String? subject,
    int? grade,
    String? semester,
    String? teacherFolderId,
  }) async =>
      throw UnimplementedError();
}

const _existing = MaterialItemModel(id: 'm1', name: '数学教材.txt');

/// 起资料库页；[settle] 为假时只泵一帧（用于观测挂起中的加载态——加载中的
/// 转圈是无限循环动画，pumpAndSettle 会永远等不到空闲）。
Future<MaterialLibraryNotifier> _pumpLibrary(
  WidgetTester tester, {
  required _FakeRepo repo,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1366, 768));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = MaterialLibraryNotifier(repo);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        materialLibraryNotifierProvider.overrideWith((ref) => notifier),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          // 与正式 app（main/app.dart）一致：CupertinoApp 带 MaterialLocalizations
          // 委托，否则 showDialog（AppToast/对话框）会抛「No MaterialLocalizations」。
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: [
            loc.GlobalMaterialLocalizations.delegate,
            ...GlobalCupertinoLocalizations.delegates,
          ],
          home: ShadToaster(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: const MaterialLibraryView(),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return notifier;
}

void main() {
  testWidgets('上传在飞时：已上传列表保持可见，只挂行内「正在刷新」提示',
      (tester) async {
    final repo = _FakeRepo(materials: const [_existing]);
    final notifier = await _pumpLibrary(tester, repo: repo);

    // 首屏加载完成：既有资料在屏上，无整块转圈。
    expect(find.text('数学教材.txt'), findsOneWidget);
    expect(find.byType(AppLoading), findsNothing);

    // 发起上传但不等待（仓库的上传 future 挂起）——复现「上传在飞」窗口。
    final uploadFlight =
        notifier.upload(filename: '新资料.txt', bytes: [1, 2, 3]);
    await tester.pump();

    // 核心断言：上传等待期间，已上传的资料不许从屏上消失。
    expect(find.text('数学教材.txt'), findsOneWidget,
        reason: '上传在飞时列表必须留在屏上，不能整块换成转圈');
    expect(find.byType(AppLoading), findsNothing,
        reason: '有内容可保留时不再用整块 AppLoading 替换列表');
    expect(find.text('正在刷新…'), findsOneWidget);
    expect(find.text('上传中…'), findsOneWidget,
        reason: '主按钮进入自转禁用态，防连点重复上传');

    // 上传完成：刷新提示退场，流程收口（notice 由视图的 listener 消费弹toast，
    // 内容口径已由 material_library_reextract_test 的 notifier 级测试覆盖）。
    repo.uploadGate.complete(
        const MaterialExtractResult(material: _existing, extraction: 'extracted'));
    await uploadFlight;
    await tester.pumpAndSettle();

    expect(find.text('正在刷新…'), findsNothing);
    expect(find.text('数学教材.txt'), findsOneWidget);
    expect(find.text('上传中…'), findsNothing);
    expect(notifier.state.loading, isFalse);
  });

  testWidgets('首屏空列表 + 加载中：整块转圈兜底，加载完落空态', (tester) async {
    final repo = _FakeRepo(gateMaterials: true);
    await _pumpLibrary(tester, repo: repo, settle: false);
    await tester.pump();

    // 什么都没有可保留：整块转圈是正确占位（不是空态文案）。
    expect(find.byType(AppLoading), findsOneWidget);
    expect(find.text('这里还没有资料'), findsNothing);

    repo.materialsGate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AppLoading), findsNothing, reason: '加载完不应残留转圈');
    expect(find.text('这里还没有资料'), findsOneWidget);
  });
}
