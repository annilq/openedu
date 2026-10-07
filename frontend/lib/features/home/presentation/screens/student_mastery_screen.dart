import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/widgets/app_scroll_page.dart';
import '../providers/home_notifier.dart';
import '../widgets/mastery_board.dart';
import '../../../../shared/widgets/app_section_title.dart';

/// 学生端「我的学科掌握度」：用自身 id 拉取掌握度看板，按学科色着色。
class StudentMasteryScreen extends ConsumerStatefulWidget {
  final UserModel user;
  const StudentMasteryScreen({super.key, required this.user});

  @override
  ConsumerState<StudentMasteryScreen> createState() => _StudentMasteryScreenState();
}

class _StudentMasteryScreenState extends ConsumerState<StudentMasteryScreen> {
  @override
  void initState() {
    super.initState();
    // 娃端以自身 id 拉取掌握度（教师端由学生详情页按 user.id 触发）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(masteryNotifierProvider.notifier).load(widget.user.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScrollPage(
      children: [
        const SectionTitle('我的学科掌握度'),
        MasteryBoard(isStudent: true),
      ],
    );
  }
}
