import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/home/presentation/teacher_nav_stack.dart';
import 'package:kids_learn/features/home/presentation/teacher_pages.dart';
import 'package:kids_learn/shared/domain/models/models.dart';

/// 教师端返回栈（ADR-0059 / ticket 03）。
///
/// 钉住的是三条不变量，而不是三个方法名：
///   1. **「当前页面」只有一个状态 = 栈顶**。栈不是与它并列的第二个真源——历史上
///      「侧栏索引 + 覆盖层 + 布尔」三份状态各自记得清理，漏清就出现「点了『我的』
///      但个人信息根本没进渲染树」。这里 [TeacherNavStack.current] 是栈顶的只读
///      投影，改页面只有下钻 / 换入口 / 回退三条路，任一条都不可能让「当前页面」
///      与「历史」说不一致的话。
///   2. **根页面（概览）不能再退**。全 App 只有一个 route（ADR-0059），返回键原本
///      直接退出应用；根页必须让位给系统，否则退出能力被白白拿走。
///   3. **换一级入口清空历史**。切到「题库」后按返回若弹回上一次的班内学生页，
///      说明历史没清——那正是 P0-2 要求消除的「跨越入口的假返回」。
void main() {
  group('TeacherNavStack：当前页面 = 栈顶（唯一状态）', () {
    test('初始落在概览，且不可再退', () {
      final nav = TeacherNavStack();
      expect(nav.current, isA<OverviewPage>());
      expect(nav.canPop, isFalse);
      expect(nav.parent, isNull);
    });

    test('下钻入栈：当前页是新页、上一层是来源页', () {
      final nav = TeacherNavStack()
        ..reset(const ClassManagementPage())
        ..push(const ClassStudentsPage('c1', '三(1)班'));

      expect(nav.current, isA<ClassStudentsPage>());
      expect(nav.parent, isA<ClassManagementPage>(),
          reason: '来源页由历史决定，不需要下钻页自己声明回落目标');
      expect(nav.canPop, isTrue);
    });

    test('出栈逐级回到来源页（四级下钻链）', () {
      final nav = TeacherNavStack()
        ..reset(const ClassManagementPage())
        ..push(const ClassStudentsPage('c1', '三(1)班'))
        ..push(const StudentDetailPage('s1'))
        ..push(EditStudentPage(_student));

      // 四级下钻：班级管理 → 班内学生 → 学生详情 → 编辑学生。
      expect(nav.current, isA<EditStudentPage>());

      expect(nav.pop(), isA<StudentDetailPage>());
      expect(nav.pop(), isA<ClassStudentsPage>());
      expect(nav.pop(), isA<ClassManagementPage>());
      expect(nav.pop(), isA<OverviewPage>(),
          reason: '栈底恒为概览：回退到最后必须落在根页面，而不是把栈弹空');

      expect(nav.canPop, isFalse);
    });

    test('根页面（概览）再 pop：返回 null 且当前页不变', () {
      final nav = TeacherNavStack();
      expect(nav.pop(), isNull, reason: '根页没有历史可退，返回键应交回系统');
      expect(nav.current, isA<OverviewPage>());
    });
  });

  group('TeacherNavStack：换一级入口清空历史', () {
    test('切入口后回退落到概览，不弹回上一次的下钻页', () {
      final nav = TeacherNavStack()
        ..reset(const ClassManagementPage())
        ..push(const ClassStudentsPage('c1', '三(1)班'));

      expect(nav.current, isA<ClassStudentsPage>());

      nav.reset(const QuestionBankPage());
      expect(nav.current, isA<QuestionBankPage>());
      expect(nav.parent, isA<OverviewPage>(),
          reason: '换一级入口后历史应清空：上一层只能是概览，不能是班内学生页');
      expect(nav.pop(), isA<OverviewPage>());
      expect(nav.canPop, isFalse);
    });

    test('切回概览：栈里只剩根页面', () {
      final nav = TeacherNavStack()
        ..reset(const ClassManagementPage())
        ..push(const ClassStudentsPage('c1', '三(1)班'))
        ..reset(const OverviewPage());

      expect(nav.current, isA<OverviewPage>());
      expect(nav.canPop, isFalse);
    });
  });
}

// 编辑学生页需要一个 UserModel 入参；这里只作栈的填充值，字段无关紧要。
final UserModel _student = UserModel(
  id: 's1',
  username: '2023001',
  displayName: '小明',
  role: 'child',
);
