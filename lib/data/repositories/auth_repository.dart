// lib/data/repositories/auth_repository.dart
import 'package:bcrypt/bcrypt.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../db/app_database.dart';

class AuthRepository {
  AuthRepository(this._db);
  final AppDatabase _db;

  /// Returns the user on a correct password for an active account, else null.
  Future<AppUser?> login(String username, String password) async {
    final row = await (_db.select(_db.users)
          ..where((u) => u.username.equals(username)))
        .getSingleOrNull();
    if (row == null || !row.active) return null;
    if (!BCrypt.checkpw(password, row.passwordHash)) return null;
    return _toUser(row);
  }

  AppUser _toUser(User row) => AppUser(
        id: row.id,
        username: row.username,
        fullName: row.fullName,
        role: UserRole.fromName(row.role),
        active: row.active,
      );
}
