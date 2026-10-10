import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 文件规模静态守卫（ADR-0058）。
///
/// 「一个文件装什么 / 多大」不是类型问题，`flutter analyze` 照不出来，只能静态扫。
/// 本守卫只做两件事：
///
/// 1. **未登记的新文件不得超过 400 行**——这是 ADR-0058 的主要执行力：它拦不住
///    历史债务，但能拦住**下一个** `teacher_question_bank_view.dart`（现已拆出
///    `BankQuestionRow`，基线随之下调到 759）。
/// 2. **已登记的超限文件不得继续增长**（棘轮）——现存 **13** 个超限文件登记在
///    [_baseline] 里（另 `dev/theme_preview.dart` 1189 行走豁免），基线**只许下调不许上调**：
///    拆小了把基线跟着调小，长回去就失败。
///    它不强迫任何人现在就去拆分，但保证这些文件不会继续变长。
///
/// 为什么用「棘轮」而不是「一次性把 16 个文件都拆完」：ADR-0044 定下的纪律是
/// **渐进迁移，禁止一次性全量重做**。棘轮让债务单向收缩——每拆掉一个文件，
/// 就把 [_baseline] 里那一条删掉（第 3 条断言会在它降到 400 以下时提醒你删）。
///
/// 有意增长某个已登记文件时（例如往 `app_theme.dart` 加一个令牌），必须同步调高
/// 基线并在 commit 正文说明理由——这个摩擦是故意的。
///
/// 豁免：`lib/dev/**`（视觉走查台，长是它的天性，见 ADR-0058 §1）与生成代码
/// （`*.g.dart` / `*.freezed.dart`）。
void main() {
  /// 单行软阈值。
  const int maxLines = 400;

  test('未登记的文件不得超过 400 行（ADR-0058）', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: '请在 frontend/ 目录下运行（flutter test 的 CWD 应为 frontend/）');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !_isDart(entity.path)) continue;
      final rel = _rel(entity.path);
      if (_isExempt(rel) || _baseline.containsKey(rel)) continue;
      final n = entity.readAsLinesSync().length;
      if (n > maxLines) offenders.add('$rel: $n 行');
    }

    expect(
      offenders,
      isEmpty,
      reason: '新文件不得超过 $maxLines 行（ADR-0058 §1）。超了说明这个文件装了\n'
          '不止一个职责——按 §2/§4 拆：Page → Section → Widget，一个文件只暴露\n'
          '一个公开物。确属例外（dev 走查台 / 生成代码）请加进豁免或 [_baseline]。\n'
          '超限文件：\n${offenders.join('\n')}',
    );
  });

  test('已登记的超限文件不得继续增长（ADR-0058 棘轮）', () {
    final grown = <String>[];
    for (final entry in _baseline.entries) {
      final file = File('lib/${entry.key}');
      if (!file.existsSync()) {
        grown.add('${entry.key}: 文件已不存在，请从 _baseline 删除该条');
        continue;
      }
      final n = file.readAsLinesSync().length;
      if (n > entry.value) {
        grown.add('${entry.key}: $n 行 > 基线 ${entry.value} 行');
      }
    }

    expect(
      grown,
      isEmpty,
      reason: '基线只许下调不许上调。要么把多出来的职责拆出去（然后调低基线），\n'
          '要么在 commit 正文说明为什么这个文件必须变长、并同步调高基线。\n'
          '${grown.join('\n')}',
    );
  });

  test('已降到阈值以下的条目必须从 _baseline 删除（ADR-0058 棘轮）', () {
    final stale = <String>[];
    for (final entry in _baseline.entries) {
      final file = File('lib/${entry.key}');
      if (!file.existsSync()) continue; // 上一条断言已报告
      final n = file.readAsLinesSync().length;
      if (n <= maxLines) {
        stale.add('${entry.key}: 已降到 $n 行，请从 _baseline 删除该条');
      }
    }

    expect(
      stale,
      isEmpty,
      reason: '拆完了就要删登记，否则棘轮会停在旧高度、允许它再长回去。\n'
          '${stale.join('\n')}',
    );
  });
}

/// 现存超限文件的基线（2026-09-21 实测；2026-10-04 补登 reflection_scene.dart；
/// 2026-10-05 拆出 BankQuestionRow 后下调 teacher_question_bank_view 838→759；
/// 2026-10-07 删除已不存在的 teacher_student_selector 登记、student_management_screen 771→775；
/// 补登 2 个此前提交（courseware 等）已落地但未登记的 >400 文件：
/// section_practice 429、teacher_task_form_view 425；
/// 2026-10-08 拆分 courseware_present_page 474→320、courseware_section_edit_dialog 470→373，
/// 两条均移出 _baseline；
/// 2026-10-08 票据 18（多对象派发）落代码：teacher_task_form_view 425→429（新增班级/学生
/// 多选状态、getter 与 pick 方法，已把 chip 行抽到 dispatch_targets_row.dart 仍净增 4 行）、
/// 补登此前漏登的 teacher_task_review_screen 390→424（新增 classIds/studentIds 携带与
/// _onAssignBulk 批量派发分支）；两处增长均为功能必需，已在提交正文说明理由）。
/// 2026-10-08 票据 20（概览→教师工作台）：teacher_tasks_view 649→656（新增 initialTab
/// 深链参数，承接概览待办卡片跳对应 Tab），功能必需、已在提交正文说明理由）。
/// 2026-10-08 票据 17（文件规模棘轮补登债务）：分文件定 A/B——
///   · section_practice 429 → **A 拆小**：抽出 PracticeQuestionPrompt/PracticeAction/PracticeNotice 三子件到
///     section_practice_parts.dart，主文件 293 行已回到 400 内，**整条移出 _baseline**；
///   · teacher_task_form_view 429 → **A 拆小**：抽出审阅闸门/动作区到 teacher_task_form_actions.dart，
///     主文件 384 行已回到 400 内，**整条移出 _baseline**。
///   两处 A 拆小均为 ADR-0058 P4「区块/子件独立成文件」，净减为真实职责分离，不是硬压行数。
/// 2026-10-08 票据 06/07（ADR-0075 概览×统计合并）：删除 analytics_screen 488/492（能力已并入
///   WorkbenchAnalysis，等价测试见 workbench_analysis_test），并从 _baseline 移除其登记；
///   拆分出的三个子文件正式登记基线：workbench_analysis 417、workbench_glance 451、
///   analytics_charts 511（图表适配器层：同组图表 widget 视为一类职责，符合 ADR-0058 §2 例外）。
///   主壳 teacher_overview_view 拆分后 242 行已回到 400 内，无需登记。
/// 2026-10-08 工作台优化（宽屏 grid + 去重）：workbench_analysis 417→374 回到 400 内、
///   **整条移出 _baseline**（去重删除冗余正确率卡 + 图表改用栅格包裹，净减为真实收敛）；
///   workbench_glance 451→450（栅格包裹微调）；analytics_charts 511→587（图表适配器增加
///   maxCategories 截断 + 密集标签旋转，修复知识点维度下 x 轴标签互相遮挡——真实缺陷修复，
///   属 B 类合理大件，基线随真实行数上调）；新增 responsive_grid.dart 69 行（≤400 不登记）。
/// 2026-10-09 工作台三处样式缺陷修复（ADR-0075 工作台优化）：analytics_charts 587→691，
///   其中 592→691 含本次（1）环形外圆半径修正（环厚 = outer - centerSpace - 描边，杜绝被
///   Stack 裁切）；（2）横向条标签列加宽 flex:6 + 2 行换行 + 长按整行弹出完整名（非 Material
///   Overlay 提示 _LabelTip）。均属 B 类图表适配器职责扩充，基线随真实行数上调。
///   workbench_glance 本次微调后回到 406（移除可选图例行 + 压缩注释，保持非 B 基线只许下调）。
/// 2026-10-10 教师工作台 / 学生管理 / 课件编辑器一轮多任务的棘轮记账：
///   · 本轮真实增长的已登记文件（B 类，基线随真实行数上调，理由写进提交正文）——
///     app_theme 1695→1702（输入框文字垂直居中：strut 令牌）、adaptive_shell 490→503
///     （侧栏折叠动画的溢出 guard）、student_management_screen 777→810（学生导入模板下载入口）；
///   · 补登漏调：teacher_tasks_view 656→672（上一轮票据 20 之后又增长了 16 行但没同步基线，
///     基线停在旧高度会让棘轮失真，这里补到实测值）；
///   · 补登两个已越过 400 但未登记的课件文件：courseware_editor_page 432、courseware_section_edit_dialog 588
///     （均为此前多轮「空态添加环节 / 知识点场景关联」累积的债务，非本轮一次性引入）。
///     2026-10-10 **两条已拆完并移出登记**：courseware_editor_page 432→363（抽出
///     `CoursewareEditorInfoCard`）、courseware_section_edit_dialog 588→379（抽出
///     `SectionMaterialPicker` 224 行含素材库 picker + 缩略图、`SectionScriptSegmentsEditor`
///     75 行含多段话术行与重点切换）。均为 A 类净减（真实职责分离），不是硬压行数。
/// 2026-10-10 **student_home 428→395，整条移出 _baseline**：AI 入口统一为右下角浮球后，
///   学生端不再有「问 AI 老师」页签，随之删除已无落点的首页 AI 横幅（`_TutorBanner`）与
///   `onNavigateToTutor` 回调——回到 400 行内，属 A 类净减（真实职责分离）。
/// **只许下调（除 B 类已登记的合理大件外）。**
///
/// 2026-10（ADR-0083 图库 DB 化 / SceneSpec 几何化）下调：
///   · reflection_scene 567 → 438：抽出公共 painter 到 reflection_scene_painter.dart、
///     数据模型与适配层到 reflection_scene_data.dart（T04/T03 落地）。属 A 类净减。
///   · section_scene_figures_picker 曾因「清单改为按需拉图库」涨到 414 → 抽出图形卡
///     子件 scene_figure_tile.dart 后回到 322，**未登记**（回到 400 内）。
///
/// 拆分批次见 `docs/refactor/2026-09-21-flutter-ui-decomposition.md`（P0–P4）。
const Map<String, int> _baseline = <String, int>{
  'shared/theme/app_theme.dart': 1702,
  'shared/widgets/adaptive_shell.dart': 503,
  'features/home/presentation/widgets/teacher/teacher_question_bank_view.dart': 759,
  'features/home/presentation/widgets/teacher/teacher_tasks_view.dart': 672,
  'features/home/presentation/screens/home_screen.dart': 586,
  'features/assistant/presentation/screens/assistant_chat_page.dart': 570,
  'shared/widgets/scene_interpreter/reflection_scene.dart': 438,
  'features/home/presentation/widgets/teacher/teacher_question_card.dart': 511,
  'features/home/presentation/widgets/teacher/teacher_wrong_questions_view.dart': 442,
  'features/home/presentation/widgets/teacher/workbench_glance.dart': 406,
  'shared/widgets/analytics_charts.dart': 691,
  'features/home/presentation/screens/teacher_task_review_screen.dart': 424,
  'features/students/presentation/screens/student_management_screen.dart': 810,
};

bool _isDart(String path) =>
    path.endsWith('.dart') &&
    !path.endsWith('.g.dart') &&
    !path.endsWith('.freezed.dart');

/// `lib/dev/**` 是视觉走查台，1189 行是它的工作形态，不按业务文件约束。
bool _isExempt(String rel) =>
    rel.startsWith('dev/') || rel.startsWith('generated/');

/// 取相对 `lib/` 的路径，统一分隔符。
String _rel(String path) {
  final norm = path.replaceAll(r'\', '/');
  const prefix = 'lib/';
  return norm.startsWith(prefix) ? norm.substring(prefix.length) : norm;
}
