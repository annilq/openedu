import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/domain/models/assistant_courseware_context.dart';
import 'package:kids_learn/features/assistant/presentation/provider/assistant_notifier.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/assistant_message_list.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../domain/models/courseware.dart';
import '../../domain/models/courseware_section.dart';
import 'section_practice_parts.dart';

/// `practice` 课堂练习环节（ADR-0067 §3.6）。
///
/// 学生口头回答，教师只在本地点击「对 / 错」；本组件不调用任务、作答、错题或
/// 掌握度能力。出题与答错提示都复用 [assistantNotifierProvider] 和
/// [AssistantMessageList]，经唯一的 `POST /assistant/chat` 通道完成。
class SectionPractice extends ConsumerStatefulWidget {
  const SectionPractice({
    super.key,
    required this.courseware,
    required this.section,
  });

  final CoursewareModel courseware;
  final CoursewareSectionModel section;

  @override
  ConsumerState<SectionPractice> createState() => _SectionPracticeState();
}

class _SectionPracticeState extends ConsumerState<SectionPractice> {
  bool _started = false;
  bool _hasQuestion = false;
  bool _correct = false;
  // T05：提示级别（方向 / 条件 / 下一步，默认方向）。初始值读自环节 payload，可选持久化。
  String _hintLevel = 'direction';
  bool _hintRequested = false;
  String? _fallback;

  @override
  void initState() {
    super.initState();
    final stored = widget.section.payload['hint_level'];
    if (stored is String && _hintLabels.containsKey(stored)) {
      _hintLevel = stored;
    }
  }

  AssistantCoursewareContext get _context => AssistantCoursewareContext(
    coursewareId: widget.courseware.id,
    sectionId: widget.section.id,
    knowledgePoint: widget.courseware.kpName,
    subject: widget.courseware.subject,
    grade: widget.courseware.grade,
    semester: widget.courseware.semester,
  );

  // T05：透传 extra（含提示级别），后端 tutor 据此驱动分级提示。
  AssistantCoursewareContext get _contextWithExtra =>
      _context.copyWith(extra: {'hint_level': _hintLevel});

  static const Map<String, String> _hintLabels = {
    'direction': '方向',
    'condition': '条件',
    'next_step': '下一步',
  };

  String _hintLabel(String level) => _hintLabels[level] ?? '方向';

  /// 各级别给提示的约束（方向级不给关键条件；下一步级不给最终答案）。
  String _hintInstruction(String level) {
    switch (level) {
      case 'condition':
        return '提示关键条件（如对称轴定义、需要判断的特征），但不要把完整解题步骤和最终答案说出口。';
      case 'next_step':
        return '指出下一步该做什么操作，但不替学生推导到最终答案。';
      case 'direction':
      default:
        return '只提示观察方向（如看哪里、沿什么对折），不要给关键条件，更不要直接说答案。';
    }
  }

  Future<void> _requestQuestion() async {
    final qtype = widget.section.practice?.qtype ?? '题目';
    setState(() {
      _started = true;
      _hasQuestion = false;
      _correct = false;
      _hintRequested = false;
      _fallback = null;
    });
    final notifier = ref.read(assistantNotifierProvider.notifier);
    notifier.reset();
    await notifier.send('请为当前课堂练习出一道 $qtype 题，只展示题目。', courseware: _context);
    if (!mounted) return;
    final next = ref.read(assistantNotifierProvider);
    final text = _answerText(next);
    setState(() {
      _fallback = _failureOf(next, text);
      _hasQuestion =
          _fallback == null &&
          text.isNotEmpty &&
          !text.contains('未配置模型') &&
          !text.contains('暂无可用的 AI 引擎');
    });
  }

  Future<void> _requestHint() async {
    final level = _hintLevel;
    setState(() {
      _hintRequested = true;
      _fallback = null;
    });
    await ref
        .read(assistantNotifierProvider.notifier)
        .send(
          '学生刚才口头回答错了。请给【${_hintLabel(level)}】级提示：${_hintInstruction(level)}',
          courseware: _contextWithExtra,
        );
    if (!mounted) return;
    final next = ref.read(assistantNotifierProvider);
    final text = _answerText(next);
    setState(() => _fallback = _failureOf(next, text));
  }

  void _markCorrect() => setState(() {
    _correct = true;
    _fallback = null;
  });

  String _answerText(AssistantState state) {
    if (state is! AssistantActive) return '';
    return state.messages
        .where((message) => message.role == 'ai' && !message.thinking)
        .map((message) => message.text)
        .where((text) => text.trim().isNotEmpty)
        .join('\n');
  }

  String? _failureOf(AssistantState state, String text) {
    if (state is AssistantActive && state.error) {
      return '课堂练习请求失败，请检查网络或模型配置后重试。';
    }
    if (text.isEmpty) {
      return '课堂练习请求失败，助手没有返回内容，请重试。';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantNotifierProvider);
    final streaming = state is AssistantActive && state.streaming;
    final messages =
        state is AssistantActive
            ? state.messages
                .where((message) => message.role == 'ai')
                .toList(growable: false)
            : const <AssistantMessage>[];
    return LayoutBuilder(
      builder:
          (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PracticeQuestionPrompt(segments: widget.section.displaySegments),
              const SizedBox(height: AppSpacing.lg),
              if (!_started)
                Align(
                  alignment: Alignment.centerLeft,
                  child: PracticeAction(
                    key: const ValueKey('courseware-practice-generate'),
                    label: '出题',
                    icon: LucideIcons.sparkles,
                    onPressed: streaming ? null : _requestQuestion,
                  ),
                ),
              if (_started) ...[
                _messageArea(constraints, messages),
                if (_fallback != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  PracticeNotice(message: _fallback!, error: true),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (_hasQuestion && !_correct) ...[
                  Text(
                    '提示级别',
                    style: AppTheme.textOf(context)
                        .labelSmall
                        ?.copyWith(color: AppTheme.colorsOf(context).onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _hintLevelSelector(context, streaming),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_hintRequested) ...[
                  PracticeNotice(
                    message:
                        '已给【${_hintLabel(_hintLevel)}】级提示（本练习不建任务、不记录作答）',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                _actions(streaming),
              ],
            ],
          ),
    );
  }

  Widget _messageArea(
    BoxConstraints constraints,
    List<AssistantMessage> messages,
  ) {
    final list = AssistantMessageList(
      messages: messages,
      maxBubbleWidthFactor: 1,
    );
    if (constraints.hasBoundedHeight) return Expanded(child: list);
    return SizedBox(height: AppLayout.contentNarrow, child: list);
  }

  Widget _hintLevelSelector(BuildContext context, bool streaming) {
    final app = AppTheme.colorsOf(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: _hintLabels.keys.map((level) {
        final selected = _hintLevel == level;
        return PracticeAction(
          label: _hintLabel(level),
          icon: selected ? LucideIcons.check : LucideIcons.chevronRight,
          fill: selected ? app.cta : app.surfaceRaised,
          foreground: selected ? app.onCta : app.onSurfaceVariant,
          onPressed: streaming
              ? null
              : () => setState(() => _hintLevel = level),
        );
      }).toList(),
    );
  }

  Widget _actions(bool streaming) {    if (_correct) {
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const PracticeNotice(message: '回答正确，可以继续下一题。'),
          PracticeAction(
            label: '再出一题',
            icon: LucideIcons.refreshCw,
            onPressed: streaming ? null : _requestQuestion,
          ),
        ],
      );
    }
    if (!_hasQuestion) {
      return Align(
        alignment: Alignment.centerLeft,
        child: PracticeAction(
          label: '重新出题',
          icon: LucideIcons.refreshCw,
          onPressed: streaming ? null : _requestQuestion,
        ),
      );
    }
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        PracticeAction(
          key: const ValueKey('courseware-practice-correct'),
          label: '对',
          icon: LucideIcons.check,
          fill: AppTheme.colorsOf(context).semanticPositive,
          foreground: AppTheme.colorsOf(context).semanticPositiveFg,
          onPressed: streaming ? null : _markCorrect,
        ),
        PracticeAction(
          key: const ValueKey('courseware-practice-wrong'),
          label: '错',
          icon: LucideIcons.x,
          fill: AppTheme.colorsOf(context).semanticError,
          foreground: AppTheme.colorsOf(context).semanticErrorFg,
          onPressed: streaming ? null : _requestHint,
        ),
      ],
    );
  }
}

