// 仓库接口 barrel：跨 feature 复用的 Repository 抽象在此统一转出，
// 调用点 `import 'package:kids_learn/shared/domain/repositories/repositories.dart'`
// 一行不用改（ADR-0036 / ADR-0058 P1）。
//
// 注意：Repository *实现*（Impl）仍留在各 feature 的 `data/`，由 feature 组合根
// 装配——本文件只转出抽象，避免 `shared -> features` 倒置（R1）。

export 'classes_repository.dart';
export 'students_repository.dart';
