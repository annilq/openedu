/// 由生成规格反推「应出题数」（ADR-0057）。
///
/// 少题（[isUnderdelivered]）此前只活在出题那一刻的前端 state
/// （`TaskGenSuccess.expected`），一旦落库就蒸发了——家长隔天打开草稿页完全看不出
/// 这份少题，而少题的草稿派发出去就是一份少题的作业。
///
/// 其实草稿页自己算得出来：`Task.specs` 是持久化的（后端 `db/models/task.py`），
/// `TaskResp.specs` 也回传了，前端 [TaskModel.specs] 接着。所以这里不需要后端新增
/// 任何字段——把「应出题数」从一次性 state 变成一个随时可重算的纯函数。
library;

import '../../../shared/domain/models/models.dart';

/// 应出题数：各条规格 `count` 之和。**0 表示未知**（无规格，或规格里没写题数），
/// 调用方必须把 0 当作「不校验」，而不是「应出 0 题」。
int expectedQuestionCount(List<TaskSpecModel> specs) =>
    specs.fold<int>(0, (sum, s) => sum + s.count);

/// 是否少题：应出题数已知且实际题数不足。
///
/// [expected] 显式传入而非内部重算，是为了让「已生成但尚未落库」的预览态也能复用
/// 同一判据（那时应出题数来自本次请求，而不是已落库的 specs）。
bool isUnderdelivered({required int expected, required int actualCount}) =>
    expected > 0 && actualCount < expected;
