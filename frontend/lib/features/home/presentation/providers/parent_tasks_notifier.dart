import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/presentation/paging.dart';
import '../../providers/home_provider.dart';

/// 三个 Tab 对应的后端状态过滤值（ADR-0053）。
///
/// 「草稿」Tab 实际是 draft + ready 两个状态——ready 是「已锁定待派发」，对家长
/// 来说和草稿一样还没发出去。分页之后**不能**在客户端过滤（那样只会过滤已加载的
/// 页，Tab 会漏数据），所以把 Tab 语义下推到服务端，一次查询 + 一次计数。
const List<String> kParentTaskTabStatuses = ['draft,ready', 'assigned', 'done'];

/// 「全部状态」：概览页的「最近任务」用（不限 Tab）。
const String kAllTaskStatuses = '';

/// 家长任务列表（游标分页，ADR-0053）。
///
/// 此前是 `ResourceNotifier<List<TaskModel>>`：一次拉全量，且每个任务内嵌全部题目
/// （载荷 O(任务数 × 题数)）。现在首屏一页、触底追加，列表项只带题目数。
/// 加载 / 错误 / 追加失败的处理全在 [ParamPagingNotifier] 里，这里只提供「去哪儿取」。
///
/// 入参是 Tab 的状态过滤值（[kParentTaskTabStatuses]）——换 Tab 就是换一次查询，
/// 与换筛选条件等价。
final parentTasksNotifierProvider = StateNotifierProvider<
    ParamPagingNotifier<TaskModel, String>, PagingState<TaskModel>>(
  (ref) => ParamPagingNotifier<TaskModel, String>(
    (statuses, {cursor}) => ref
        .watch(tasksRepositoryProvider)
        .parentTasks(status: statuses, cursor: cursor),
  ),
);

/// 从分页状态里取三个 Tab 的状态计数。
///
/// 计数由服务端随每页响应下发（否则徽标只能统计已加载页）。取到的页不是
/// [TaskPage] 时（非任务接口，理论不会）退回全 0。
TaskCounts taskCountsOf(PagingState<TaskModel> state) => switch (state) {
      PagingLoaded<TaskModel>(page: final p) =>
        p is TaskPage ? p.counts : const TaskCounts(),
      _ => const TaskCounts(),
    };
