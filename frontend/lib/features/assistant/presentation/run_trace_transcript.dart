import '../domain/run_trace.dart';
import '../../../../shared/util/datetime_format.dart';

/// 把运行轨迹列表压成一份可读的 Markdown 文本，供「导出运行轨迹」落盘
/// （file_picker.saveFile）。与助手对话导出（conversation_transcript.dart）同口径：
/// 复用系统保存面板、不引新依赖。
///
/// 列表页只持有运行概要（[RunTraceRun]），不含逐步内容——这里导出的是「运行清单」
/// （类型 / 状态 / 模型 / 时间 / ID）；逐步明细走详情页，不在本导出范围内。
String buildRunTraceMarkdown(List<RunTraceRun> runs) {
  final buffer = StringBuffer();
  buffer.writeln('# AI 运行轨迹');
  buffer.writeln();
  buffer.writeln('导出时间：${_exportStamp()}');
  buffer.writeln();
  buffer.writeln('共 ${runs.length} 次运行');
  buffer.writeln();

  for (final run in runs) {
    final title = run.title.isEmpty ? '未命名运行' : run.title;
    buffer.writeln('## $title');
    buffer.writeln();
    buffer.writeln('- 类型：${runKindLabel(run.kind)}');
    buffer.writeln('- 状态：${_statusLabel(run.status)}');
    buffer.writeln('- 模型：${run.model ?? '未知'}');
    buffer.writeln('- 创建时间：'
        '${run.createdAt == null ? '未知' : formatLocalDayMinute(run.createdAt!)}');
    buffer.writeln('- 运行 ID：${run.id}');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
  }

  return buffer.toString();
}

/// 状态 → 教师口径标签。后端状态是受控枚举，认不出的原样显示。
String _statusLabel(String status) => switch (status) {
      'running' => '进行中',
      'done' => '已完成',
      'error' => '失败',
      'blocked' => '已拦截',
      final other => other.isEmpty ? '未知' : other,
    };

String _exportStamp() {
  final d = DateTime.now().toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}

/// 导出文件名用的日期戳（YYYY-MM-DD_HHmm），避免中文/空格导致保存面板默认名异常。
String runTraceFileNameStamp() {
  final d = DateTime.now().toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)}_${p(d.hour)}${p(d.minute)}';
}

/// 把一次运行的**全步骤详情**（[RunTraceDetail]）压成可读 Markdown，供详情页
/// 「导出运行详情」落盘（file_picker.saveFile）。与列表导出同口径：复用系统保存面板、
/// 不引新依赖。
///
/// 内容 = 概要（名称 / 类型 / 状态 / 模型 / 创建时间 / 会话级合计）+ 每一步（步序 ·
/// 步类型 · 角色 + 模型 / token / 延迟 + 安全标记 + 原文）。逐步明细是详情页独有的，
/// 列表导出只给概要，两者不重叠。
String buildRunTraceDetailMarkdown(RunTraceDetail detail) {
  final run = detail.run;
  final buffer = StringBuffer();
  buffer.writeln('# AI 运行详情');
  buffer.writeln();
  buffer.writeln('导出时间：${_exportStamp()}');
  buffer.writeln();
  buffer.writeln('运行 ID：${run.id}');
  buffer.writeln();
  buffer.writeln('## 概要');
  buffer.writeln();
  buffer.writeln('- 名称：${run.title.isEmpty ? '未命名运行' : run.title}');
  buffer.writeln('- 类型：${runKindLabel(run.kind)}');
  buffer.writeln('- 状态：${_statusLabel(run.status)}');
  buffer.writeln('- 模型：${run.model ?? '未知'}');
  buffer.writeln('- 创建时间：'
      '${run.createdAt == null ? '未知' : formatLocalDayMinute(run.createdAt!)}');
  buffer.writeln('- 合计：${_totals(detail.steps)}');
  buffer.writeln();

  final steps = detail.steps;
  buffer.writeln('## 步骤（${steps.length} 步）');
  buffer.writeln();
  for (var i = 0; i < steps.length; i++) {
    final s = steps[i];
    buffer.writeln('### 第 ${i + 1} 步 · ${s.step} · ${_roleLabel(s.role)}');
    buffer.writeln();
    final safety = <String>[
      if (s.blocked)
        '已拦截${s.blockReason != null ? '（${s.blockReason}）' : ''}',
      if (s.redacted) '已脱敏',
    ];
    if (safety.isNotEmpty) buffer.writeln('- 安全：${safety.join('、')}');
    buffer.writeln('- 模型：${s.model != null && s.model!.isNotEmpty ? s.model! : '模型未记录'}');
    buffer.writeln('- token：${s.usage == null ? '未记录' : '${s.usage!.total}'}');
    buffer.writeln('- 延迟：${s.latencyMs == null ? '未记录' : '${s.latencyMs} ms'}');
    buffer.writeln();
    final content = s.content.trim();
    buffer.writeln(content.isEmpty ? '（无内容）' : content);
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
  }

  return buffer.toString();
}

/// 角色 → 教师口径标签。后端 role 是受控枚举，认不出的原样显示。
String _roleLabel(String role) => switch (role) {
      'user' => '用户',
      'assistant' => '助手',
      'tool' => '工具',
      'system' => '系统',
      final other => other.isEmpty ? '未知' : other,
    };

/// 会话级合计文案（与详情页 [_RunSummaryCard._totals] 同一口径）：步级上推，
/// 没记录任何 usage / latency 时写「未记录」而不是 0。
String _totals(List<RunTraceStep> steps) {
  final hasUsage = steps.any((s) => s.usage != null);
  final hasLatency = steps.any((s) => s.latencyMs != null);
  final tokens = steps.fold<int>(0, (sum, s) => sum + (s.usage?.total ?? 0));
  final ms = steps.fold<int>(0, (sum, s) => sum + (s.latencyMs ?? 0));
  final tokenPart = hasUsage ? '$tokens token' : 'token 未记录';
  final msPart = hasLatency ? '$ms ms' : '耗时未记录';
  return '$tokenPart · $msPart';
}
