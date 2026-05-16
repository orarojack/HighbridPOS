// test/pin_auth_test.dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/data/repositories/auth_repository.dart';

void main() {
  late AppDatabase db;
  late AuthRepository auth;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedIfEmpty(db);
    auth = AuthRepository(db);
  });

  tearDown(() async => db.close());

  Future<User> userByStaffId(String staffId) => (db.select(db.users)
        ..where((u) => u.staffId.equals(staffId)))
      .getSingle();

  test('loginWithPin succeeds with correct Staff ID + PIN', () async {
    final result = await auth.loginWithPin('CSH-001', '000000');

    expect(result.outcome, PinLoginOutcome.ok);
    expect(result.user, isNotNull);
    expect(result.user!.username, 'cashier');

    final row = await userByStaffId('CSH-001');
    expect(row.lastLoginAt, isNotNull);
    expect(row.pinFailedAttempts, 0);
  });

  test('loginWithPin with a wrong PIN returns badCredentials and increments '
      'pin_failed_attempts', () async {
    final result = await auth.loginWithPin('CSH-001', '999999');

    expect(result.outcome, PinLoginOutcome.badCredentials);
    expect(result.user, isNull);

    final row = await userByStaffId('CSH-001');
    expect(row.pinFailedAttempts, 1);
  });

  test('loginWithPin with an unknown Staff ID returns badCredentials',
      () async {
    final result = await auth.loginWithPin('NOPE-999', '000000');
    expect(result.outcome, PinLoginOutcome.badCredentials);
    expect(result.user, isNull);
  });

  test('loginWithPin treats a malformed PIN as badCredentials', () async {
    final result = await auth.loginWithPin('CSH-001', '12');
    expect(result.outcome, PinLoginOutcome.badCredentials);
    expect(result.user, isNull);
  });

  test('5 consecutive wrong PINs locks the account; correct PIN then returns '
      'locked', () async {
    for (var i = 0; i < 4; i++) {
      final r = await auth.loginWithPin('CSH-001', '999999');
      expect(r.outcome, PinLoginOutcome.badCredentials);
    }
    // 5th wrong attempt locks.
    final fifth = await auth.loginWithPin('CSH-001', '999999');
    expect(fifth.outcome, PinLoginOutcome.locked);
    expect(fifth.lockedUntil, isNotNull);

    final row = await userByStaffId('CSH-001');
    expect(row.pinLockedUntil, isNotNull);
    expect(row.pinLockedUntil!.isAfter(DateTime.now()), isTrue);

    // Even a correct PIN is rejected while locked.
    final correct = await auth.loginWithPin('CSH-001', '000000');
    expect(correct.outcome, PinLoginOutcome.locked);
    expect(correct.user, isNull);
  });

  test('unlockPin clears the lock and resets failed attempts', () async {
    for (var i = 0; i < 5; i++) {
      await auth.loginWithPin('CSH-001', '999999');
    }
    await auth.unlockPin('CSH-001');

    final row = await userByStaffId('CSH-001');
    expect(row.pinLockedUntil, isNull);
    expect(row.pinFailedAttempts, 0);

    // Correct PIN now succeeds again.
    final result = await auth.loginWithPin('CSH-001', '000000');
    expect(result.outcome, PinLoginOutcome.ok);
  });

  test('loginWithPin returns inactive for a deactivated account', () async {
    await (db.update(db.users)..where((u) => u.staffId.equals('CSH-001')))
        .write(const UsersCompanion(active: Value(false)));

    final result = await auth.loginWithPin('CSH-001', '000000');
    expect(result.outcome, PinLoginOutcome.inactive);
    expect(result.user, isNull);
  });

  test('resetPin sets a new pin_hash and force_pin_change = true', () async {
    final id = (await userByStaffId('CSH-001')).id;
    await auth.resetPin(id, '123456');

    final row = await userByStaffId('CSH-001');
    expect(row.forcePinChange, isTrue);
    expect(row.pinFailedAttempts, 0);
    expect(row.pinLockedUntil, isNull);

    final result = await auth.loginWithPin('CSH-001', '123456');
    expect(result.outcome, PinLoginOutcome.ok);
  });

  test('changePin sets a new pin_hash and force_pin_change = false', () async {
    final id = (await userByStaffId('CSH-001')).id;
    await auth.changePin(id, '654321');

    final row = await userByStaffId('CSH-001');
    expect(row.forcePinChange, isFalse);

    final result = await auth.loginWithPin('CSH-001', '654321');
    expect(result.outcome, PinLoginOutcome.ok);
  });
}
