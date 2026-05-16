// lib/features/auth/auth_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../domain/models.dart';
import '../../providers.dart';

/// Holds the currently logged-in user, or null when logged out.
class AuthController extends StateNotifier<AppUser?> {
  AuthController(this._ref) : super(null);
  final Ref _ref;

  /// Attempts login. Returns null on success, or an error message on failure.
  Future<String?> login(String username, String password) async {
    if (username.trim().isEmpty || password.isEmpty) {
      return 'Enter a username and password.';
    }
    final user = await _ref
        .read(authRepositoryProvider)
        .login(username.trim(), password);
    if (user == null) {
      return 'Invalid username or password, or the account is disabled.';
    }
    state = user;
    return null;
  }

  /// Attempts a Staff ID + PIN login. Returns the [PinLoginResult] so the UI
  /// can branch on the outcome. On a successful login the state user is set.
  Future<PinLoginResult> loginWithPin(String staffId, String pin) async {
    final result = await _ref
        .read(authRepositoryProvider)
        .loginWithPin(staffId.trim(), pin);
    if (result.outcome == PinLoginOutcome.ok && result.user != null) {
      state = result.user;
    }
    return result;
  }

  /// Clears the [AppUser.forcePinChange] flag on the in-memory state after a
  /// successful PIN change, so the app can leave the PIN-change screen.
  void clearForcePinChange() {
    final user = state;
    if (user != null && user.forcePinChange) {
      state = AppUser(
        id: user.id,
        username: user.username,
        fullName: user.fullName,
        role: user.role,
        active: user.active,
      );
    }
  }

  void logout() => state = null;
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AppUser?>(
  (ref) => AuthController(ref),
);
