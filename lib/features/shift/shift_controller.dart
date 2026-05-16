// lib/features/shift/shift_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/shift_repository.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../auth/auth_controller.dart';

/// The terminal this POS instance runs on. Single-till deployment for now.
const String kTerminalId = 'TILL-001';

/// Tracks the current open [Shift] for the signed-in user.
///
/// State is an [AsyncValue]: loading while the repository is queried, `data`
/// with the open shift or `null` when no shift is open, `error` on failure.
/// The controller rebuilds when the signed-in user changes.
class ShiftController extends StateNotifier<AsyncValue<Shift?>> {
  ShiftController(this._ref, this._userId)
      : super(const AsyncValue.loading()) {
    refresh();
  }

  final Ref _ref;
  final int? _userId;

  ShiftRepository get _repo => _ref.read(shiftRepositoryProvider);

  /// Re-reads the current open shift for the signed-in user.
  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) {
      state = const AsyncValue.data(null);
      return;
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.currentOpenShift(userId));
  }

  /// Opens a shift for the signed-in user with [openingFloat] cents.
  /// Returns the opened [Shift]. Throws [ShiftAlreadyOpenException] if a
  /// shift is already open, or [StateError] if no user is signed in.
  Future<Shift> start(int openingFloat) async {
    final userId = _userId;
    if (userId == null) {
      throw StateError('No user is signed in.');
    }
    final shift = await _repo.openShift(
      userId: userId,
      terminalId: kTerminalId,
      openingFloat: openingFloat,
    );
    state = AsyncValue.data(shift);
    return shift;
  }

  /// Closes the open shift, recording [countedCash] cents, an optional
  /// [note], and the [closedBy] user id (the approver for a non-zero
  /// variance, otherwise the cashier). Returns the closed [Shift].
  Future<Shift> end({
    required int shiftId,
    required int countedCash,
    required String note,
    required int closedBy,
  }) async {
    final shift = await _repo.closeShift(
      shiftId: shiftId,
      countedCash: countedCash,
      closedBy: closedBy,
      note: note,
    );
    state = const AsyncValue.data(null);
    return shift;
  }
}

/// Exposes the current open shift for the signed-in user. Rebuilds when the
/// authenticated user changes.
final shiftControllerProvider =
    StateNotifierProvider<ShiftController, AsyncValue<Shift?>>((ref) {
  final user = ref.watch(authControllerProvider);
  return ShiftController(ref, user?.id);
});
