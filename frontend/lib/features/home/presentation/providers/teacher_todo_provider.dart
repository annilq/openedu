import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/task.dart';
import '../../../../shared/presentation/resource.dart';
import '../../providers/home_provider.dart';

/// 教师工作台待办聚合（ticket 20）：待审核 / 待派发 / 谁没交。
///
/// 服务端一次性聚合返回，客户端只渲染，不自行统计分页（避免徽标漏数，ADR-0053 同款陷阱）。
/// 加载态统一用共享的 [Resource<T>]（LCC-08）：Idle/Loading → 骨架占位，Error → 重试，
/// Loaded → 三卡。取数逻辑下沉到 [ResourceNotifier._run]，不再手写 4 态 sealed 类。
final teacherTodoProvider = StateNotifierProvider<
    ResourceNotifier<TeacherTodoSummary>,
    Resource<TeacherTodoSummary>>(
  (ref) => ResourceNotifier(
    () => ref.watch(tasksRepositoryProvider).teacherTodoSummary(),
  ),
);
