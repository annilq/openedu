# 05: 画廊按需拉取（不缓存）

**What to build:** 画廊打开时从后端拉一次图库、用完即弃，不写本地磁盘/内存缓存。与 04 画板共享同一图库数据源。

**Blocked by:** 01（读端点依赖图库表）, 02（渲染依赖新 SceneSpec 几何）

**Status:** done

## 验收
- [x] 画廊打开触发 `GET /scene-library/figures` 一次。
- [x] 拉取结果仅用于本次渲染；页面关闭/进程退出后不残留本地缓存（无磁盘写入、无跨会话内存持留）。
- [x] 画廊使用与 04 同一图库源渲染（内置 `is_builtin=true` + 用户行）。
- [x] 不重复请求：同一会话内二次打开不重新拉取（仅会话内一次性，非落盘缓存）。

## 落地记录
范围界定：ADR-0083 决策 7 把「画廊」限定为**创作 UI**（「图库只在画板/画廊这类创作 UI
打开时按需 GET」）。故本轮接入：**画板工具栏 + 场景库「默认演示图形」+ 知识点交互讲解
编辑器**三处画廊。运行时的选项组画廊（`SceneOptionGroup` 非 curated 的整库铺开）**未动**
——它必须零图库依赖（题库/错题/AI 讲解观感一字不变），交由 **T06 收口**（见下方移交）。

- 新增 `shared/domain/figure_library.dart`：DB 行（`points` + `label` + `is_builtin`，**无 axis**）
  → `FigureShape`；顶点不足 / key 缺失的行跳过（不显示渲染不出来的空卡）。解析刻意**不写进
  `figures.dart`**（`gen_figures.py` 产物，T06 退役；手写内容会被生成器覆盖并打破 parity 锁）。
- 新增 `shared/domain/providers/figure_library_provider.dart`：`figureLibraryProvider`
  （`FutureProvider` 非 autoDispose）。三条纪律：①**懒加载**——启动期不拉（运行时零图库依赖）；
  ②**会话内一次性**——同一 ProviderScope 二次读取不重复请求；③**不落盘**——进程退出即失。
  选址 `shared`（跨 feature 共享，与 `figures.dart` 同理），避免 courseware→home 横向依赖。
- 新增 `shared/widgets/scene_interpreter/figure_library_gallery.dart`：`FigureLibraryGallery`
  ——取数薄层，拉取中给占位、失败给「重试」（`ref.invalidate`）、成功渲染**哑组件**
  `ReflectionFigureGallery`（后者保持「只吃图形列表」，便于显式子集与测试直构）。
- 接线：`scene_library_view`（打开画板前 `await` provider → 注入 `presets`；保存成功
  `invalidate` 一次让新行可见）、`scene_library_default_figure_section`、`knowledge_point_scene_editor`。
- 新增 13 条测试（`test/figure_library_provider_test.dart`）：解析（含坏行/类型错）、懒加载、
  读一次、会话内二次不重复、换容器重拉（= 不落盘）、invalidate 重拉、失败进 error 态、
  画廊 widget 打开即拉 + 渲染内置/用户行、失败给重试。

## 移交给 T06（收口）
- `SceneOptionGroup` 非 curated 分支仍用 `kFigureShapes` 铺整库；`kFigureShapes` 退役时
  必须同步处理（要么走 `figureLibraryProvider` 取数，要么改为只渲染 spec 内联的条目——
  后者才是 ADR-0083 决策 7「运行时渲染零图库依赖」的字面读法，需在 T06 拍板）。
- `section_scene_figures_picker`（课件挑图形，自绘 tile 网格而非画廊）与
  `scene_library_default_figure_section._set` 的 `figureByKey(...).label` 仍依赖 `kFigureShapes`。
- `reflection_scene.dart` 的 `_baseline`（567）可随本轮 438 行下调。
