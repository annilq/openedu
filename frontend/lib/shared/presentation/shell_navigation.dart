import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 导航壳的目的地（跨页请求用）。
///
/// **为什么需要这条通道**：家长端 AI 助手是 `Navigator.push` 出来的**整页**
/// （ADR-0047），它不在壳的导航上下文里；而助手里的一张引导卡可能要请用户去
/// 「布置任务」页。整页既够不着壳的 Tab 索引，也不该知道壳的索引编号，
/// 于是把「想去哪」声明成一个意图交给壳消费。
///
/// 值的语义是**目的地**，不是**动作**：`request` 只表达「请把我带到 X」，
/// 到不到、怎么到由壳决定（例如已在该页就不动）。
enum ShellDestination {
  /// 家长端「布置任务」页。
  parentCreateTask,

  /// 家长端「任务」列表页。
  parentTaskList,

  /// 家长端「题库」页。
  parentQuestionBank;

  /// 线协议 target（后端 `guide/agent.py` 的 `TARGET_*`）→ 目的地。
  ///
  /// 认不出返回 null——**未知 target 必须什么也不做**。后端的 target 是受控枚举，
  /// 前端悄悄兜底会让「协议新增了值、前端还没跟上」表现为「点了一个莫名其妙的
  /// 按钮」，而不是一个能被守卫测出来的失败。
  static ShellDestination? fromTarget(String target) => switch (target) {
        'parent_create_task' => ShellDestination.parentCreateTask,
        'parent_task_list' => ShellDestination.parentTaskList,
        'parent_question_bank' => ShellDestination.parentQuestionBank,
        _ => null,
      };
}

/// 壳导航意图：由壳外页面（push 的整页）写入，壳消费后清空。
class ShellNavigationNotifier extends StateNotifier<ShellDestination?> {
  ShellNavigationNotifier() : super(null);

  void request(ShellDestination destination) => state = destination;

  /// 消费后清空——不清的话下一次 rebuild 会把同一次跳转再触发一遍。
  void consume() => state = null;
}

final shellNavigationProvider =
    StateNotifierProvider<ShellNavigationNotifier, ShellDestination?>(
  (ref) => ShellNavigationNotifier(),
);
