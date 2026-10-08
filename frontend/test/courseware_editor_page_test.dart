// 课件编辑器页（ADR-0067 第二轮 T01：拖拽重排 + 多选批量删）。
//
// ⚠️ 刻意不套 Material（同 courseware_present_page_test）：App 根 ShadApp + CupertinoApp，
// 整树无 Material 祖先。测试照 assistant_sources_bar_test 的写法挂 CupertinoApp。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as loc;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/courseware/domain/models/courseware.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_asset.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_redraft_diff.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_section.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_section_kind.dart';
import 'package:kids_learn/features/courseware/domain/repositories/courseware_repository.dart';
import 'package:kids_learn/features/courseware/presentation/pages/courseware_editor_page.dart';
import 'package:kids_learn/features/courseware/presentation/widgets/editor_section_list.dart'
    show reorderCoursewareSections;
import 'package:kids_learn/features/courseware/providers/courseware_provider.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

CoursewareSectionModel _sec(String id, String title) => CoursewareSectionModel(
      id: id,
      kind: CoursewareSectionKind.mediaGallery,
      title: title,
      script: '话术：$title',
      payload: const {},
    );

CoursewareModel _editorCourseware(List<CoursewareSectionModel> sections) =>
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

/// 测试用假 StorageService：不读写 SharedPreferences，[getToken] 直接返回 null。
/// 素材图片走 [AuthImage] 取 token 注入鉴权头；测试无后端，返回 null 即不带头，
/// 不影响 widget 构建（失败由 errorBuilder 兜底，且不触发真实网络）。
class _FakeStorage extends StorageService {
  @override
  String? getToken() => null;
}

/// 内存假仓库：只实现编辑器用到的 [listCourseware] / [updateSections] / [getRedraftDiff]，
/// 其余给计数占位，便于断言「重起草不新建/删除副本」。
class _FakeRepo extends CoursewareRepository {
  _FakeRepo(this._courseware, {this.listReturnsEmpty = false});
  final CoursewareModel _courseware;
  // 模拟「这个知识点还没有课件」：listCourseware 返回空（T09 进入即空态）。
  final bool listReturnsEmpty;
  List<CoursewareSectionModel>? lastUpdated;
  int updateSectionsCalls = 0;
  int createCoursewareCalls = 0;
  int deleteCoursewareCalls = 0;
  int redraftDiffCalls = 0;
  CoursewareRedraftDiffModel? redraftDiff;

  @override
  Future<List<CoursewareModel>> listCourseware({
    String? knowledgePointId,
    String? subject,
    int? grade,
    String? semester,
  }) async =>
      listReturnsEmpty ? <CoursewareModel>[] : [_courseware];

  @override
  Future<CoursewareModel> updateSections(
    String coursewareId,
    List<CoursewareSectionModel> sections,
  ) async {
    updateSectionsCalls++;
    lastUpdated = sections;
    return CoursewareModel(
      id: _courseware.id,
      subject: _courseware.subject,
      grade: _courseware.grade,
      semester: _courseware.semester,
      kpName: _courseware.kpName,
      title: _courseware.title,
      status: _courseware.status,
      sections: sections,
    );
  }

  @override
  Future<CoursewareModel> createCourseware(
          {required String knowledgePointId, String? title}) async {
    createCoursewareCalls++;
    // 人为延迟，让「生成中」提示可被 widget 测试稳定观测（生产端是真 AI 起草，本就慢）。
    await Future.delayed(const Duration(milliseconds: 50));
    return _courseware;
  }

  @override
  Future<CoursewareModel?> getRecentCourseware() async => null;
  @override
  Future<CoursewareModel> getCourseware(String id) async => _courseware;
  @override
  Future<CoursewareModel> updateCourseware(String coursewareId,
          {String? title, String? status}) async =>
      _courseware;
  @override
  Future<void> deleteCourseware(String coursewareId) async {
    deleteCoursewareCalls++;
  }

  @override
  Future<CoursewareRedraftDiffModel> getRedraftDiff(String coursewareId) async {
    redraftDiffCalls++;
    return redraftDiff ?? CoursewareRedraftDiffModel(diff: const []);
  }

  /// 知识点讲解模板：测试里可注入，模拟「已配置 / 未配置」两种场景。
  List<Map<String, dynamic>>? kpScenes;

  @override
  Future<List<Map<String, dynamic>>?> getKnowledgePointScenes({
    required String kpId,
    required String subject,
    required int grade,
    String semester = '',
  }) async =>
      kpScenes;

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

Future<void> _pumpEditor(
  WidgetTester tester, {
  required _FakeRepo repo,
  List<CoursewareAssetModel> assets = const <CoursewareAssetModel>[],
  Size size = const Size(1366, 768),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coursewareRepositoryProvider.overrideWithValue(repo),
        // 素材图片走 AuthImage 取 token；测试无后端，用假 StorageService 让构建不崩。
        storageServiceProvider.overrideWithValue(_FakeStorage()),
        // 素材库检索（picker 用 T04）：测试里不直连 repository，直接喂假素材。
        // 覆盖 coursewareAssetLibraryProvider（picker 实际 watch 的），并按查询串过滤，
        // 使文件名检索框在测试里真实生效。
        coursewareAssetLibraryProvider.overrideWith((ref, q) {
          if (q.filename == null || q.filename!.isEmpty) return assets;
          return assets
              .where((a) => a.name.contains(q.filename!))
              .toList();
        }),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          // 与正式 app（main/app.dart）一致：CupertinoApp 带 MaterialLocalizations
          // 委托，否则 material 的 showDialog（编辑对话框）会抛「No MaterialLocalizations」。
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

void main() {
  group('编辑器环节重排 / 批量删（T01）', () {
    test('重排纯函数：插到目标之前、末尾、各种 from/to', () {
      final a = _sec('a', 'A');
      final b = _sec('b', 'B');
      final c = _sec('c', 'C');
      final list = [a, b, c];
      // 语义：把 from 移到 to「之前」。from<to 时 insertAt=to-1。
      expect(reorderCoursewareSections(list, 0, 2).map((s) => s.id).toList(),
          ['b', 'a', 'c']);
      expect(reorderCoursewareSections(list, 0, 1).map((s) => s.id).toList(),
          ['a', 'b', 'c']);
      expect(reorderCoursewareSections(list, 2, 0).map((s) => s.id).toList(),
          ['c', 'a', 'b']);
      expect(reorderCoursewareSections(list, 0, 3).map((s) => s.id).toList(),
          ['b', 'c', 'a']);
      expect(reorderCoursewareSections(list, 1, 3).map((s) => s.id).toList(),
          ['a', 'c', 'b']);
    });

    testWidgets('渲染 3 个环节且计数正确', (tester) async {
      final repo = _FakeRepo(_editorCourseware(
          [_sec('a', '环节一'), _sec('b', '环节二'), _sec('c', '环节三')]));
      await _pumpEditor(tester, repo: repo);
      final e = tester.takeException();
      if (e != null) {
        debugDumpApp();
        debugPrint('=== OVERFLOW: $e');
      }
      expect(find.text('3 个讲解环节'), findsOneWidget);
      expect(find.text('环节一'), findsOneWidget);
      expect(find.text('环节三'), findsOneWidget);
      expect(e, isNull);
    });

    testWidgets('多选批量删：选中两项后删除，落库且计数更新', (tester) async {
      final repo = _FakeRepo(_editorCourseware(
          [_sec('a', '环节一'), _sec('b', '环节二'), _sec('c', '环节三')]));
      await _pumpEditor(tester, repo: repo);

      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('环节一'));
      await tester.tap(find.text('环节二'));
      await tester.pumpAndSettle();
      expect(find.text('删除选中(2)'), findsOneWidget);

      await tester.tap(find.text('删除选中(2)'));
      await tester.pumpAndSettle();

      expect(repo.updateSectionsCalls, 1);
      expect(repo.lastUpdated?.map((s) => s.id).toList(), ['c']);
      expect(find.text('1 个讲解环节'), findsOneWidget);
      expect(find.text('环节三'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('拖拽手柄触发重排并持久化（顺序改变）', (tester) async {
      final repo = _FakeRepo(_editorCourseware(
          [_sec('a', '环节一'), _sec('b', '环节二'), _sec('c', '环节三')]));
      await _pumpEditor(tester, repo: repo);

      final handle = find.byKey(const Key('drag-0'));
      expect(handle, findsOneWidget);
      // 向下拖到第三张卡片的落点附近。
      await tester.drag(handle, const Offset(0, 260));
      await tester.pumpAndSettle();

      // 拖拽应触发一次 updateSections，且顺序相对原序发生变化（验证重排→落库链路）。
      expect(repo.updateSectionsCalls, 1);
      final ordered = repo.lastUpdated!.map((s) => s.id).toList();
      expect(ordered.length, 3);
      expect(ordered, isNot(['a', 'b', 'c']));
      expect(tester.takeException(), isNull);
    });
  });

  group('话术多段化 + 重点（T02）', () {
    test('模型：script_segments 解析 + displaySegments 回退 + 序列化往返', () {
      // 旧单串话术 → 退化成一段（向后兼容，不空屏）。
      final legacy = _sec('a', '环节一');
      expect(legacy.displaySegments.map((s) => s.text).toList(), ['话术：环节一']);

      final seg = CoursewareSectionModel(
        id: 'a',
        title: '环节一',
        scriptSegments: [
          CoursewareScriptSegment(
              text: '开场', emphasis: CoursewareScriptEmphasis.bold),
          CoursewareScriptSegment(
              text: '追问', emphasis: CoursewareScriptEmphasis.highlight),
        ],
      );
      expect(seg.displaySegments.length, 2);
      expect(seg.displaySegments[0].emphasis, CoursewareScriptEmphasis.bold);
      // 有段列表时优先用它，忽略旧 script。
      expect(seg.displaySegments.map((s) => s.text).toList(),
          ['开场', '追问']);

      // 空课件：无段、无 script → 空。
      expect(const CoursewareSectionModel(id: 'x').displaySegments, isEmpty);

      // 序列化往返不丢重点。
      final back = CoursewareSectionModel.fromJson(seg.toJson());
      expect(back.scriptSegments[1].emphasis, CoursewareScriptEmphasis.highlight);
      expect(CoursewareScriptEmphasis.tryParse('bogus'),
          CoursewareScriptEmphasis.none);
    });

    testWidgets('编辑器对话框：增段 + 切重点 + 保存落库', (tester) async {
      final repo = _FakeRepo(_editorCourseware([_sec('a', '环节一')]));
      await _pumpEditor(tester, repo: repo);

      // 点环节卡片打开编辑对话框（legacy script 自动包成第 1 段）。
      await tester.tap(find.text('环节一'));
      await tester.pumpAndSettle();
      expect(find.text('编辑环节'), findsOneWidget);

      // 第 1 段重点：普通 → 加粗。
      await tester.tap(find.text('普通'));
      await tester.pumpAndSettle();
      expect(find.text('加粗'), findsWidgets);

      // 添加第二段并输入文本。
      await tester.tap(find.text('添加一段'));
      await tester.pumpAndSettle();
      final seg2 = find.byType(EditableText).at(2); // 0=标题 1=第1段 2=第2段
      await tester.enterText(seg2, '第二段话术');
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(repo.updateSectionsCalls, 1);
      final saved = repo.lastUpdated!.first;
      expect(saved.scriptSegments.length, 2);
      expect(saved.scriptSegments[0].emphasis, CoursewareScriptEmphasis.bold);
      expect(saved.scriptSegments[1].text, '第二段话术');
      // 旧 script 同步压平，保证仍读 script 的消费者不丢。
      expect(saved.script, contains('第二段话术'));
      expect(tester.takeException(), isNull);
    });
  });

  group('媒体画廊内联增删素材项（T03）', () {
    CoursewareSectionModel gallery(String id, String title,
            List<Map<String, String>> items) =>
        _sec(id, title).copyWith(
          payload: {'items': items},
        );

    const assetA = CoursewareAssetModel(
      id: 'a1',
      name: '蝴蝶标本',
      mime: 'image/png',
      url: '/x/a1',
    );
    const assetB = CoursewareAssetModel(
      id: 'b1',
      name: '建筑立面',
      mime: 'image/png',
      url: '/x/b1',
    );

    testWidgets('内联添加素材项：开 picker 选图 → 持久化且项数 +1',
        (tester) async {
      final repo = _FakeRepo(_editorCourseware([
        gallery('a', '环节一', const [
          {'asset_id': 'a1', 'caption': '蝴蝶标本'},
        ]),
      ]));
      await _pumpEditor(tester, repo: repo, assets: [assetA, assetB]);

      await tester.tap(find.text('环节一'));
      await tester.pumpAndSettle();
      // 编辑对话框已带既有 1 个素材项（caption 直接可见）。
      expect(find.text('蝴蝶标本'), findsWidgets);

      // 添加素材 → 素材库 picker 弹出 → 选第二个素材。
      await tester.tap(find.text('添加素材'));
      await tester.pumpAndSettle();
      expect(find.text('选择素材'), findsOneWidget);
      // 新 picker 以缩略图网格展示素材：用语义标签定位「建筑立面」缩略图并点选。
      await tester.tap(find.bySemanticsLabel('选择素材 建筑立面'));
      await tester.pumpAndSettle();
      // 确认（picker 内多选确认）→ 关闭 picker，回到编辑对话框。
      // 注：编辑对话框原本已带 1 个素材项（a1 蝴蝶标本），picker 以
      // initialSelected 预选它，点选 建筑立面（b1）后共 2 项，故按钮为「确认（2）」。
      await tester.tap(find.text('确认（2）'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(repo.updateSectionsCalls, 1);
      final mats = repo.lastUpdated!.first.materials;
      expect(mats.length, 2);
      expect(mats.any((m) => m.assetId == 'b1'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('内联删除素材项：移除一项 → 持久化且项数 -1、不再出现',
        (tester) async {
      final repo = _FakeRepo(_editorCourseware([
        gallery('a', '环节一', const [
          {'asset_id': 'a1', 'caption': '蝴蝶标本'},
          {'asset_id': 'b1', 'caption': '建筑立面'},
        ]),
      ]));
      await _pumpEditor(tester, repo: repo);

      await tester.tap(find.text('环节一'));
      await tester.pumpAndSettle();
      expect(find.text('蝴蝶标本'), findsWidgets);
      expect(find.text('建筑立面'), findsWidgets);

      // 删除最后一项：素材缩略图右上角的删除按钮（语义标签「移除该素材」，
      // 末位即第 2 项；素材名仍作为 caption 叠加显示）。
      await tester.tap(find.bySemanticsLabel('移除该素材').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(repo.updateSectionsCalls, 1);
      final mats = repo.lastUpdated!.first.materials;
      expect(mats.length, 1);
      expect(mats.first.assetId, 'a1');
      expect(tester.takeException(), isNull);
    });
  });

  group('素材库检索端点接入 picker（T04）', () {
    CoursewareSectionModel gallery(String id, String title,
            List<Map<String, String>> items) =>
        _sec(id, title).copyWith(
          payload: {'items': items},
        );

    const assetA = CoursewareAssetModel(
      id: 'a1',
      name: '蝴蝶标本',
      mime: 'image/png',
      url: '/x/a1',
    );
    const assetB = CoursewareAssetModel(
      id: 'b1',
      name: '建筑立面',
      mime: 'image/png',
      url: '/x/b1',
    );

    Future<void> openPickerWithGallery(WidgetTester tester, _FakeRepo repo) async {
      await _pumpEditor(tester, repo: repo, assets: [assetA, assetB]);
      await tester.tap(find.text('环节一'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加素材'));
      await tester.pumpAndSettle();
      expect(find.text('选择素材'), findsOneWidget);
    }

    testWidgets('picker 并列展示素材库且选择回执形状不变（asset_id）',
        (tester) async {
      final repo = _FakeRepo(_editorCourseware([
        gallery('a', '环节一', const []),
      ]));
      await openPickerWithGallery(tester, repo);

      // 「我的素材库」以缩略图网格并列展示两个素材（用语义标签定位缩略图）。
      expect(find.bySemanticsLabel('选择素材 蝴蝶标本'), findsWidgets);
      expect(find.bySemanticsLabel('选择素材 建筑立面'), findsWidgets);

      // 选择第二个 → 回执是选中的 asset id 列表，保存后落到 materials。
      await tester.tap(find.bySemanticsLabel('选择素材 建筑立面'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认（1）'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final mats = repo.lastUpdated!.first.materials;
      expect(mats.length, 1);
      expect(mats.first.assetId, 'b1');
      // 新 picker 只回传 id，新建项 caption 留空（不再从素材名派生）。
      expect(mats.first.caption, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('文件名检索框过滤素材库', (tester) async {
      final repo = _FakeRepo(_editorCourseware([
        gallery('a', '环节一', const []),
      ]));
      await openPickerWithGallery(tester, repo);

      // 输入「建筑」→ 只剩建筑立面，蝴蝶标本被过滤掉（新 picker 检索框 key 同步）。
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('asset-picker-search')),
          matching: find.byType(EditableText),
        ),
        '建筑',
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('选择素材 建筑立面'), findsWidgets);
      expect(find.bySemanticsLabel('选择素材 蝴蝶标本'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('AI 重起草逐段 diff 预览 + 逐段接受（T07）', () {
    CoursewareSectionModel secX(String id, String title, String script) =>
        _sec(id, title).copyWith(script: script);

    final secA = secX('a', '环节一', '旧话术');
    final secA2 = secX('a', '环节一', '新话术');
    final secB = _sec('b', '环节二');
    final secC = _sec('c', '环节三');
    final secD = _sec('d', '环节四(新)');

    CoursewareRedraftDiffModel diff() => CoursewareRedraftDiffModel(diff: [
          CoursewareSectionDiffModel(
            status: CoursewareSectionDiffStatus.modified,
            current: secA,
            drafted: secA2,
          ),
          CoursewareSectionDiffModel(
            status: CoursewareSectionDiffStatus.added,
            drafted: secD,
          ),
          CoursewareSectionDiffModel(
            status: CoursewareSectionDiffStatus.unchanged,
            current: secB,
          ),
          CoursewareSectionDiffModel(
            status: CoursewareSectionDiffStatus.removed,
            current: secC,
          ),
        ]);

    test('mergeRedraftChoices：默认全 true → 用新版/采用/删待删/未变留旧', () {
      final merged = mergeRedraftChoices(diff(), List.filled(4, true));
      expect(merged.map((s) => s.id).toList(), ['a', 'd', 'b']);
      expect(merged[0].script, '新话术'); // modified 取 drafted
      expect(merged.length, 3); // removed 被删
    });

    test('mergeRedraftChoices：modified 留旧版 + removed 保留 → 旧序列 + 保留项', () {
      // 索引 0=modified 选 false，1=added true，2=unchanged，3=removed 选 false。
      final choices = [false, true, true, false];
      final merged = mergeRedraftChoices(diff(), choices);
      expect(merged.map((s) => s.id).toList(), ['a', 'd', 'b', 'c']);
      expect(merged[0].script, '旧话术'); // modified 留旧
      expect(merged.last.id, 'c'); // removed 被保留
    });

    test('fromJson 往返：四种状态与嵌套环节都在', () {
      final json = {
        'diff': [
          {
            'status': 'modified',
            'current': secA.toJson(),
            'drafted': secA2.toJson(),
          },
          {'status': 'added', 'drafted': secD.toJson()},
          {'status': 'unchanged', 'current': secB.toJson()},
          {'status': 'removed', 'current': secC.toJson()},
        ],
      };
      final m = CoursewareRedraftDiffModel.fromJson(json);
      expect(m.diff.length, 4);
      expect(m.diff[0].status, CoursewareSectionDiffStatus.modified);
      expect(m.diff[1].drafted?.id, 'd');
      expect(m.diff[3].current?.id, 'c');
    });

    testWidgets(
        '编辑器：点「AI 重新起草」弹 diff 预览，逐段展示；应用后写回同一课件、不建副本',
        (tester) async {
      final repo = _FakeRepo(_editorCourseware([secA, secB, secC]));
      repo.redraftDiff = diff();
      await _pumpEditor(tester, repo: repo);

      // 弹窗前不应调用任何重起草 / 建删接口。
      expect(repo.redraftDiffCalls, 0);
      expect(repo.createCoursewareCalls, 0);

      // 打开重起草预览（走 getRedraftDiff 而非先建后删）。
      await tester.tap(find.text('AI 重新起草'));
      await tester.pumpAndSettle();
      expect(repo.redraftDiffCalls, 1);
      expect(find.text('重起草预览'), findsOneWidget);
      // 四个状态徽标 + 四个标题都出现。
      expect(find.text('修改'), findsOneWidget);
      expect(find.text('新增'), findsOneWidget);
      expect(find.text('未变'), findsOneWidget);
      expect(find.text('待删除'), findsOneWidget);
      expect(find.text('环节四(新)'), findsOneWidget);

      // 应用所选（默认全采用草稿视角）。
      await tester.tap(find.text('应用所选'));
      await tester.pumpAndSettle();

      // 写回同一课件：一次 updateSections，合并结果正确。
      expect(repo.updateSectionsCalls, 1);
      expect(repo.lastUpdated?.map((s) => s.id).toList(), ['a', 'd', 'b']);
      expect(repo.lastUpdated?.first.script, '新话术');
      // 关键：没有新建 / 删除课件副本。
      expect(repo.createCoursewareCalls, 0);
      expect(repo.deleteCoursewareCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('编辑器：diff 预览可取消，原课件不动、不落库', (tester) async {
      final repo = _FakeRepo(_editorCourseware([secA, secB, secC]));
      repo.redraftDiff = diff();
      await _pumpEditor(tester, repo: repo);

      await tester.tap(find.text('AI 重新起草'));
      await tester.pumpAndSettle();
      expect(find.text('重起草预览'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(repo.updateSectionsCalls, 0);
      expect(repo.createCoursewareCalls, 0);
      expect(repo.deleteCoursewareCalls, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('进入不自动建课件，显式发起 AI 生成（T09）', () {
    CoursewareModel emptyKpCourseware() => _editorCourseware(const []);

    testWidgets('进入无课件知识点：不自动建、显示「新增课件信息」按钮',
        (tester) async {
      // listCourseware 返回空 → 编辑器停在空态，不应自动调 createCourseware。
      final repo = _FakeRepo(emptyKpCourseware(), listReturnsEmpty: true);
      await _pumpEditor(tester, repo: repo);

      // 关键：进入页面没有自动请求 AI（createCourseware 调用计数为 0）。
      expect(repo.createCoursewareCalls, 0);
      // 空态给出下一步：主动发起按钮。
      expect(find.text('还没有课件'), findsOneWidget);
      expect(find.text('新增课件信息'), findsOneWidget);
      // 没有环节列表、没有「开始讲课」（无课件不可讲）。
      expect(find.text('开始讲课'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点「新增课件信息」触发 AI 生成并展示课件', (tester) async {
      final repo = _FakeRepo(emptyKpCourseware(), listReturnsEmpty: true);
      await _pumpEditor(tester, repo: repo);
      expect(repo.createCoursewareCalls, 0);

      await tester.tap(find.text('新增课件信息'));
      // 生成中：明确提示，且仍在忙（不会闪过空白）。
      await tester.pump();
      expect(find.text('AI 正在生成课件，请稍候…'), findsOneWidget);

      await tester.pumpAndSettle();
      // 生成完成后展示课件内容（这里假仓库返回有环节的课件）。
      expect(repo.createCoursewareCalls, 1);
      expect(find.text('新增课件信息'), findsNothing);
      expect(find.text('开始讲课'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('进入已有课件知识点：直接展示，不自动重起草', (tester) async {
      // 正常有课件：进入即展示，不应有任何 AI 触发（create/redraft 调用计数均为 0）。
      final repo = _FakeRepo(_editorCourseware([_sec('a', '环节一')]));
      await _pumpEditor(tester, repo: repo);
      expect(repo.createCoursewareCalls, 0);
      expect(repo.redraftDiffCalls, 0);
      expect(find.text('环节一'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('interactiveScene 关联知识点场景（方案 A）', () {
    CoursewareSectionModel scene(String id) => CoursewareSectionModel(
          id: id,
          kind: CoursewareSectionKind.interactiveScene,
          title: '动手画对称图形',
          payload: const {},
        );

    final reflectionSpec = <String, dynamic>{
      'kind': 'reflection',
      'title': '图形的运动（轴对称）',
      'inputs': <dynamic>[],
      'controls': <String, dynamic>{},
      'narrative': '对折演示',
      'outputs': <String, dynamic>{'isAxisymmetric': true},
      'editable': true,
    };

    // 选择器占位文案（未关联时显示）。
    final pickerTrigger = '未关联（点此选择）';

    Future<void> openSceneDialog(WidgetTester tester, _FakeRepo repo) async {
      await _pumpEditor(tester, repo: repo);
      await tester.tap(find.text('动手画对称图形'));
      await tester.pumpAndSettle();
      expect(find.text('编辑环节'), findsOneWidget);
    }

    testWidgets('交互讲解环节：对话框出现「关联知识点场景」并提供模板选择器',
        (tester) async {
      final repo = _FakeRepo(_editorCourseware([scene('a')]));
      repo.kpScenes = [reflectionSpec];
      await openSceneDialog(tester, repo);

      expect(find.text('关联知识点场景'), findsOneWidget);
      // 知识点已配置模板 → 出现下拉选择器（占位文案），而非「去知识点页配置」提示。
      expect(find.text('选择讲解模板'), findsOneWidget);
      expect(find.text(pickerTrigger), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('未配置场景：保存后 scene 为 null 且 legacy payload 清空', (tester) async {
      // 对应「按配置显示」核心契约：教师没在编辑器里关联场景时，演示页不应渲染任何
      // 交互演示。下拉选择由 SectionSceneAssociationBlock.onSelectedIndex → _onSceneSelected
      // （一行 copyWith(scene:)）负责；这里验证「保持未配置」的落库结果。
      final repo = _FakeRepo(_editorCourseware([scene('a')]));
      repo.kpScenes = [reflectionSpec];
      await openSceneDialog(tester, repo);

      // 选择器存在但未选中（占位文案），确认处于「未关联」态。
      expect(find.text(pickerTrigger), findsWidgets);
      expect(find.text('本环节已关联上方选中的交互演示。'), findsNothing);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(repo.updateSectionsCalls, 1);
      // 未配置 → 顶层 scene 为 null，legacy payload 清空。
      expect(repo.lastUpdated!.first.scene, isNull);
      expect(repo.lastUpdated!.first.payload, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('知识点未配置模板 → 提示去知识点页配置且无选择器',
        (tester) async {
      final repo = _FakeRepo(_editorCourseware([scene('a')]));
      repo.kpScenes = const []; // 未配置
      await openSceneDialog(tester, repo);

      expect(find.text('关联知识点场景'), findsOneWidget);
      expect(
        find.text('该知识点还没有配置交互讲解模板。请先到知识点页的「讲解」入口配置一份'
            '（如轴对称选图形 + 调对称轴），这里才能选到它。'),
        findsOneWidget,
      );
      expect(find.text('选择讲解模板'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('已关联（顶层 scene）后可「清除关联」，保存后 scene 为空',
        (tester) async {
      // 节本来就带一份顶层关联场景（教师此前在编辑器里选过并保存）。
      final sec = scene('a').copyWith(
        scene: Map<String, dynamic>.from(reflectionSpec),
      );
      final repo = _FakeRepo(_editorCourseware([sec]));
      repo.kpScenes = [reflectionSpec];
      await openSceneDialog(tester, repo);

      // 进入即显示已关联（模板列表里能匹配到选中项）。
      expect(find.text('本环节已关联上方选中的交互演示。'), findsOneWidget);
      await tester.tap(find.text('清除关联'));
      await tester.pumpAndSettle();
      expect(find.text('本环节已关联上方选中的交互演示。'), findsNothing);

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(repo.updateSectionsCalls, 1);
      expect(repo.lastUpdated!.first.scene, isNull);
      expect(repo.lastUpdated!.first.payload, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('内容块统一化：resolvedMaterials / resolvedScene', () {
    test('resolvedScene 只认顶层 scene，payload 内嵌不再被当场景', () {
      // 旧 mediaGallery：payload.items → resolvedMaterials 回退（素材回退保留）。
      final legacyGallery = CoursewareSectionModel(
        id: 'g',
        kind: CoursewareSectionKind.mediaGallery,
        payload: {
          'items': [
            {'asset_id': 'a1', 'caption': 'x'}
          ]
        },
      );
      expect(legacyGallery.resolvedMaterials.first.assetId, 'a1');

      // 顶层 materials 优先于 payload.items（归一化后旧数据落到顶层）。
      final mixed = legacyGallery.copyWith(
        materials: const [CoursewareMaterialItem(assetId: 'top', caption: 'y')],
      );
      expect(mixed.resolvedMaterials.first.assetId, 'top');

      // interactiveScene 仅在顶层 scene 显式配置时才渲染；payload 里的 SceneSpec
      // 不再被当作场景（演示严格「按配置显示」，杜绝「没配却显示」）。
      final legacyScene = CoursewareSectionModel(
        id: 's',
        kind: CoursewareSectionKind.interactiveScene,
        payload: {'kind': 'reflection'},
      );
      expect(legacyScene.resolvedScene, isNull);

      // 教师在编辑器关联过的顶层 scene 优先渲染。
      final configured = legacyScene.copyWith(scene: const {'kind': 'bar'});
      expect(configured.resolvedScene?['kind'], 'bar');

      // 其它 kind 的 payload 更不应被误当作场景。
      final practice = CoursewareSectionModel(
        id: 'p',
        kind: CoursewareSectionKind.practice,
        payload: {'qtype': 'choice'},
      );
      expect(practice.resolvedScene, isNull);
      expect(practice.resolvedMaterials, isEmpty);
    });
  });
}
