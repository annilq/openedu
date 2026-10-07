// 学生管理页（ticket 02）在「不套 Material」的树里真构建一次（ADR-0044：全仓禁用
// Material 控件，整棵树无 Material 祖先，否则 `flutter analyze` 照不出来、只有真机构建
// 才炸）。同时验证分组 / 筛选入口 / 活跃错题数展示这些核心验收点。
//
// 取数由桩 repository 接管（不碰真实网络），只验证 UI 层。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/classes/domain/models/class_model.dart';
import 'package:kids_learn/features/classes/domain/repositories/classes_repository.dart';
import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import 'package:kids_learn/features/students/domain/repositories/students_repository.dart';
import 'package:kids_learn/features/students/presentation/screens/student_management_screen.dart';
import 'package:kids_learn/features/students/providers/students_provider.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

/// 桩：只实现管理页用到的三个取数方法，其余走 noSuchMethod（不会被执行到）。
class _FakeStudentsRepo implements StudentsRepository {
  final List<UserModel> students;
  final Map<String, int> counts;
  _FakeStudentsRepo(this.students, this.counts);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();

  @override
  Future<List<UserModel>> getStudents({
    String? classId,
    String? keyword,
  }) async =>
      students;

  @override
  Future<Map<String, int>> getWrongQuestionCounts() async => counts;
}

class _FakeClassesRepo implements ClassesRepository {
  final List<ClassModel> classes;
  _FakeClassesRepo(this.classes);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();

  @override
  Future<List<ClassModel>> getClasses() async => classes;
}

void main() {
  final classes = [
    ClassModel(id: 'c1', name: '三(1)班', grade: 3, studentCount: 2),
    ClassModel(id: 'c2', name: '三(2)班', grade: 3, studentCount: 1),
  ];
  final students = [
    UserModel(
        id: 's1',
        username: '2023001',
        displayName: '小明',
        role: 'child',
        grade: 3,
        classId: 'c1'),
    UserModel(
        id: 's2',
        username: '2023002',
        displayName: '小红',
        role: 'child',
        grade: 3,
        classId: 'c1'),
    UserModel(
        id: 's3',
        username: '2023003',
        displayName: '小刚',
        role: 'child',
        grade: 3,
        classId: 'c2'),
    UserModel(
        id: 's4',
        username: '2023004',
        displayName: '未分班学生',
        role: 'child',
        grade: 3,
        classId: null),
  ];
  final counts = {'s1': 2, 's2': 0, 's3': 1, 's4': 5};

  Future<void> pumpScreen(
    WidgetTester tester, {
    required void Function(String) onOpenStudent,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          studentsRepositoryProvider
              .overrideWithValue(_FakeStudentsRepo(students, counts)),
          classesRepositoryProvider
              .overrideWithValue(_FakeClassesRepo(classes)),
        ],
        child: ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
          appBuilder: (context) => CupertinoApp(
            home: StudentManagementScreen(onOpenStudent: onOpenStudent),
          ),
        ),
      ),
    );
    await tester.pump();
    // 等 initState 的 postFrameCallback + 取数 future 落定。
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('在不套 Material 的树里真构建，并按班级分组 + 展示活跃错题数',
      (tester) async {
    final opened = <String>[];
    await pumpScreen(tester, onOpenStudent: opened.add);

    expect(tester.takeException(), isNull,
        reason: '整棵树无 Material 祖先，构建不应抛 "No Material widget found"');
    expect(find.text('学生管理'), findsOneWidget);

    // 三个分组头都出现：两个真实班级 + 未分班。
    expect(find.text('三(1)班'), findsWidgets);
    expect(find.text('三(2)班'), findsWidgets);
    expect(find.text('未分班'), findsWidgets);

    // 学生姓名与学号展示。
    expect(find.text('小明'), findsOneWidget);
    expect(find.text('学号 2023001'), findsOneWidget);

    // 活跃错题数醒目展示（s1 有 2 道）。
    expect(find.text('2 道错题'), findsOneWidget);
    expect(find.text('无错题'), findsOneWidget); // s2 为 0

    // 行内入口：点学生行跳详情页。
    await tester.tap(find.text('小明'));
    await tester.pump();
    expect(opened, contains('s1'));
  });

  testWidgets('搜索与班级筛选入口渲染（不抛错）', (tester) async {
    await pumpScreen(tester, onOpenStudent: (_) {});
    // 搜索框 label 与筛选 chip（全部 / 各班 / 未分班）。
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('全部'), findsWidgets);
    expect(find.text('未分班'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
