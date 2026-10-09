// 课件中心页（courseware-round-3 T01）+ 课件信息编辑（T02）。
//
// ⚠️ 不套 Material：App 根 ShadApp + CupertinoApp，整树无 Material 祖先（同
// courseware_editor_page_test）。showDialog 需 CupertinoApp 带 MaterialLocalizations 委托，
// 否则抛「No MaterialLocalizations」。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as loc;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/courseware/domain/models/courseware.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_asset.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_redraft_diff.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_section.dart';
import 'package:kids_learn/features/courseware/domain/repositories/courseware_repository.dart';
import 'package:kids_learn/features/courseware/presentation/pages/courseware_editor_page.dart';
import 'package:kids_learn/features/courseware/presentation/screens/courseware_center_screen.dart';
import 'package:kids_learn/features/courseware/providers/courseware_provider.dart';
import 'package:kids_learn/features/home/domain/repositories/material_repository.dart';
import 'package:kids_learn/shared/widgets/app_actions.dart';
import 'package:kids_learn/shared/widgets/app_buttons.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

CoursewareModel _cw({
  String id = 'cw1',
  String title = '轴对称的第一课',
  String kpName = '图形的运动（轴对称）',
  String status = 'draft',
  String? objective,
}) =>
    CoursewareModel(
      id: id,
      subject: '数学',
      grade: 3,
      semester: '下册',
      kpName: kpName,
      title: title,
      status: status,
      objective: objective,
    );

/// 测试用假仓库：覆盖中心页 / 创建 sheet / 信息编辑用到的端点，并捕获新建与编辑参数。
class _FakeRepo extends CoursewareRepository {
  _FakeRepo({
    this.listReturnsEmpty = false,
    this.knowledgePoints = const [],
  });
  final bool listReturnsEmpty;
  final List<KnowledgePointOption> knowledgePoints;

  int listKnowledgePointsCalls = 0;
  String? lastCreateKpId;
  String? lastCreateTitle;
  String? lastCreateObjective;
  bool? lastCreateDraft;
  String? lastUpdateTitle;
  String? lastUpdateStatus;

  @override
  Future<List<CoursewareModel>> listCourseware({
    String? knowledgePointId,
    String? subject,
    int? grade,
    String? semester,
  }) async =>
      listReturnsEmpty ? <CoursewareModel>[] : [_cw()];

  @override
  Future<List<KnowledgePointOption>> listKnowledgePoints() async {
    listKnowledgePointsCalls++;
    return knowledgePoints;
  }

  @override
  Future<CoursewareModel> createCourseware({
    required String knowledgePointId,
    String? title,
    String? objective,
    bool draft = true,
  }) async {
    lastCreateKpId = knowledgePointId;
    lastCreateTitle = title;
    lastCreateObjective = objective;
    lastCreateDraft = draft;
    return _cw(
      id: 'cw-new',
      title: title ?? '图形的运动（轴对称）',
      objective: objective,
    );
  }

  @override
  Future<CoursewareModel?> getRecentCourseware() async => null;

  @override
  Future<CoursewareModel> getCourseware(String id) async => _cw(id: id);

  @override
  Future<CoursewareModel> updateCourseware(String coursewareId,
          {String? title, String? status}) async {
    lastUpdateTitle = title;
    lastUpdateStatus = status;
    return _cw(id: coursewareId, title: title ?? '轴对称的第一课', status: status ?? 'draft');
  }

  @override
  Future<CoursewareModel> updateSections(String coursewareId,
          List<CoursewareSectionModel> sections) async =>
      _cw(id: coursewareId);

  @override
  Future<void> deleteCourseware(String coursewareId) async {}

  @override
  Future<CoursewareRedraftDiffModel> getRedraftDiff(String coursewareId) async =>
      CoursewareRedraftDiffModel(diff: const []);

  @override
  Future<List<Map<String, dynamic>>?> getKnowledgePointScenes({
    required String kpId,
    required String subject,
    required int grade,
    String semester = '',
  }) async =>
      null;

  @override
  Future<List<CoursewareAssetModel>> getAssets({
    String? knowledgePointId,
    String? filename,
  }) async =>
      const [];

  @override
  Future<CoursewareAssetModel> uploadAsset({
    required String filename,
    required List<int> bytes,
  }) async =>
      const CoursewareAssetModel(name: '', mime: '', url: '');

  @override
  Future<void> deleteAsset(String assetId) async {}
}

class _FakeStorage extends StorageService {
  @override
  String? getToken() => null;
}

Future<void> _pumpCenter(WidgetTester tester, _FakeRepo repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coursewareRepositoryProvider.overrideWithValue(repo),
        storageServiceProvider.overrideWithValue(_FakeStorage()),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: [
            loc.GlobalMaterialLocalizations.delegate,
            ...GlobalCupertinoLocalizations.delegates,
          ],
          home: ShadToaster(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: const CoursewareCenterScreen(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpEditor(WidgetTester tester, _FakeRepo repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coursewareRepositoryProvider.overrideWithValue(repo),
        storageServiceProvider.overrideWithValue(_FakeStorage()),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: [
            loc.GlobalMaterialLocalizations.delegate,
            ...GlobalCupertinoLocalizations.delegates,
          ],
          home: ShadToaster(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: CoursewareEditorPage(
                knowledgePointId: 'kp1',
                kpName: '图形的运动（轴对称）',
                subject: '数学',
                grade: 3,
                semester: '下册',
                initialCourseware: _cw(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('课件中心 · 新增课件入口（T01）', () {
    testWidgets('空态展示「新增课件」主入口，并预载知识点选择器数据源',
        (tester) async {
      final repo = _FakeRepo(listReturnsEmpty: true, knowledgePoints: [
        const KnowledgePointOption(id: 'kp1', name: '图形的运动（轴对称）'),
        const KnowledgePointOption(id: 'kp2', name: '分数加减'),
      ]);
      await _pumpCenter(tester, repo);

      expect(find.text('新增课件'), findsWidgets); // 标题行按钮 + 空态 action
      expect(find.text('还没有课件'), findsOneWidget);
      // 注意：知识点全集由「新增课件」表单在打开时拉取，不在中心页预载。
      expect(repo.listKnowledgePointsCalls, 0);
    });

    testWidgets('点「新增课件」弹表单：未选知识点时「创建空课件」禁用',
        (tester) async {
      final repo = _FakeRepo(listReturnsEmpty: true, knowledgePoints: [
        const KnowledgePointOption(id: 'kp1', name: '图形的运动（轴对称）'),
      ]);
      await _pumpCenter(tester, repo);

      await tester.tap(find.text('新增课件').first);
      await tester.pumpAndSettle();

      expect(find.text('知识点'), findsOneWidget);
      expect(find.text('请选择知识点'), findsOneWidget);
      expect(find.widgetWithText(AppPrimaryButton, '创建空课件'), findsOneWidget);
      // 打开表单即拉取知识点全集（选择器数据源）。
      expect(repo.listKnowledgePointsCalls, greaterThanOrEqualTo(1));
      // 未选知识点不应触发建课件。
      expect(repo.lastCreateDraft, isNull);
    });

    testWidgets('选知识点后创建空壳：走 draft=false（不触发 AI）并打开编辑器',
        (tester) async {
      final repo = _FakeRepo(listReturnsEmpty: true, knowledgePoints: [
        const KnowledgePointOption(id: 'kp1', name: '图形的运动（轴对称）'),
        const KnowledgePointOption(id: 'kp2', name: '分数加减'),
      ]);
      await _pumpCenter(tester, repo);

      await tester.tap(find.text('新增课件').first);
      await tester.pumpAndSettle();
      // 打开知识点下拉并选择第一项。
      await tester.tap(find.text('请选择知识点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('图形的运动（轴对称）'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppPrimaryButton, '创建空课件'));
      await tester.pumpAndSettle();

      // 关键：空壳走 draft=false，不触发 AI 起草。
      expect(repo.lastCreateDraft, isFalse);
      expect(repo.lastCreateKpId, 'kp1');
      // 建好后直接进入编辑器（课件信息卡可见）。
      expect(find.text('课件信息'), findsNothing); // 信息卡仅在编辑器内
      expect(find.text('备课'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('课件信息编辑（T02）', () {
    testWidgets('信息卡展示标题与状态，点编辑改标题 + 状态落库',
        (tester) async {
      final repo = _FakeRepo();
      await _pumpEditor(tester, repo);

      // 信息卡：标题 + 状态芯片（草稿）。
      expect(find.text('轴对称的第一课'), findsWidgets);
      expect(find.text('草稿'), findsWidgets);

      await tester.tap(find.widgetWithText(AppTextAction, '编辑'));
      await tester.pumpAndSettle();
      expect(find.text('课件信息'), findsOneWidget); // 编辑弹窗标题

      // 改标题（弹窗内唯一文本输入框）。
      await tester.enterText(find.byType(EditableText), '轴对称复习课');
      await tester.pumpAndSettle();
      // 状态改「可上讲台」：value 初始为 draft，选择器显示已选项标签，点它展开。
      await tester.tap(find.text('草稿（还在调）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('可上讲台（可直接讲）'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppPrimaryButton, '保存'));
      await tester.pumpAndSettle();

      expect(repo.lastUpdateTitle, '轴对称复习课');
      expect(repo.lastUpdateStatus, 'ready');
      expect(tester.takeException(), isNull);
    });
  });
}
