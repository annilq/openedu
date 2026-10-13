/// 学生端导航的**唯一**事实源（ADR-0059），与 [TeacherPage] 同构。
///
/// 取代原先「页签索引 + `_showProfile` 布尔」的二选一（LCC-09）：布尔与索引并存等于
/// 两个真源，需要「谁压谁」的裁决且裁决散落各回调，易漏（点了「我的」忘了清页签 →
/// 两个同时亮）。合成 `sealed` 后各入口天然互斥，`switch` 穷尽性由编译器保证。
sealed class ChildPage {
  const ChildPage();
}

class ChildHomePage extends ChildPage {
  const ChildHomePage();
}

class ChildReviewPage extends ChildPage {
  const ChildReviewPage();
}

class ChildWrongQuestionsPage extends ChildPage {
  const ChildWrongQuestionsPage();
}

class ChildMasteryPage extends ChildPage {
  const ChildMasteryPage();
}

/// 学生端「我的」（个人信息）。教师端「我的」并入 [TeacherPage] 分支，学生端作为
/// 独立的 [ChildPage] 共存于同一导航状态——两者都不在页签索引里。
class ChildProfilePage extends ChildPage {
  const ChildProfilePage();
}

/// [ChildPage] → IndexedStack 下标；[ChildProfilePage] 返回 -1（不进 IndexedStack）。
int childPageIndex(ChildPage page) => switch (page) {
      ChildProfilePage() => -1,
      ChildHomePage() => 0,
      ChildReviewPage() => 1,
      ChildWrongQuestionsPage() => 2,
      ChildMasteryPage() => 3,
    };

/// 页签下标 → [ChildPage]（越界回落首页）。
ChildPage childPageFromIndex(int index) => switch (index) {
      0 => const ChildHomePage(),
      1 => const ChildReviewPage(),
      2 => const ChildWrongQuestionsPage(),
      3 => const ChildMasteryPage(),
      _ => const ChildHomePage(),
    };
