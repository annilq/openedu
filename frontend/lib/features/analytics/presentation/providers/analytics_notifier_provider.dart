import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import 'package:kids_learn/features/students/providers/students_provider.dart';
import '../../providers/analytics_provider.dart';
import 'analytics_notifier.dart';

/// 统计页 notifier 组合根：聚合 analytics / classes / students 三个仓库。
final analyticsNotifierProvider =
    StateNotifierProvider<AnalyticsNotifier, AnalyticsState>((ref) {
  final analytics = ref.watch(analyticsRepositoryProvider);
  final classes = ref.watch(classesRepositoryProvider);
  final students = ref.watch(studentsRepositoryProvider);
  return AnalyticsNotifier(analytics, classes, students);
});
