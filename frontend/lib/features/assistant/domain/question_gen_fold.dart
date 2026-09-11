import '../../../../shared/domain/models/models.dart';
import 'assistant_event.dart';

/// 把 AG-UI 事件流折成「出题预览态」的纯模块。
///
/// 原先这段解释逻辑是 `home_notifier.TaskGenNotifier.generate` 里一个 8 分支
/// switch，和 Riverpod 状态赋值、SSE 迭代、落库请求写在一起——逐帧行为（推理
/// 文本怎么累加、题卡到达后内联区何时折叠、0 题时回显什么）全部无法断言。
/// 这里把它抽成不可变值 + 一个 [apply]：输入事件序列，输出可断言的预览态。
///
/// 只负责「解释」，不负责发请求与落库——那些仍在 notifier。
class QuestionGenFold {
  /// 已到达的题卡（DATA.type == 'question'）。
  final List<QuestionPreview> questions;

  /// 内联推理区状态：正在生成的题序号（-1 = 无）。
  final int liveIndex;

  /// 内联推理区的进度标签。
  final String liveLabel;

  /// 内联推理区已累积的推理文本。
  final String liveReasoning;

  /// 后端最后一条 ASSISTANT_MESSAGE（count=0 时下发「本次未能生成题目…」）。
  final String lastMessage;

  /// ERROR 帧文案；非 null 表示流以错误收尾。
  final String? errorText;

  const QuestionGenFold({
    this.questions = const <QuestionPreview>[],
    this.liveIndex = -1,
    this.liveLabel = '',
    this.liveReasoning = '',
    this.lastMessage = '',
    this.errorText,
  });

  static const _generating = '生成中';
  static const _genFailed = '生成失败';
  static const _emptyHint = '本次未能生成题目，请调整科目或年级后重试。';

  bool get hasError => errorText != null;

  /// 流结束但 0 题时的回显文案：优先后端说明，否则兜底。
  String get emptyMessage => lastMessage.isNotEmpty ? lastMessage : _emptyHint;

  /// 消费一帧事件，返回新的 [QuestionGenFold]（纯函数，不改接收者）。
  QuestionGenFold apply(AssistantEvent ev) => switch (ev.eventType) {
        AssistantEventType.toolCall => _copy(liveLabel: ev.label ?? _generating),
        AssistantEventType.step => _copy(
            // 新题开始：展开内联区（序号 = 下一题），清空上一题残留的推理文本。
            liveIndex: questions.length,
            liveLabel: ev.label ?? _generating,
            liveReasoning: '',
          ),
        AssistantEventType.thinking => _isRouting(ev)
            ? this
            : _copy(liveReasoning: liveReasoning + (ev.text ?? '')),
        AssistantEventType.assistantMessage =>
          (ev.text?.isNotEmpty ?? false) ? _copy(lastMessage: ev.text!) : this,
        AssistantEventType.data => _withQuestion(ev),
        AssistantEventType.toolResult => _copy(liveIndex: -1, liveLabel: ''),
        AssistantEventType.error =>
          _copy(errorText: ev.message ?? _genFailed),
        _ => this,
      };

  /// 路由帧（extra.business / extra.routing）跳过：那是「正在选择助手…」这类
  /// 编排状态，不是出题思路，拼进推理区会污染展示。
  static bool _isRouting(AssistantEvent ev) {
    final extra = ev.extra;
    if (extra == null) return false;
    return extra['business'] != null || extra['routing'] == true;
  }

  QuestionGenFold _withQuestion(AssistantEvent ev) {
    if (ev.data?['type'] != 'question') return this;
    final result = ev.data?['result'];
    if (result is! Map<String, dynamic>) return this;
    return _copy(
      questions: <QuestionPreview>[
        ...questions,
        QuestionPreview.fromJson(result),
      ],
      // 题卡到达：折叠内联区（推理已随卡落到卡片 info icon）。
      liveIndex: -1,
      liveLabel: '',
      liveReasoning: '',
    );
  }

  QuestionGenFold _copy({
    List<QuestionPreview>? questions,
    int? liveIndex,
    String? liveLabel,
    String? liveReasoning,
    String? lastMessage,
    Object? errorText = _unset,
  }) =>
      QuestionGenFold(
        questions: questions ?? this.questions,
        liveIndex: liveIndex ?? this.liveIndex,
        liveLabel: liveLabel ?? this.liveLabel,
        liveReasoning: liveReasoning ?? this.liveReasoning,
        lastMessage: lastMessage ?? this.lastMessage,
        errorText: identical(errorText, _unset)
            ? this.errorText
            : errorText as String?,
      );

  static const _unset = Object();
}
