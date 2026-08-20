import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../domain/repositories/children_repository.dart';

sealed class ChildrenState {
  const ChildrenState();
}

class ChildrenInitial extends ChildrenState {
  const ChildrenInitial();
}

class ChildrenLoading extends ChildrenState {
  const ChildrenLoading();
}

class ChildrenLoaded extends ChildrenState {
  final List<UserModel> children;
  const ChildrenLoaded(this.children);
}

class ChildrenError extends ChildrenState {
  final String message;
  const ChildrenError(this.message);
}

class ChildrenNotifier extends StateNotifier<ChildrenState> {
  final ChildrenRepository _repo;
  ChildrenNotifier(this._repo) : super(const ChildrenInitial());

  Future<void> loadChildren() async {
    state = const ChildrenLoading();
    try {
      final children = await _repo.getChildren();
      state = ChildrenLoaded(children);
    } catch (e) {
      state = ChildrenError(e.toString());
    }
  }

  Future<void> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
  }) async {
    try {
      await _repo.createChild(
        username: username,
        password: password,
        displayName: displayName,
        grade: grade,
      );
      await loadChildren();
    } catch (e) {
      state = ChildrenError(e.toString());
    }
  }
}
