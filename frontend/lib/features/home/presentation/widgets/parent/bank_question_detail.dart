import 'package:flutter/material.dart' show Dialog, Icons, showDialog;
import 'package:flutter/widgets.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/utils/question_labels.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';

/// 题库题的详情弹窗（ADR-0061 §S）。
///
/// 为什么要详情：题库列表是**扫描式**的（一眼看有没有要用的题），但「这题讲什么」
/// 需要**停留式**阅读。三块内容：
/// 1. **题目本体**：题干 / 选项 / 答案 / 解析 —— 与做题时的呈现一致；
/// 2. **知识点信息**：学科 / 年级 / 学期 / 知识点 / 难度 / 被引用次数 —— 列表里
///    只显示知识点名，详情补全「这题属于哪个学期」（它同时决定讲解匹配哪份模板）；
/// 3. **交互式讲解**：读落库快照 `sceneSpec`（知识点模板后续改动不影响已生成的题）。
///
/// 无场景时**不显示**图形区，而不是显示空态占位——「没配模板」是常态，不是异常。
///
/// 独立成文件的原因：内联进题库视图会顶破 ADR-0058 的行数棘轮。
class BankQuestionDetail extends StatelessWidget {
  final BankQuestionItem item;

  const BankQuestionDetail({super.key, required this.item});

  /// 弹窗最大宽度。比调参弹窗（560）宽——题目 + 选项 + 图形并排更舒展。
  static const double maxWidth = 640;

  /// 打开详情。返回 Future 以便调用方await（关闭后无需处理结果）。
  static Future<void> show(BuildContext context, BankQuestionItem item) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: BankQuestionDetail(item: item),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    final spec = item.sceneSpec;
    final hasScene = spec != null && spec['kind'] is String;
    final hasOptions = item.options != null && item.options!.isNotEmpty;

    // 内容可能比屏高（题干长 + 有图形）→ 套滚动兜底，任何屏高都不溢出。
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 标题行：题型 + 难度 + 关闭 ──
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppTags.normal(qtypeLabel(item.qtype)),
                      if ((item.difficulty ?? '').isNotEmpty)
                        AppTags.normal(difficultyLabel(item.difficulty!)),
                      if (item.archivedAt != null)
                        AppTags.normal('已归档'),
                    ],
                  ),
                ),
                AppIconAction(
                  icon: Icons.close,
                  semanticLabel: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // ── 题目本体 ──
            Text(item.stem, style: text.bodyMedium),
            if (hasOptions) ...[
              const SizedBox(height: AppSpacing.sm),
              // 选项标号取自**位置**（与做题/纸质导出一致），不受选项文本里是否
              // 自带「A.」影响。
              for (var i = 0; i < item.options!.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${chr(i)}. ${item.options![i]}',
                    style: text.bodyMedium,
                  ),
                ),
            ],
            if ((item.answer ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '标准答案：${item.answer}',
                style: text.bodyMedium?.copyWith(
                  color: app.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if ((item.explanation ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('解析：${item.explanation}', style: text.bodyMedium),
            ],

            // ── 知识点信息 ──
            const SizedBox(height: AppSpacing.md),
            _KnowledgeFacts(item: item),

            // ── 交互式讲解（ADR-0061 §S）──
            if (hasScene) ...[
              const SizedBox(height: AppSpacing.md),
              AppTags.info('交互讲解'),
              const SizedBox(height: AppSpacing.sm),
              // 画布是「边长 = 宽度」的正方形（ADR-0061 §O），弹窗里必须压窄，
              // 否则一屏放不下题干+ 图形。
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _sceneMaxWidth),
                  child: SceneInterpreter(
                    kind: spec['kind'] as String,
                    spec: spec,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 场景画布最大宽度。压窄理由同`SceneOptionGroup._maxItemWidth`（ADR-0061 §O）：
  /// 画布边长 = 宽度，不压会把弹窗顶出屏幕。
  static const double _sceneMaxWidth = 300;

  /// 仅供测试断言「画布确实被压窄」用（私有常量测试拿不到）。
  @visibleForTesting
  static const double sceneMaxWidthForTest = _sceneMaxWidth;
}

/// 知识点信息块：列表里只有知识点名，这里补全「属于哪学期/难度/被引用几次」。
class _KnowledgeFacts extends StatelessWidget {
  final BankQuestionItem item;

  const _KnowledgeFacts({required this.item});

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    // '' = 整学年/不限（ADR-0061 §J）。别显示成空白标签。
    final semester = item.semester.isEmpty ? '整学年' : item.semester;
    final facts = <(String, String)>[
      ('学科', item.subject),
      ('年级', '${item.grade}年级'),
      ('学期', semester),
      ('知识点', item.knowledgePoint),
      if (item.usageCount > 0) ('被引用', '${item.usageCount} 次'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: app.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppSpacing.xs),
        border: Border.all(color: app.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('知识点信息', style: text.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          // 用固定宽度的标签列对齐，比一串Wrap 更整齐。
          for (final (k, v) in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      k,
                      style: text.bodySmall?.copyWith(
                        color: app.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(child: Text(v, style: text.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 序号字母（0→A, 1→B …）。不用 `String.fromCharCode` 是为了可读性。
String chr(int i) => String.fromCharCode(65 + i);
