// lib/data/repositories/auth_repository.dart
import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../db/app_database.dart';

/// Outcome of a PIN login attempt.
enum PinLoginOutcome { ok, badCredentials, locked, inactive }

/// Result of a PIN login attempt: an [outcome] plus, when relevant, the
/// authenticated [user] or the [lockedUntil] timestamp.
class PinLoginResult {
  final PinLoginOutcome outcome;
  final AppUser? user;
  final DateTime? lockedUntil;
  const PinLoginResult(this.outcome, {this.user, this.lockedUntil});
}

class AuthRepository {
  AuthRepository(this._db);
  final AppDatabase _db;

  /// Number of consecutive wrong PINs that triggers a lockout.
  static const int maxPinAttempts = 5;

  /// How long an account stays locked after [maxPinAttempts] failures.
  static const Duration lockoutDuration = Duration(minutes: 15);

  /// Returns the user on a correct password for an active account, else null.
  Future<AppUser?> login(String username, String password) async {
    final row = await (_db.select(_db.users)
          ..where((u) => u.username.equals(username)))
        .getSingleOrNull();
    if (row == null || !row.active) return null;
    if (!BCrypt.checkpw(password, row.passwordHash)) return null;
    await (_db.update(_db.users)..where((u) => u.id.equals(row.id)))
        .write(UsersCompanion(lastLoginAt: Value(DateTime.now())));
    return _toUser(row);
  }

  /// Authenticates a user by Staff ID + 6-digit PIN, applying failed-attempt
  /// counting and lockout. A malformed PIN is treated as bad credentials.
  Future<PinLoginResult> loginWithPin(String staffId, String pin) async {
    final row = await (_db.select(_db.users)
          ..where((u) => u.staffId.equals(staffId)))
        .getSingleOrNull();
    if (row == null || row.pinHash == null) {
      return const PinLoginResult(PinLoginOutcome.badCredentials);
    }
    if (!row.active) {
      return const PinLoginResult(PinLoginOutcome.inactive);
    }

    final lockedUntil = row.pinLockedUntil;
    if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
      return PinLoginResult(PinLoginOutcome.locked, lockedUntil: lockedUntil);
    }

    final validPin = RegExp(r'^\d{6}$').hasMatch(pin);
    if (!validPin || !BCrypt.checkpw(pin, row.pinHash!)) {
      final attempts = row.pinFailedAttempts + 1;
      final justLocked = attempts >= maxPinAttempts;
      final newLock =
          justLocked ? DateTime.now().add(lockoutDuration) : null;
      await (_db.update(_db.users)..where((u) => u.id.equals(row.id)))
          .write(UsersCompanion(
        pinFailedAttempts: Value(attempts),
        pinLockedUntil: Value(newLock),
      ));
      if (justLocked) {
        return PinLoginResult(PinLoginOutcome.locked, lockedUntil: newLock);
      }
      return const PinLoginResult(PinLoginOutcome.badCredentials);
    }

    await (_db.update(_db.users)..where((u) => u.id.equals(row.id)))
        .write(UsersCompanion(
      pinFailedAttempts: const Value(0),
      pinLockedUntil: const Value(null),
      lastLoginAt: Value(DateTime.now()),
    ));
    return PinLoginResult(PinLoginOutcome.ok, user: _toUser(row));
  }

  /// Manager action: clears a PIN lockout and resets failed attempts.
  Future<void> unlockPin(String staffId) async {
    await (_db.update(_db.users)..where((u) => u.staffId.equals(staffId)))
        .write(const UsersCompanion(
      pinFailedAttempts: Value(0),
      pinLockedUntil: Value(null),
    ));
  }

  /// Manager action: sets a new PIN and forces the user to change it on next
  /// login. Also clears any lockout / failed attempts.
  Future<void> resetPin(int userId, String newPin) async {
    await (_db.update(_db.users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(
      pinHash: Value(BCrypt.hashpw(newPin, BCrypt.gensalt())),
      forcePinChange: const Value(true),
      pinFailedAttempts: const Value(0),
      pinLockedUntil: const Value(null),
    ));
  }

  /// User action: sets a new PIN and clears the forced-change flag.
  Future<void> changePin(int userId, String newPin) async {
    await (_db.update(_db.users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(
      pinHash: Value(BCrypt.hashpw(newPin, BCrypt.gensalt())),
      forcePinChange: const Value(false),
    ));
  }

  AppUser _toUser(User row) => AppUser(
        id: row.id,
        username: row.username,
        fullName: row.fullName,
        role: UserRole.fromName(row.role),
        active: row.active,
        forcePinChange: row.forcePinChange,
      );
}
