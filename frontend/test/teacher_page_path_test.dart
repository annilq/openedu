import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/home/presentation/teacher_pages.dart';
import 'package:kids_learn/shared/domain/models/models.dart';

/// 页面路径序列化（ticket 12，ADR-0059）。
///
/// 钉住三条不变量：
///   1. **往返稳定**：每个「直达型」页面（不持有复杂对象）`toPath → fromPath → toPath`
///      必须产出同一条路径——否则存的落点和还原的落点对不上，重启后落错页。
///   2. **复杂对象落点还原**：[EditStudentPage]（持 [UserModel]）与 [TaskReviewPage]
///      （持 [TaskModel]）不持久化对象本身，前者按 id 落点回详情页、后者回落任务列表。
///   3. **回落**：认不出的类型 / 缺失必需参数一律回 [OverviewPage]（不崩、不停空白页）。
void main() {
  final student = UserModel(
    id: 'student-uuid',
    username: 'stu',
    displayName: '小明',
    role: 'student',
  );
  final task = TaskModel(
    id: 'task-uuid',
    title: 'draft',
    status: 'draft',
    questions: [],
  );

  group('TeacherPage 路径序列化：往返稳定', () {
    // 直达型页面（不持有复杂对象）：往返后路径必须完全一致。
    final directPages = <TeacherPage>[
      const OverviewPage(),
      const CreateTaskPage(),
      const TaskListPage(),
      TaskListPage(initialTab: 2),
      const AddStudentPage(),
      const AddStudentPage(classId: 'c1', className: '三(1)班'),
      const QuestionBankPage(),
      const MaterialLibraryPage(),
      const ModelsPage(),
      const ProfilePage(),
      const StudentsPage(),
      const StudentDetailPage('s1',
          initialTab: StudentDetailTab.wrongQuestions),
      const StudentDetailPage('s2'),
      const CoursewarePage(),
      const SceneLibraryPage(),
      const SceneLibraryDetailPage('axis-symmetry'),
      const AssetLibraryPage(),
      const ClassStudentsPage('c1', '三(1)班'),
      const RunTracePage(),
      const RunTraceDetailPage('run-9'),
    ];

    for (final page in directPages) {
      test('往返稳定：${page.runtimeType}', () {
        final restored = teacherPageFromPath(page.toPath());
        expect(restored.toPath(), page.toPath(),
            reason: '${page.toPath()} 还原后必须能再次产出同一路径');
      });
    }
  });

  group('TeacherPage 路径序列化：复杂对象落点还原', () {
    test('EditStudentPage → StudentDetailPage（按 id 还原，不复活编辑表单）', () {
      final path = EditStudentPage(student).toPath();
      expect(path, 'edit-student?studentId=student-uuid');
      final restored = teacherPageFromPath(path);
      expect(restored, isA<StudentDetailPage>());
      final detail = restored as StudentDetailPage;
      expect(detail.studentId, 'student-uuid');
      // 还原到详情页默认概览页签，而非直接复活编辑态。
      expect(detail.initialTab, StudentDetailTab.overview);
    });

    test('TaskReviewPage → TaskListPage（近提交态不予复活）', () {
      final path = TaskReviewPage(task).toPath();
      expect(path, 'review?taskId=task-uuid');
      final restored = teacherPageFromPath(path);
      expect(restored, isA<TaskListPage>());
    });
  });

  group('TeacherPage 路径序列化：回落', () {
    test('完全不认识的路径 → 概览', () {
      expect(teacherPageFromPath('totally-unknown-type'),
          isA<OverviewPage>());
    });
    test('空字符串 → 概览', () {
      expect(teacherPageFromPath(''), isA<OverviewPage>());
    });
    test('student-detail 缺 studentId → 概览', () {
      expect(teacherPageFromPath('student-detail?tab=overview'),
          isA<OverviewPage>());
    });
    test('scene-detail 缺 kind → 概览', () {
      expect(teacherPageFromPath('scene-detail'), isA<OverviewPage>());
    });
    test('class-students 缺 className → 概览', () {
      expect(teacherPageFromPath('class-students?classId=c1'),
          isA<OverviewPage>());
    });
    test('run-trace-detail 缺 runId → 概览', () {
      expect(teacherPageFromPath('run-trace-detail'), isA<OverviewPage>());
    });
    test('tasks tab 非数字 → 回落默认 0', () {
      final restored = teacherPageFromPath('tasks?tab=abc');
      expect(restored, isA<TaskListPage>());
      expect((restored as TaskListPage).initialTab, 0);
    });
    test('student-detail tab 非法枚举 → 回落 overview', () {
      final restored =
          teacherPageFromPath('student-detail?studentId=s1&tab=nope');
      expect(restored, isA<StudentDetailPage>());
      expect((restored as StudentDetailPage).initialTab,
          StudentDetailTab.overview);
    });
  });
}
