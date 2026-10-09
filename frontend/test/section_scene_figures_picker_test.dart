// 课件环节编辑器的「演示哪几个图形、按什么顺序」入口（ADR-0076 §2.1 / §2.2 · ticket 04）。
//
// **输入侧接缝**：真编辑器页 + 假仓库，断言**保存出去的那份数据**（`repo.lastUpdated`
// → `section.scene`）。02 / 03 票的画廊与解释器消费的就是这份数据，因此把契约钉在
// 写入侧等于给它们定输入。
//
// 守六件事（每条对应票上一项验收）：
// 1. 勾选顺序 == `items` 顺序——刻意用**非库序**的勾选序列（先正方形后房子），
//    库序断言在「按库序重排」的坏实现下也照样过，测不出问题；
// 2. 保存 → 重开编辑器 → 回读一致（教师下次打开看到的还是自己排的那份）；
// 3. 勾 ≤1 张 → `optionGroup` 这个键被**删掉**（不是把 scene 清空），回落单场景；
// 4. 未关联场景 / kind ≠ reflection → 选择器不出现（其它场景没有平面图形语义）；
// 5. `points` 保存时已展开（断网也能渲染，不能只留 key 让渲染层回查）；
// 6. 知识点场景零回写（ADR-0073 红线）。
//
// 挂载纪律：整树**不套 Material**（根是 `ShadApp` + `CupertinoApp`，本仓没有 Material
// 祖先）；material 的 `showDialog` 需要 `MaterialLocalizations`，故挂中文委托而非
// 套 MaterialApp。编辑弹窗内容可滚，越界的控件先 `ensureVisible` 再点。
import 'dart:convert';

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
import 'package:kids_learn/features/home/domain/repositories/material_repository.dart';
import 'package:kids_learn/features/courseware/presentation/pages/courseware_editor_page.dart';
import 'package:kids_learn/features/courseware/providers/courseware_provider.dart';
import 'package:kids_learn/shared/domain/figures.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_actions.dart';

/// 知识点上的一份轴对称讲解模板（编辑器「关联知识点场景」拉回来的就是它）。
Map<String, dynamic> _reflectionSpec() => <String, dynamic>{
      'kind': 'reflection',
      'title': '图形的运动（轴对称）',
      'narrative': '对折演示',
      'editable': true,
    };

CoursewareSectionModel _section([Map<String, dynamic>? scene]) =>
    CoursewareSectionModel(
      id: 'a',
      title: '动手画对称图形',
      payload: const {},
      scene: scene,
    );

CoursewareModel _coursewareWith(List<CoursewareSectionModel> sections) =>
    CoursewareModel(
      id: 'cw1',
      subject: '数学',
      grade: 3,
      semester: '下册',
      kpName: '图形的运动（轴对称）',
      title: '轴对称的第一课',
      status: 'ready',
      sections: sections,
    );

/// 记忆体假仓库：只实现编辑器会调的三件事，其余给占位。
class _FakeRepo extends CoursewareRepository {
  _FakeRepo(this._courseware);
  final CoursewareModel _courseware;
  List<CoursewareSectionModel>? lastUpdated;
  int updateSectionsCalls = 0;

  /// 知识点讲解模板（编辑器「关联知识点场景」的数据源）。保存前后快照比对用它
  /// 守「零回写知识点」红线。
  List<Map<String, dynamic>>? kpScenes;

  @override
  Future<List<CoursewareModel>> listCourseware({
    String? knowledgePointId,
    String? subject,
    int? grade,
    String? semester,
  }) async =>
      [_courseware];

  @override
  Future<CoursewareModel> updateSections(
    String coursewareId,
    List<CoursewareSectionModel> sections,
  ) async {
    updateSectionsCalls++;
    lastUpdated = sections;
    return _coursewareWith(sections);
  }

  @override
  Future<List<Map<String, dynamic>>?> getKnowledgePointScenes({
    required String kpId,
    required String subject,
    required int grade,
    String semester = '',
  }) async =>
      kpScenes;

  @override
  Future<CoursewareModel> createCourseware({
    required String knowledgePointId,
    String? title,
    String? objective,
    bool draft = true,
  }) async =>
      _courseware;
  @override
  Future<List<KnowledgePointOption>> listKnowledgePoints() async => const [];
  @override
  Future<CoursewareModel?> getRecentCourseware() async => null;
  @override
  Future<CoursewareModel> getCourseware(String id) async => _courseware;
  @override
  Future<CoursewareModel> updateCourseware(String coursewareId,
          {String? title, String? status}) async =>
      _courseware;
  @override
  Future<void> deleteCourseware(String coursewareId) async {}
  @override
  Future<CoursewareRedraftDiffModel> getRedraftDiff(String coursewareId) async =>
      CoursewareRedraftDiffModel(diff: const []);
  @override
  Future<List<CoursewareAssetModel>> getAssets({
    String? knowledgePointId,
    String? filename,
  }) async =>
      <CoursewareAssetModel>[];
  @override
  Future<CoursewareAssetModel> uploadAsset(
          {required String filename, required List<int> bytes}) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteAsset(String assetId) async {}
}

Future<void> _pumpEditor(WidgetTester tester, {required _FakeRepo repo}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [coursewareRepositoryProvider.overrideWithValue(repo)],
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
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 打开某环节的编辑弹窗（编辑器页里点环节卡片即可）。
Future<void> _openDialog(WidgetTester tester, _FakeRepo repo) async {
  await _pumpEditor(tester, repo: repo);
  await tester.tap(find.text('动手画对称图形'));
  await tester.pumpAndSettle();
  expect(find.text('编辑环节'), findsOneWidget);
}

/// 勾选 / 取消勾选一个图形（图形名即卡片文案）。
Future<void> _toggle(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// 点某个行内动作（上移 / 下移 / 移除）。
///
/// 按 `semanticLabel` 找（语义名带图形名，故唯一）——顺带也钉住了键盘 / 读屏路径
/// 拿到的是「把房子上移」而不是三个同名的「上移」。
Future<void> _press(WidgetTester tester, String semanticLabel) async {
  final finder = find.byWidgetPredicate(
    (w) => w is AppTextAction && w.semanticLabel == semanticLabel,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, _FakeRepo repo) async {
  await tester.ensureVisible(find.text('保存'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
  expect(repo.updateSectionsCalls, 1, reason: '保存没有落到仓库');
}

/// 保存出去的那份 `optionGroup`（断言前先确认它确实在）。
Map<String, dynamic> _savedGroup(_FakeRepo repo) {
  final scene = repo.lastUpdated!.first.scene;
  expect(scene, isNotNull);
  expect(scene!.containsKey('optionGroup'), isTrue);
  return scene['optionGroup'] as Map<String, dynamic>;
}

/// 条目里的图形 key 序列——顺序就是教学编排意图。
List<String> _keysOf(Map<String, dynamic> group) =>
    (group['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((e) => e['figureKey'] as String)
        .toList();

void main() {
  testWidgets('勾 2 张：顺序 == 勾选顺序（非库序），保存后落库，重开回读一致',
      (tester) async {
    final repo = _FakeRepo(_coursewareWith([_section(_reflectionSpec())]));
    await _openDialog(tester, repo);

    // 先勾正方形（库序第 5）再勾房子（库序第 1）：库序下会变成 [房子, 正方形]。
    await _toggle(tester, '正方形');
    await _toggle(tester, '房子');

    await _save(tester, repo);

    final group = _savedGroup(repo);
    expect(group['curated'], isTrue);
    expect(_keysOf(group), <String>['square', 'house']);

    // 重开编辑器（保存后页面已换成新环节），回读应一致。
    await tester.tap(find.text('动手画对称图形'));
    await tester.pumpAndSettle();
    expect(find.text('编辑环节'), findsOneWidget);
    expect(find.text('1. 正方形'), findsOneWidget);
    expect(find.text('2. 房子'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('上移 / 下移改顺序：落库顺序跟着变', (tester) async {
    final repo = _FakeRepo(_coursewareWith([_section(_reflectionSpec())]));
    await _openDialog(tester, repo);

    await _toggle(tester, '正方形');
    await _toggle(tester, '房子');
    // 勾选顺序（先正方形后房子），与上一条用例同。
    expect(find.text('1. 正方形'), findsOneWidget);
    expect(find.text('2. 房子'), findsOneWidget);

    await _press(tester, '把房子上移');
    expect(find.text('1. 房子'), findsOneWidget);
    expect(find.text('2. 正方形'), findsOneWidget);

    await _save(tester, repo);
    expect(_keysOf(_savedGroup(repo)), <String>['house', 'square']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('勾 1 张：optionGroup 被移除，scene 本身还在', (tester) async {
    final repo = _FakeRepo(_coursewareWith([_section(_reflectionSpec())]));
    await _openDialog(tester, repo);

    await _toggle(tester, '正方形');
    await _save(tester, repo);

    final scene = repo.lastUpdated!.first.scene;
    expect(scene, isNotNull, reason: 'scene 被整个清空了（只应删 optionGroup 键）');
    expect(scene!.containsKey('optionGroup'), isFalse);
    // 回落到单场景路径：场景自己的字段一个不少。
    expect(scene['kind'], 'reflection');
    expect(scene['title'], '图形的运动（轴对称）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('勾 0 张（勾了又取消）：optionGroup 被移除', (tester) async {
    final repo = _FakeRepo(_coursewareWith([_section(_reflectionSpec())]));
    await _openDialog(tester, repo);

    await _toggle(tester, '正方形');
    await _toggle(tester, '房子');
    await _toggle(tester, '正方形'); // 取消
    await _toggle(tester, '房子'); // 取消
    await _save(tester, repo);

    final scene = repo.lastUpdated!.first.scene;
    expect(scene, isNotNull);
    expect(scene!.containsKey('optionGroup'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未关联场景 / 非轴对称场景：选择器不出现', (tester) async {
    const pickerTitle = '演示哪几个图形、按什么顺序';

    // ① 未关联场景。
    final noScene = _FakeRepo(_coursewareWith([_section()]));
    await _openDialog(tester, noScene);
    expect(find.text(pickerTitle), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // ② 关联了，但不是轴对称（没有平面图形语义，摆图形选择器是误导）。
    final otherKind = _FakeRepo(
      _coursewareWith([_section(<String, dynamic>{'kind': 'fraction'})]),
    );
    await _pumpEditor(tester, repo: otherKind);
    await tester.tap(find.text('动手画对称图形'));
    await tester.pumpAndSettle();
    expect(find.text('编辑环节'), findsOneWidget);
    expect(find.text(pickerTitle), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('points 已展开（不是只有 key），且与图形库顶点一致', (tester) async {
    final repo = _FakeRepo(_coursewareWith([_section(_reflectionSpec())]));
    await _openDialog(tester, repo);

    await _toggle(tester, '正方形');
    await _toggle(tester, '房子');
    await _save(tester, repo);

    final items = (_savedGroup(repo)['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(items.length, 2);
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      expect(item['label'], '');
      expect(item['caption'], isNotNull);
      final key = item['figureKey'] as String;
      // 图形中文名 == 图形库里那一个的 label（渲染层按 caption 命中图形）。
      final shape = kFigureShapes.firstWhere((f) => f.key == key);
      expect(item['caption'], shape.label);
      expect(item['defaultAxisAngle'], shape.defaultAxisAngle);

      final points = item['points'];
      expect(points, isA<List>(), reason: 'points 被写成了 ${points.runtimeType}');
      expect((points as List).length, shape.vertices.length);
      for (var v = 0; v < shape.vertices.length; v++) {
        final vertex = points[v];
        expect(vertex, isA<List>(), reason: '顶点被压平了：$vertex');
        expect((vertex as List).length, 2);
        expect(vertex[0], closeTo(shape.vertices[v].x, 1e-9));
        expect(vertex[1], closeTo(shape.vertices[v].y, 1e-9));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('知识点场景零回写：保存前后快照一致（ADR-0073）', (tester) async {
    // 环节的 scene 与知识点模板**故意是同一个 Map 实例**：实现若就地改 scene，
    // 知识点上那份立刻跟着变——这条断言因此能抓住就地写。
    final kpSpec = _reflectionSpec();
    final repo = _FakeRepo(_coursewareWith([_section(kpSpec)]));
    repo.kpScenes = [kpSpec];
    final before = jsonEncode(repo.kpScenes);

    await _openDialog(tester, repo);
    await _toggle(tester, '正方形');
    await _toggle(tester, '房子');
    await _save(tester, repo);

    expect(jsonEncode(repo.kpScenes), before,
        reason: '知识点上的场景被回写了（ADR-0073：只写本环节的副本）');
    // 本环节确实写上了——否则这条断言会因为「什么都没做」而假通过。
    expect(_keysOf(_savedGroup(repo)), <String>['square', 'house']);
    expect(tester.takeException(), isNull);
  });

}
