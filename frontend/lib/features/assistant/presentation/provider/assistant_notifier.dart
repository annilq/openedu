import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kids_learn/shared/domain/models/assistant_courseware_context.dart';
import '../../domain/assistant_requests.dart';
import '../../providers/assistant_provider.dart';
import '../../domain/ai_text_fold.dart';
import '../../domain/assistant_card.dart';
import '../../domain/assistant_clarify.dart';
import '../../domain/assistant_summary.dart';
import '../../domain/assistant_event.dart';
import '../../domain/assistant_source.dart';
import '../../domain/assistant_suggested_action.dart';
import '../../domain/conversation.dart';

/// 一条助手对话气泡。
class AssistantMessage {
  final String role; // 'user' | 'ai'
  final String text;
  final bool blocked;
  final List<AssistantCard>? cards; // DATA 类型化卡片（题卡 / 任务卡 / 学情卡）
  final bool thinking; // 占位「思考中」气泡（尚无文本）
  final String stage; // thinking 时的阶段文案（路由/工具帧提取），空 = 默认「思考中…」
  final List<RagSource> sources; // 答疑引用落点（答案下方「参考来源」条）
  final List<SuggestedAction>? followups; // 回复后 follow-up chips（SUGGESTED_ACTIONS 帧，票 03(a)）

  /// 缺槽引导（ADR-0095 / ADR-0100）：非空时补一个「一句补齐」快捷入口。
  ///
  /// ADR-0100：正文已由后端念成一句引导，这里**不再**逐槽铺选项 chip——补三项点三次
  /// 往返比纯文本更慢。本卡只把示例句做成可点的一行。
  final List<ClarifySlot>? clarify;

  final List<SummarySlot>? summary; // 规格汇总（extra.summary，ADR-0095）：非空时渲染带修改入口的汇总卡

  const AssistantMessage({
    required this.role,
    this.text = '',
    this.blocked = false,
    this.cards,
    this.thinking = false,
    this.stage = '',
    this.sources = const <RagSource>[],
    this.followups,
    this.clarify,
    this.summary,
  });

  /// 从回放气泡重建一条消息（role 换算成 UI 侧口径：`assistant` → `ai`）。
  ///
  /// 回放气泡**没有 `blocked`**：`Message` 上那组安全标记列从未被写入（真正的被拦记录
  /// 在 TutorLog，即 F-305 的「已拦截」徽标），所以历史消息上不会出现安全提示——
  /// 这是有意的不对称，别用「顺带补个字段」把它掩盖成看起来能用的空值。
  ///
  /// ``clarify`` / ``summary`` 照搬：气泡载荷里存的就是与实时流 `extra` 同形的结构化
  /// 帧（ADR-0095），解析后挂到消息上，历史里的追问卡与汇总卡按原样还原。
  factory AssistantMessage.fromBubble(AssistantBubble bubble) =>
      AssistantMessage(
        role: bubble.role == 'assistant' ? 'ai' : 'user',
        text: bubble.text,
        cards: bubble.cards.isEmpty ? null : bubble.cards,
        clarify: _orNull(ClarifySlot.slotsOf(bubble.clarify)),
        summary: _orNull(SummarySlot.slotsOf(bubble.summary)),
        // 回放溯源为后续增强：当前气泡载荷未携带 sources，留空不展示。
        sources: const <RagSource>[],
      );
}

/// 空列表折成 null：与实时流同一口径（`clarify` / `summary` 非空才渲染卡）。
List<T>? _orNull<T>(List<T> slots) => slots.isEmpty ? null : slots;

sealed class AssistantState {
  const AssistantState();
}

class AssistantInitial extends AssistantState {
  const AssistantInitial();
}

class AssistantActive extends AssistantState {
  final List<AssistantMessage> messages;
  final bool streaming;
  final bool error;

  const AssistantActive(this.messages, this.streaming, {this.error = false});
}

class AssistantNotifier extends StateNotifier<AssistantState> {
  final AssistantRepository _repo;

  AssistantNotifier(this._repo) : super(const AssistantInitial());

  bool _submitting = false;

  /// 当前会话 id：首轮由后端 DONE 帧回写，之后每轮原样带回以续接上下文。
  ///
  /// 后端对该 id 做「teacher_id + student_id」归属校验（`features/assistant/service.py`）：
  /// 不匹配时不报错，而是**另建会话并回写新 id**，这里随之覆盖（自愈，不会读到他人会话）。
  /// 只存内存——**有意如此**（产品决策 2026-09-16）：打开助手默认空态，不自动续接
  /// 历史会话；首轮发消息才新建会话。要接着上次聊就点「历史会话」里的对应行
  /// （resume 会接管该行的 session id，后续消息落回原会话）。
  String? _currentSessionId;

  /// 兜底历史上限，对齐后端 `load_chat_history(limit=20)`。
  ///
  /// 后端只有在「无 session_id」或「归属校验失败」时才消费请求里的 history
  /// （有有效 session_id 时改从 DB 载入并覆盖）。该兜底路径**没有服务端截断**，
  /// 所以必须在发送侧限长，否则长对话会把整段历史灌进 prompt。
  static const _historyLimit = 20;

  /// 把气泡列表压成后端契约的 history（`{"role", "content"}`），只保留最近 [_historyLimit] 条。
  List<Map<String, dynamic>> _tailHistory(List<AssistantMessage> messages) {
    final pairs =
        messages
            .where((m) => !m.thinking)
            .map(
              (m) => {
                // UI 侧 role 是 'ai'，后端契约是 'assistant'（agent_core/ports.py）；
                // 键名是 content 而非 text——否则适配器取不到文本，整条被丢弃。
                'role': m.role == 'ai' ? 'assistant' : 'user',
                'content': m.text,
              },
            )
            .toList();
    if (pairs.length <= _historyLimit) return pairs;
    return pairs.sublist(pairs.length - _historyLimit);
  }

  /// 发送一条消息并消费 SSE 事件流。角色由后端 JWT 解析（教师 / 学生自动分流）。
  Future<void> send(
    String raw, {
    String? model,
    AssistantCoursewareContext? courseware,
  }) async {
    final message = raw.trim();
    if (message.isEmpty || _submitting) return;
    _submitting = true;

    final history = switch (state) {
      AssistantActive(:final messages) => _tailHistory(messages),
      _ => <Map<String, dynamic>>[],
    };

    final current = switch (state) {
      AssistantActive(:final messages) => List<AssistantMessage>.from(
        messages.where((m) => !m.thinking),
      ),
      _ => <AssistantMessage>[],
    };
    current.add(AssistantMessage(role: 'user', text: message));
    state = AssistantActive(current, true);

    // 事件解释委托 [AiTextFold]（纯模块）：本 notifier 只负责喂事件与落状态。
    var fold = const AiTextFold();
    try {
      await for (final ev in _repo.chat(
        AssistantChatReq(
          message: message,
          sessionId: _currentSessionId,
          history: history,
          model: model,
          courseware: courseware,
          // 与 courseware 同源：课件入口带知识点 id 时一并透传，后端据此解析知识点
          // 场景（L0 门控），否则为 null 走普通对话。补上此前漏传的字段。
          knowledgePointId: courseware?.knowledgePointId,
        ),
      )) {
        // 会话身份随 DONE 帧回写：首轮建立；归属校验失败时后端换新 id，此处自愈覆盖。
        if (ev.eventType == AssistantEventType.done && ev.sessionId != null) {
          _currentSessionId = ev.sessionId;
        }
        fold = fold.apply(ev);
        state = AssistantActive(_render(current, fold, streaming: true), true);
      }
      state = AssistantActive(_render(current, fold, streaming: false), false);
    } catch (e) {
      state = AssistantActive(
        <AssistantMessage>[
          ..._render(current, fold, streaming: false),
          AssistantMessage(role: 'ai', text: '⚠️ ${e.toString()}'),
        ],
        false,
        error: true,
      );
    } finally {
      _submitting = false;
    }
  }

  /// 恢复一段历史会话：换掉当前会话身份与气泡，之后的 [send] 会续接到它
  /// （后端按 session_id 归属校验后续接，零后端改动）。
  ///
  /// 历史列表里每一条都是**调用者本人**的会话（ADR-0096），所以续接必然过归属校验——
  /// 不再需要在调用侧按归属挑路径。
  void resume({
    required String sessionId,
    required List<AssistantMessage> messages,
  }) {
    _currentSessionId = sessionId;
    state = AssistantActive(messages, false);
  }

  /// 开启新会话：丢弃当前 session_id 与气泡，下一轮重新在后端建立会话。
  ///
  /// 没有这一步 session_id 会一直续接，历史只增不减（后端仅截最近 20 条喂 prompt，
  /// 但会话本身不会结束）。入口是助手页历史模式顶栏的「新对话」（ADR-0048）——
  /// 它必须存在：有了「恢复续接」却没有「开新的一段」，用户就只能靠列表里多出
  /// 一堆碎会话。
  void reset() {
    _currentSessionId = null;
    state = const AssistantInitial();
  }

  /// 把 [fold] 的解释结果渲染到气泡列表尾部：思考中占位 → 正文 → 错误气泡。
  ///
  /// 占位气泡只在 [streaming] 时存在；流结束（或异常）后必须消失，否则会留下
  /// 一个永久转圈的空气泡。
  List<AssistantMessage> _render(
    List<AssistantMessage> history,
    AiTextFold fold, {
    required bool streaming,
  }) {
    final out = List<AssistantMessage>.from(history);
    if (fold.isEmpty) {
      if (streaming) {
        // 占位气泡带上阶段文案：路由/工具帧到达时把「思考中…」换成
        // 「已选择助手：X / 正在查询××」，用户能看到推进而不是干等。
        out.add(
          AssistantMessage(role: 'ai', thinking: true, stage: fold.stage),
        );
      }
      return out;
    }
    if (fold.text.isNotEmpty || fold.cards.isNotEmpty) {
      out.add(
        AssistantMessage(
          role: 'ai',
          text: fold.text,
          cards: fold.cards.isEmpty ? null : fold.cards,
          blocked: fold.blocked,
          sources: fold.sources,
          clarify: fold.clarifySlots.isEmpty ? null : fold.clarifySlots,
          summary: fold.summarySlots.isEmpty ? null : fold.summarySlots,
        ),
      );
    }
    if (fold.hasError) {
      out.add(
        AssistantMessage(
          role: 'ai',
          text: fold.errorText!,
          blocked: fold.blocked,
        ),
      );
    }
    // 回复后 follow-up chips（票 03(a)）：挂到本轮最后一条 ai 消息下方渲染。
    if (fold.suggestedActions.isNotEmpty) {
      for (var i = out.length - 1; i >= 0; i--) {
        if (out[i].role == 'ai') {
          final m = out[i];
          out[i] = AssistantMessage(
            role: m.role,
            text: m.text,
            blocked: m.blocked,
            cards: m.cards,
            thinking: m.thinking,
            stage: m.stage,
            sources: m.sources,
            followups: fold.suggestedActions,
            // 重建时不能丢 clarify / summary：follow-up 挂在同一条 ai 消息上，
            // 丢掉会让引导卡、汇总卡在 chips 到达的那一刻消失。
            clarify: m.clarify,
            summary: m.summary,
          );
          break;
        }
      }
    }
    return out;
  }
}

final assistantNotifierProvider =
    StateNotifierProvider<AssistantNotifier, AssistantState>((ref) {
      final repo = ref.watch(assistantRepositoryProvider);
      return AssistantNotifier(repo);
    });
