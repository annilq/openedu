import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_chip.dart';
import '../../../classes/presentation/screens/class_management_screen.dart';
import '../../../students/presentation/screens/student_management_screen.dart';
import '../teacher_pages.dart';

/// 合并入口「班级」内部的当前视图（ticket 10）：按班级 / 全部学生。
///
/// 视图态**不放在** [StudentsPage] 导航对象上——放进导航对象会：(1) 切页内 tab 时改变
/// `_teacherPage` 从而触发壳内换页转场（ticket 05 的 150ms 交叉淡入，不该在切页内
/// tab 时发生）；(2) 让 ADR-0059 的单一页面状态变脏。这里用一份轻量 provider 记忆
/// 当前视图：页内切换不触发转场；下钻返回后据此还原到进入前的视图。
final studentsEntryViewProvider =
    StateProvider<StudentsView>((_) => StudentsView.all);

/// 合并入口「班级」的容器页：侧栏只此一个承载学生的入口，页内以 [IndexedStack] 常驻
/// 两种视图——切换不清空「全部学生」视图的筛选与关键字（acceptance #2），且下钻返回
/// 能还原到进入前的视图（acceptance #3 / #4）。
///
/// 选中态走 [AppChip]（可聚焦动作组件，遵守「可点区域一律走可聚焦动作组件」纪律）；
/// 两种视图的取数由各自既有屏幕负责，本容器不重写任何内部排版。
class StudentsScreen extends ConsumerWidget {
  final void Function(String classId, String className) onOpenClass;
  final void Function(String studentId) onOpenStudent;
  final VoidCallback? onAddStudent;

  const StudentsScreen({
    super.key,
    required this.onOpenClass,
    required this.onOpenStudent,
    this.onAddStudent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(studentsEntryViewProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
          child: Row(
            children: [
              AppChip(
                label: '按班级',
                selected: view == StudentsView.byClass,
                onTap: () =>
                    ref.read(studentsEntryViewProvider.notifier).state =
                        StudentsView.byClass,
              ),
              const SizedBox(width: AppSpacing.sm),
              AppChip(
                label: '全部学生',
                selected: view == StudentsView.all,
                onTap: () =>
                    ref.read(studentsEntryViewProvider.notifier).state =
                        StudentsView.all,
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            // 两种视图常驻挂载：切 tab 不重建另一视图，筛选/关键字得以保留。
            index: view.index,
            children: [
              ClassManagementScreen(onOpenClass: onOpenClass),
              StudentManagementScreen(
                onOpenStudent: onOpenStudent,
                onAddStudent: onAddStudent,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
