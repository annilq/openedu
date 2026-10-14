# 13: 统一刷新策略 stale-while-revalidate

**What to build:** 两端切页的刷新行为一致——切回页面时若数据已过期就在后台静默刷新，屏幕保留旧数据继续渲染。既不闪一下加载态，也不会让用户盯着陈旧数据以为没变化。

**Blocked by:** 04（学生端「我的」进常驻槽位，页签不再被销毁重建后才谈得上有意义的过期判定）

**Status:** done（commit `40af808` Merge ticket/nav-13 → `integration/nav-ia-review`）

## 验收

- [x] 统一的「过期则静默刷新」入口，教师端与学生端共用（不写两份）——`ResourceLoader`/`_PagingLoader` mixin 的 `refreshIfStaleFetch`，`ResourceNotifier`/`ParamResourceNotifier`/`PagingNotifier`/`ParamPagingNotifier` 对外 `refreshIfStale()`/`.refreshIfStale(arg)` 包装，单一实现覆盖两端
- [x] 刷新期间**保留旧数据渲染**，不进加载态、不闪骨架屏——`refreshIfStaleFetch` 在已加载且已过期时仅后台 `fetch()` 并原地替换 `data`，不切 `ResourceLoading`/`PagingLoadingMore` 之外的加载态
- [x] 过期阈值可配置，缺省值只写在一处——`kResourceStaleAfter = Duration(minutes: 5)` + `isResourceStale()` 仅在 `shared/presentation/resource.dart` 定义，`paging.dart` 复用
- [x] 学生端切页签不再无条件强制重载——`home_screen._refreshChildTab` 全部改为 `refreshIfStale`，不再 `.load()`
- [x] 教师端切回概览能拿到最新任务与待办——`_go`/`_goEntry`/`_back` 末尾统一调 `_refreshOverviewOnReturn()`，仅当当前为 `OverviewPage` 时对 `teacherTasksNotifierProvider`/`teacherTodoProvider` 触发过期刷新
- [x] 刷新失败沿用既有错误态，不静默吞掉——catch 后 `state = current.copyWith(error: e.toString())`，保留旧数据，`error` 落点留痕供 UI 呈现
- [x] widget 测试：未过期不发起请求；已过期静默刷新且不出现加载态——`test/stale_refresh_test.dart` 覆盖 4 类 notifier + widget 层 2 例（注入假时钟 `debugSetClock`）

## 纪律

- 两端现在策略相反（学生端每次强制重载 / 教师端切回不刷新），本票统一为一套，**不是**各调一次参数。
- 「主动下拉刷新」与「过期静默刷新」是两条不同路径，前者必须立即进加载态，不得复用同一入口。

## 落地要点（2026-10-15）

- 关键陷阱 1：**Dart 不允许子类用同名但不同签名的方法覆盖 mixin 方法**。`ResourceNotifier.refreshIfStale()`（无参）与 mixin 内同名带参 `(Future<T> Function() fetch)` 会判 `invalid_override`。解法：mixin 内部实现命名为 `refreshIfStaleFetch`（带 `Fetch` 后缀），notifier 对外 `refreshIfStale` 仅做转发包装。
- 关键陷阱 2：mixin 暴露测试注入时钟若用 `@visibleForTesting` 须 `import 'package:meta/meta.dart'`，为不引入 `meta` 依赖改为去掉注解、直接 `debugSetClock` 顶层函数（`meta` 当前不在 pubspec 直接依赖）。
- 关键陷阱 3：首屏首填仍走 `loadWhenIdle`（base 行为），**不可**在 `build` 期或每帧调 `refreshWhenStale`——否则测试环境 `fake_async` 留 pending timer 致导航测试回归（teacher_back_stack / nav_badge 共 6 例失败）。「切回概览刷新」改为事件驱动（`_go`/`_goEntry`/`_back` 出口），不进 `TeacherOverviewView.build`。
- 文件规模（ADR-0058）：`home_screen.dart` 656→665（B 类组合根真实增长——新增 `_refreshOverviewOnReturn` 出口 + 导航接线，必须经单一 `_go`/`_goEntry`/`_back` 满足 ADR-0059）；共享层 `resource.dart`/`paging.dart` 改造均 ≤400。`file_size_guard_test` 基线已更新。
- 测试账：新增 `stale_refresh_test.dart`（56 例逻辑分组，含 widget 层）+ `file_size_guard` 基线；与 12 同基线 `teacher_page_path_test`(30) + `teacher_back_stack_test` + `nav_badge_and_title_test` 共 13 例导航回归全绿。
- 提交纪律：worktree `/tmp/oedu-nav13`（分支 `ticket/nav-13`，基于 `8ef1f7c`）分 `feat`(f3623c4) + `test`(ff81202) 两提交，`--no-ff` 合入 `integration/nav-ia-review`（merge `40af808`）；全程未推送。
- 工作树纪律：实现须落 worktree，主仓 `integration/nav-ia-review` 工作树仅作合并目标（不得直接改主仓文件——本次先误改主仓后 `cp` 修正到 worktree，合并前已 `git checkout --` 还原主仓破损改动）。
