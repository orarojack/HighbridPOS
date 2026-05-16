// test/migration_test.dart
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';

void main() {
  group('schema v2 — forward path (onCreate)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    test('schemaVersion is 3', () {
      expect(db.schemaVersion, 3);
    });

    test('a fresh v2 database has the shifts and cash_events tables', () async {
      // Touching the executor opens the DB and runs onCreate.
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' ORDER BY name",
          )
          .get();
      final names = tables.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('shifts'));
      expect(names, contains('cash_events'));
    });

    test('users table has the new PIN columns', () async {
      final cols = await db
          .customSelect("PRAGMA table_info('users')")
          .get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(
        names,
        containsAll(<String>[
          'staff_id',
          'pin_hash',
          'pin_failed_attempts',
          'pin_locked_until',
          'force_pin_change',
          'last_login_at',
        ]),
      );
    });

    test('sales table has the shift_id column', () async {
      final cols = await db
          .customSelect("PRAGMA table_info('sales')")
          .get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('shift_id'));
    });

    test('can insert a user with PIN fields and a shift + cash event',
        () async {
      final userId = await db.into(db.users).insert(
            UsersCompanion.insert(
              username: 'cashier1',
              passwordHash: 'x',
              fullName: 'Cashier One',
              role: 'cashier',
              staffId: const Value('USR-001'),
              pinHash: const Value('pinhash'),
              forcePinChange: const Value(true),
            ),
          );

      final user =
          await (db.select(db.users)..where((t) => t.id.equals(userId)))
              .getSingle();
      expect(user.staffId, 'USR-001');
      expect(user.pinHash, 'pinhash');
      expect(user.pinFailedAttempts, 0); // default applied
      expect(user.forcePinChange, isTrue);
      expect(user.pinLockedUntil, isNull);
      expect(user.lastLoginAt, isNull);

      final shiftId = await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              userId: userId,
              terminalId: 'T1',
              openingFloat: 10000,
              status: 'open',
            ),
          );
      final shift =
          await (db.select(db.shifts)..where((t) => t.id.equals(shiftId)))
              .getSingle();
      expect(shift.status, 'open');
      expect(shift.openingFloat, 10000);
      expect(shift.cashSalesTotal, 0); // default
      expect(shift.note, '');

      final eventId = await db.into(db.cashEvents).insert(
            CashEventsCompanion.insert(
              shiftId: shiftId,
              userId: userId,
              type: 'payIn',
              amount: const Value(2500),
              reason: const Value('float top-up'),
            ),
          );
      final event = await (db.select(db.cashEvents)
            ..where((t) => t.id.equals(eventId)))
          .getSingle();
      expect(event.type, 'payIn');
      expect(event.amount, 2500);
      expect(event.shiftId, shiftId);
    });

    test('a sale can be linked to a shift via shift_id', () async {
      final userId = await db.into(db.users).insert(
            UsersCompanion.insert(
              username: 'c2',
              passwordHash: 'x',
              fullName: 'C Two',
              role: 'cashier',
            ),
          );
      final shiftId = await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              userId: userId,
              terminalId: 'T1',
              openingFloat: 0,
              status: 'open',
            ),
          );
      final saleId = await db.into(db.sales).insert(
            SalesCompanion.insert(
              referenceNo: 'S-001',
              cashierId: userId,
              subtotal: 1000,
              taxTotal: 0,
              total: 1000,
              status: 'completed',
              shiftId: Value(shiftId),
            ),
          );
      final sale =
          await (db.select(db.sales)..where((t) => t.id.equals(saleId)))
              .getSingle();
      expect(sale.shiftId, shiftId);
    });
  });

  group('schema v2 — upgrade path (v1 -> v2)', () {
    late Directory tmpDir;
    late File dbFile;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('hbpos_migration_');
      dbFile = File('${tmpDir.path}/app.db');
    });

    tearDown(() async {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    });

    test('a v1-shaped database upgrades and backfills staff_id', () async {
      // Build a true v1-shaped database on an on-disk file: drop every table
      // drift's createAll() made and recreate the Slice 1 (v1) schema by raw
      // SQL — users without PIN columns, sales without shift_id, and no
      // shifts/cash_events tables. An on-disk file lets us close the v1
      // connection and re-open the same DB as v2 to trigger onUpgrade.
      final v1 = AppDatabase(NativeDatabase(dbFile));
      await v1.customStatement('PRAGMA foreign_keys = OFF');
      for (final t in const [
        'users',
        'categories',
        'products',
        'sales',
        'sale_items',
        'payments',
        'stock_movements',
        'shifts',
        'cash_events',
      ]) {
        await v1.customStatement('DROP TABLE IF EXISTS "$t"');
      }
      // Recreate only the v1 tables the v1->v2 migration touches.
      await v1.customStatement(
        'CREATE TABLE users ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'username TEXT NOT NULL UNIQUE, '
        'password_hash TEXT NOT NULL, '
        'full_name TEXT NOT NULL, '
        'role TEXT NOT NULL, '
        'active INTEGER NOT NULL DEFAULT 1, '
        "created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')))",
      );
      await v1.customStatement(
        'CREATE TABLE sales ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'reference_no TEXT NOT NULL UNIQUE, '
        'cashier_id INTEGER NOT NULL REFERENCES users (id), '
        'subtotal INTEGER NOT NULL, '
        'tax_total INTEGER NOT NULL, '
        'total INTEGER NOT NULL, '
        'status TEXT NOT NULL, '
        "created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')))",
      );
      // payments existed in v1; the v2->v3 migration ALTERs it (return_id),
      // so it must be present for the chained 1->3 upgrade to succeed.
      await v1.customStatement(
        'CREATE TABLE payments ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'sale_id INTEGER NOT NULL REFERENCES sales (id), '
        'method TEXT NOT NULL, '
        'amount INTEGER NOT NULL, '
        'tendered INTEGER NOT NULL, '
        'change_due INTEGER NOT NULL, '
        "created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')))",
      );
      await v1.customStatement(
        "INSERT INTO users (username, password_hash, full_name, role) "
        "VALUES ('admin', 'h', 'Admin', 'manager')",
      );
      await v1.customStatement('PRAGMA user_version = 1');
      await v1.close();

      // Re-open the SAME database file as a v2 AppDatabase. The
      // schemaVersion bump (1 -> 2) triggers the onUpgrade migration.
      final v2 = AppDatabase(NativeDatabase(dbFile));
      try {
        // Force the DB to open and run the migration.
        final users = await v2.select(v2.users).get();
        expect(users, hasLength(1));
        final admin = users.single;
        // staff_id was backfilled by the migration.
        expect(admin.staffId, 'USR-${admin.id.toString().padLeft(3, '0')}');
        expect(admin.username, 'admin'); // pre-existing data preserved
        expect(admin.pinFailedAttempts, 0); // new column default

        // New tables exist after upgrade.
        final tables = await v2
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table'",
            )
            .get();
        final names = tables.map((r) => r.read<String>('name')).toSet();
        expect(names, containsAll(<String>['shifts', 'cash_events']));

        // sales gained shift_id.
        final saleCols =
            await v2.customSelect("PRAGMA table_info('sales')").get();
        expect(
          saleCols.map((r) => r.read<String>('name')),
          contains('shift_id'),
        );
      } finally {
        await v2.close();
      }
    });
  });
}
