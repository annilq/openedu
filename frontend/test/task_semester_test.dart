import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/shared/domain/models/question.dart';
import 'package:kids_learn/shared/domain/models/task.dart';

/// 学期维度（ADR-0061 发布任务对接资料库）模型层往返测试。
///
/// 学期从「发布任务表单 → TaskSpec → 流式题卡 → 确认落库」全程透传，模型层
/// 任一环fromJson/toJson 漏字段，讲解时就匹配不到同学期的知识点交互场景。
void main() {
  group('TaskSpecModel · 学期透传', () {
    test('toJson / fromJson 往返保学期', () {
      final spec = TaskSpecModel(
        subject: '数学',
        grade: 4,
        knowledgePoint: '图形的运动（轴对称）',
        qtype: 'choice',
        count: 5,
        semester: '上学期',
      );
      final json = spec.toJson();
      expect(json['semester'], '上学期');
      // 与后端 TaskSpec 同为snake_case 键
      expect(json.containsKey('semester'), isTrue);

      final back = TaskSpecModel.fromJson(json);
      expect(back.semester, '上学期');
      expect(back.knowledgePoint, '图形的运动（轴对称）');
    });

    test('未指定学期默认为空串（整学年），老数据不炸', () {
      final spec = TaskSpecModel(
        subject: '数学',
        grade: 3,
        knowledgePoint: '分数',
        qtype: 'calc',
        count: 3,
      );
      expect(spec.semester, '');
      expect(spec.toJson()['semester'], '');
      // 老数据（后端未下发 semester）也能解析
      final back = TaskSpecModel.fromJson(spec.toJson());
      expect(back.semester, '');
    });
  });

  group('QuestionPreview · 学期随题卡回传落库', () {
    test('fromJson 读学期、toJson 原样回传（确认落库不丢）', () {
      final preview = QuestionPreview.fromJson({
        'subject': '数学',
        'grade': 4,
        'stem': '下列图形中，轴对称图形有几个？',
        'qtype': 'choice',
        'knowledge_point': '图形的运动（轴对称）',
        'semester': '下学期',
      });
      expect(preview.semester, '下学期');
      // 回传后端 /tasks/from-generated 的 payload 必须带学期
      expect(preview.toJson()['semester'], '下学期');
    });

    test('缺学期字段时回落空串（兼容旧后端）', () {
      final preview = QuestionPreview.fromJson({
        'subject': '数学',
        'grade': 3,
        'stem': '1/2 + 1/2 = ?',
        'qtype': 'calc',
        'knowledge_point': '分数',
      });
      expect(preview.semester, '');
    });
  });

  group('QuestionModel · 学期随落库题目下发', () {
    test('fromJson 读学期', () {
      final q = QuestionModel.fromJson({
        'id': 'q1',
        'stem': '题面',
        'qtype': 'choice',
        'knowledge_point': '轴对称',
        'semester': '上学期',
      });
      expect(q.semester, '上学期');
    });

    test('缺学期字段时回落空串', () {
      final q = QuestionModel.fromJson({
        'id': 'q1',
        'stem': '题面',
        'qtype': 'choice',
        'knowledge_point': '轴对称',
      });
      expect(q.semester, '');
    });
  });
}
