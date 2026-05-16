// lib/features/auth/auth_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  void logout() => state = null;
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AppUser?>(
  (ref) => AuthController(ref),
);
