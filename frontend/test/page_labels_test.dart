import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/child_pages.dart';
import 'package:kids_learn/features/home/presentation/page_labels.dart';
import 'package:kids_learn/features/home/presentation/providers/home_notifier.dart';
import 'package:kids_learn/features/home/presentation/screens/teacher_destinations.dart';
import 'package:kids_learn/features/home/presentation/teacher_pages.dart';
import 'package:kids_learn/shared/domain/models/models.dart';

/// 页面门面映射表的守卫（ticket 01 / ADR-0059）。
///
/// 测两件事，都是 `flutter analyze` 照不出来的：
///
/// 1. **登记完整**：`TeacherPage` / `ChildPage` 的每个子类都要在映射表里出现。
///    映射本身是穷尽 `switch`（漏一个编译就红），但那要求没人偷偷塞 `_ =>` 兜底——
///    一旦塞了，「新增页面忘记登记」就会从编译失败退化成运行时显示空白，正是本票
///    要消灭的失效模式。这里逐个断言标题非空，兜底一旦偷偷回来立刻红。
/// 2. **纯搬移**：菜单取到的标题 / 图标必须与搬移前逐字一致。期望值写死为搬移前
///    `teacher_destinations.dart` 里的字面量（独立事实源，不是从被测对象算出来的），
///    这样「顺手改个名字」会在这一条上暴露——改名是 07 的活，01 不许顺手做。
const String _labelsFile = 'lib/features/home/presentation/page_labels.dart';
const String _teacherPagesFile = 'lib/features/home/presentation/teacher_pages.dart';
const String _childPagesFile = 'lib/features/home/presentation/child_pages.dart';
const String _destinationsFile =
    'lib/features/home/presentation/screens/teacher_destinations.dart';

void main() {
  group('登记完整性：每个页面都有一份门面', () {
    test('TeacherPage 的每个子类都在映射表里出现', () {
      _expectEverySubclassListed(_teacherPagesFile);
    });

    test('ChildPage 的每个子类都在映射表里出现', () {
      _expectEverySubclassListed(_childPagesFile);
    });

    test('每个教师端页面都有非空标题（防止用 _ => 兜底架空穷尽匹配）', () {
      for (final page in _everyTeacherPage) {
        final face = teacherPageFace(page);
        expect(face.title.trim(), isNotEmpty,
            reason: '${page.runtimeType} 没有标题——映射里是不是加了 `_ =>` 兜底？');
      }
    });

    test('每个学生端页面都有非空标题', () {
      for (final page in _everyChildPage) {
        final face = childPageFace(page);
        expect(face.title.trim(), isNotEmpty,
            reason: '${page.runtimeType} 没有标题');
      }
    });
  });

  group('单一映射：菜单不再自带标题字面量', () {
    test('目的地构造器里不再出现任何硬编码的中文标题', () {
      final src = File(_destinationsFile).readAsStringSync();
      const banned = [
        ..._teacherSidebarLabels,
        '我的',
        '首页',
        '复习',
        '错题本',
        '掌握度',
      ];
      // 只认「带引号的字面量」：本文件保留了大量中文**注释**（纪律要求的为什么），
      // 它们用「」而非引号书写，故这条断言不会因为注释而误报。
      final leftover = banned.where((l) => src.contains("'$l'")).toList();
      expect(
        leftover,
        isEmpty,
        reason: '标题必须只存在于 $_labelsFile 一处，$leftover 还在这里写着第二份。'
            '两处并存时改名票（07）改一处漏一处，界面就会显示两个不同的名字。',
      );
    });
  });

  group('纯搬移：菜单的门面与搬移前逐字一致', () {
    test('教师端侧栏 11 项：顺序、标题、图标都不变', () {
      final dests = _destinations().teacher(const OverviewPage(), const TaskGenIdle());

      expect(dests.expand((s) => s.items).map((d) => d.label).toList(),
          _teacherSidebarLabels,
          reason: '侧栏标题必须逐字保持搬移前的字面量（改名留给 07）');
      expect(dests.expand((s) => s.items).map((d) => d.icon).toList(),
          _teacherSidebarIcons,
          reason: '侧栏图标必须保持搬移前的 Lucide 图标');
    });

    test('出题中（生成页）「任务」项仍叫「任务」，不变成生成页自己的标题', () {
      final dests = _destinations().teacher(
        const CreateTaskPage(),
        const TaskGenPreview([], streaming: true),
      );
      final labels = dests.expand((s) => s.items).map((d) => d.label).toList();

      expect(labels, _teacherSidebarLabels,
          reason: '生成页不是侧栏入口，它只把「任务」点亮；标题不能随它的落点变化');
      expect(
          dests.expand((s) => s.items).firstWhere((d) => d.label == '任务').active,
          isTrue);
    });

    test('学生端 4 个页签：顺序、标题、图标都不变', () {
      final dests = _destinations().child(0);

      expect(dests.expand((s) => s.items).map((d) => d.label).toList(),
          ['首页', '复习', '错题本', '掌握度']);
      expect(dests.expand((s) => s.items).map((d) => d.icon).toList(), [
        LucideIcons.house,
        LucideIcons.refreshCw,
        LucideIcons.bookOpen,
        LucideIcons.target,
      ]);
      // 高亮仍按下标判定，只亮当前页签一个。
      expect(dests.expand((s) => s.items).map((d) => d.active).toList(),
          [true, false, false, false]);
      expect(_destinations().child(2).expand((s) => s.items).map((d) => d.active).toList(),
          [false, false, true, false]);
    });

    test('「我的」对两个角色都是同一份「我的」', () {
      final profile = _destinations().profile(active: true);
      expect(profile.label, '我的');
      expect(profile.icon, LucideIcons.userRound);
      expect(profile.active, isTrue);
    });
  });

  group('下钻页用自身的口径，不用父级口径', () {
    test('六类下钻页各有自己的标题', () {
      expect(teacherPageFace(_review).title, '草稿审核',
          reason: '草稿审核是独立页面，标题不能用父级「任务」');
      expect(teacherPageFace(EditStudentPage(_student)).title, '编辑学生');
      expect(teacherPageFace(const StudentDetailPage('s1')).title, '学生详情');
      expect(teacherPageFace(const SceneLibraryDetailPage('graph')).title, '场景库详情');
      expect(teacherPageFace(_sceneEditor).title, '场景编辑器');
      expect(teacherPageFace(const RunTraceDetailPage('r1')).title, '运行轨迹详情');
    });

    test('班级下钻页标题就是班级名（页面上显示的那个名字）', () {
      expect(
        teacherPageFace(const ClassStudentsPage('c1', '三(1)班')).title,
        '三(1)班',
        reason: '下钻页自身以班级名为标题，跟随页面显示而非写死通用名',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// 期望值：搬移前 `teacher_destinations.dart:37-103` 里的原字面量（独立事实源）。
// ---------------------------------------------------------------------------

const List<String> _teacherSidebarLabels = [
  '概览',
  '任务',
  '学生',
  '班级管理',
  '题库',
  '课件',
  '场景库',
  '备课资料',
  '图片素材',
  '模型管理',
  '运行轨迹',
];

const List<IconData> _teacherSidebarIcons = [
  LucideIcons.layoutDashboard,
  LucideIcons.listTodo,
  LucideIcons.users,
  LucideIcons.school,
  LucideIcons.library,
  LucideIcons.bookOpen,
  LucideIcons.component,
  LucideIcons.folderOpen,
  LucideIcons.images,
  LucideIcons.cpu,
  LucideIcons.route,
];

NavigationDestinations _destinations() => NavigationDestinations(
      goEntry: (_) {},
      goChildTab: (_) {},
      goProfile: () {},
      genTrailing: (_) => null,
    );

/// 每个 sealed 子类一个代表实例——登记完整性按子类名由静态扫描兜底，这里按
/// 「每个都得能用」兜底。
final List<TeacherPage> _everyTeacherPage = [
  const OverviewPage(),
  const CreateTaskPage(),
  const TaskListPage(),
  const AddStudentPage(),
  EditStudentPage(_student),
  const QuestionBankPage(),
  const MaterialLibraryPage(),
  const ModelsPage(),
  _review,
  const ProfilePage(),
  const StudentManagementPage(),
  const StudentDetailPage('s1'),
  const CoursewarePage(),
  const SceneLibraryPage(),
  const SceneLibraryDetailPage('graph'),
  _sceneEditor,
  const AssetLibraryPage(),
  const ClassManagementPage(),
  const ClassStudentsPage('c1', '三(1)班'),
  const RunTracePage(),
  const RunTraceDetailPage('r1'),
];

final List<ChildPage> _everyChildPage = const [
  ChildHomePage(),
  ChildReviewPage(),
  ChildWrongQuestionsPage(),
  ChildMasteryPage(),
  ChildProfilePage(),
];

final UserModel _student = UserModel(
  id: 's1',
  username: '2023001',
  displayName: '小明',
  role: 'child',
);

final TaskReviewPage _review = TaskReviewPage(
  TaskModel(id: 't1', title: '练习', status: 'draft', questions: const []),
);

final SceneLibraryEditorPage _sceneEditor = SceneLibraryEditorPage(
  kpId: 'k1',
  kpName: '轴对称',
  subject: '数学',
  grade: 4,
  semester: '上学期',
);

/// 扫描 [pagesFile] 里 `class X extends <sealed>` 的子类名，逐个确认它们出现在
/// 映射表的开关分支里。
///
/// 编译期穷尽性只保证「每个分支都处理到了」，不保证「每个子类都登记了一份真文案」——
/// 有人为了消编译错误塞 `_ => (title: '', icon: ...)` 时，这条静态扫描会先红。
void _expectEverySubclassListed(String pagesFile) {
  final declared = RegExp(
    r'^class\s+(\w+)\s+extends\s+(?:TeacherPage|ChildPage)\b',
    multiLine: true,
  )
      .allMatches(File(pagesFile).readAsStringSync())
      .map((m) => m.group(1)!)
      .toList();
  final src = File(_labelsFile).readAsStringSync();

  expect(declared, isNotEmpty, reason: '$pagesFile 里没扫到任何 sealed 子类');
  final missing = declared.where((name) => !src.contains('$name(')).toList();
  expect(
    missing,
    isEmpty,
    reason: '以下页面类型没有在 $_labelsFile 里登记：$missing。'
        '缺一行 = 顶栏 / 路径恢复将来会显示空白（ticket 12 的直接失效模式）。',
  );
}
