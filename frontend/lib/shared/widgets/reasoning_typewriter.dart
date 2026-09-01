import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 出题推理打字机（ADR-0017）：把 [text] 逐字揭示，营造「AI 正在思考出题」的连续感。
///
/// - 文本一次性到达（打底路径）：从 0 动画揭示到全文。
/// - 文本流式增量到达（reasoning 模型）：每次 [text] 变长时续接揭示新增部分。
/// - [streaming] 为 true 且未揭示完时，尾部显示闪烁光标 `▌`。
class ReasoningTypewriterWidget extends StatefulWidget {
  final String text;
  final bool streaming;

  const ReasoningTypewriterWidget(this.text, {this.streaming = false, super.key});

  @override
  State<ReasoningTypewriterWidget> createState() =>
      _ReasoningTypewriterWidgetState();
}

class _ReasoningTypewriterWidgetState extends State<ReasoningTypewriterWidget> {
  int _shown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ReasoningTypewriterWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 文本变长（流式增量或首次到达）→ 继续揭示新增部分。
    if (widget.text.length > _shown) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 18), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_shown >= widget.text.length) {
        t.cancel();
        return;
      }
      setState(() {
        _shown = (_shown + 2).clamp(0, widget.text.length);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final revealed = widget.text.substring(0, _shown);
    final done = _shown >= widget.text.length;
    return Text(
      revealed + (widget.streaming && !done ? '▌' : ''),
      style: text.bodySmall?.copyWith(
        color: app.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
