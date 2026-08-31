import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../providers/home_notifier.dart';
import '../widgets/mastery_board.dart';

/// 娃娃端「我的学科掌握度」：用自身 id 拉取掌握度看板，按学科色着色。
class ChildMasteryScreen extends ConsumerStatefulWidget {
  final UserModel user;
  const ChildMasteryScreen({super.key, required this.user});

  @override
  ConsumerState<ChildMasteryScreen> createState() => _ChildMasteryScreenState();
}

class _ChildMasteryScreenState extends ConsumerState<ChildMasteryScreen> {
  @override
  void initState() {
    super.initState();
    // 娃端以自身 id 拉取掌握度（家长端由 selectedChildProvider 触发）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(masteryNotifierProvider.notifier).load(widget.user.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl4),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('我的学科掌握度'),
              MasteryBoard(isChild: true),
            ],
          ),
        ),
      ),
    );
  }
}
