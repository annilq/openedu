import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../providers/review_notifier.dart';

String _fmtDate(DateTime? dt) {
  if (dt == null) return '—';
  final l = dt.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

/// 娃娃端错题本：查看自己答错的题（不含答案，防作弊；复习走 ReviewScreen）。
class WrongQuestionsScreen extends ConsumerStatefulWidget {
  const WrongQuestionsScreen({super.key});

  @override
  ConsumerState<WrongQuestionsScreen> createState() => _WrongQuestionsScreenState();
}

class _WrongQuestionsScreenState extends ConsumerState<WrongQuestionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(childWrongQuestionsProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(childWrongQuestionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的错题本')),
      body: switch (state) {
        WrongQuestionsInitial() || WrongQuestionsLoading() =>
          const AppLoading(message: '加载错题...'),
        WrongQuestionsError() => AppError(
            message: state.message,
            onRetry: () => ref.read(childWrongQuestionsProvider.notifier).load(),
          ),
        WrongQuestionsLoaded() => state.items.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('还没有错题，继续保持！',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20)),
                ),
              )
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(childWrongQuestionsProvider.notifier).load(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.items.length,
                  itemBuilder: (ctx, i) => _WrongQuestionCard(item: state.items[i]),
                ),
              ),
      },
    );
  }
}

class _WrongQuestionCard extends StatelessWidget {
  final WrongQuestionModel item;
  const _WrongQuestionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.stem, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(item.subject)),
                Chip(label: Text(item.knowledgePoint)),
                Chip(label: Text('错过 ${item.wrongCount} 次')),
                Chip(label: Text('复习阶段 ${item.reviewStage}')),
              ],
            ),
            const SizedBox(height: 8),
            Text('最近答错：${_fmtDate(item.firstWrongAt)}',
                style: Theme.of(context).textTheme.bodySmall),
            if (item.dueAt != null)
              Text('下次复习：${_fmtDate(item.dueAt)}',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
