import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/assistant/domain/run_trace.dart';
import 'package:kids_learn/features/assistant/presentation/run_trace_transcript.dart';

/// [buildRunTraceMarkdown] 是「导出运行轨迹」的纯逻辑：把列表里的运行概要压成
/// 可读文本，不走网络、不依赖原生，断言喂列表即可、稳定可测。
void main() {
  group('buildRunTraceMarkdown', () {
    test('每条运行标类型 / 状态 / 模型 / 时间 / ID', () {
      final md = buildRunTraceMarkdown([
        RunTraceRun(
          id: 'r1',
          kind: 'question',
          title: '分数加减法',
          model: 'gpt-4o',
          status: 'done',
          createdAt: '2026-10-19T21:03:00',
        ),
      ]);

      expect(md, contains('# AI 运行轨迹'));
      expect(md, contains('分数加减法'));
      expect(md, contains('类型：出题'));
      expect(md, contains('状态：已完成'));
      expect(md, contains('模型：gpt-4o'));
      expect(md, contains('运行 ID：r1'));
    });

    test('kind / status 认不出的原样显示，缺省字段给占位', () {
      final md = buildRunTraceMarkdown([
        RunTraceRun(id: 'r2', kind: 'unknown-biz', status: 'weird'),
      ]);

      expect(md, contains('类型：unknown-biz'));
      expect(md, contains('状态：weird'));
      expect(md, contains('模型：未知'));
      expect(md, contains('未命名运行'));
    });

    test('空列表仍生成标题与计数，不崩', () {
      final md = buildRunTraceMarkdown(const <RunTraceRun>[]);
      expect(md, contains('# AI 运行轨迹'));
      expect(md, contains('共 0 次运行'));
    });
  });

  group('buildRunTraceDetailMarkdown', () {
    test('概要 + 全步骤（含角色 / 安全标记）一并导出', () {
      final detail = RunTraceDetail(
        run: RunTraceRun(
          id: 'r9',
          kind: 'question',
          title: '分数加减法',
          model: 'gpt-4o',
          status: 'done',
          createdAt: '2026-10-19T21:03:00',
        ),
        steps: [
          RunTraceStep(id: 's1', turn: 1, role: 'user', step: 'input', content: '出一道题'),
          RunTraceStep(
            id: 's2',
            turn: 2,
            role: 'assistant',
            step: 'output',
            content: '来看这道题',
            model: 'gpt-4o',
            latencyMs: 1200,
            usage: StepUsage(total: 350),
          ),
          RunTraceStep(
            id: 's3',
            turn: 3,
            role: 'tool',
            step: 'tool_result',
            content: 'raw params',
            blocked: true,
            blockReason: '命中红线',
          ),
        ],
      );

      final md = buildRunTraceDetailMarkdown(detail);
      expect(md, contains('# AI 运行详情'));
      expect(md, contains('运行 ID：r9'));
      expect(md, contains('步骤（3 步）'));
      expect(md, contains('第 1 步 · input · 用户'));
      expect(md, contains('出一道题'));
      expect(md, contains('第 2 步 · output · 助手'));
      expect(md, contains('350'));
      // 被拦步骤带安全标记与理由
      expect(md, contains('已拦截（命中红线）'));
    });

    test('空步骤只导出概要，不崩', () {
      final detail = RunTraceDetail(
        run: RunTraceRun(id: 'r0', kind: 'query', status: 'done'),
      );
      final md = buildRunTraceDetailMarkdown(detail);
      expect(md, contains('# AI 运行详情'));
      expect(md, contains('步骤（0 步）'));
    });
  });
}
