// test/return_migration_test.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';

void main() {
  group('schema v3 — forward path (onCreate)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    test('schemaVersion is 3', () {
      expect(db.schemaVersion, 3);
    });

    test('a fresh v3 database has the returns and return_items tables',
        () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' ORDER BY name",
          )
          .get();
      final names = tables.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('returns'));
      expect(names, contains('return_items'));
    });

    test('payments table has the return_id column', () async {
      final cols =
          await db.customSelect("PRAGMA table_info('payments')").get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('return_id'));
    });

    test('shifts table has the refund_total column', () async {
      final cols = await db.customSelect("PRAGMA table_info('shifts')").get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('refund_total'));
    });

    test('returns_reference_no_unique index exists on a fresh v3 db',
        () async {
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index'",
          )
          .get();
      final names = indexes.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('returns_reference_no_unique'));
    });

    test('reference_no uniqueness is enforced by the index', () async {
      // FK targets must exist; FK checking is ON via beforeOpen.
      final userId = await db.into(db.users).insert(
            UsersCompanion.insert(
              username: 'mgr',
              passwordHash: 'h',
              fullName: 'Manager',
              role: 'manager',
            ),
          );
      final saleId = await db.into(db.sales).insert(
            SalesCompanion.insert(
              referenceNo: 'S-100',
              cashierId: userId,
              subtotal: 1000,
              taxTotal: 0,
              total: 1000,
              status: 'completed',
            ),
          );
      await db.into(db.returns).insert(
            ReturnsCompanion.insert(
              referenceNo: 'R-001',
              originalSaleId: saleId,
              cashierId: userId,
              refundTotal: 100,
              approvedBy: userId,
            ),
          );
      expect(
        () => db.into(db.returns).insert(
              ReturnsCompanion.insert(
                referenceNo: 'R-001',
                originalSaleId: saleId,
                cashierId: userId,
                refundTotal: 200,
                approvedBy: userId,
              ),
            ),
        throwsA(anything),
      );
    });
  });

  group('schema v3 — upgrade path (v2 -> v3)', () {
    late Directory tmpDir;
    late File dbFile;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('hbpos_v3_migration_');
      dbFile = File('${tmpDir.path}/app.db');
    });

    tearDown(() async {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    });

    test('a v2-shaped database upgrades to v3 without data loss', () async {
      // Build a true v2-shaped database on an on-disk file: drop every table
      // drift's createAll() made and recreate the Slice 2 (v2) schema by raw
      // SQL — no returns/return_items tables, payments without return_id,
      // shifts without refund_total. An on-disk file lets us close the v2
      // connection and re-open the same DB as v3 to trigger onUpgrade.
      final v2 = AppDatabase(NativeDatabase(dbFile));
      await v2.customStatement('PRAGMA foreign_keys = OFF');
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
        'returns',
        'return_items',
      ]) {
        await v2.customStatement('DROP TABLE IF EXISTS "$t"');
      }
      await v2.customStatement('DROP INDEX IF EXISTS returns_reference_no_unique');
      // Recreate only the v2 tables the v2->v3 migration touches.
      // A v2 users table already has the Slice 2 PIN columns (added by the
      // v1->v2 migration); since from == 2 the from < 2 block will NOT run.
      await v2.customStatement(
        'CREATE TABLE users ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'username TEXT NOT NULL UNIQUE, '
        'password_hash TEXT NOT NULL, '
        'full_name TEXT NOT NULL, '
        'role TEXT NOT NULL, '
        'active INTEGER NOT NULL DEFAULT 1, '
        "created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')), "
        'staff_id TEXT, '
        'pin_hash TEXT, '
        'pin_failed_attempts INTEGER NOT NULL DEFAULT 0, '
        'pin_locked_until INTEGER, '
        'force_pin_change INTEGER NOT NULL DEFAULT 0, '
        'last_login_at INTEGER)',
      );
      await v2.customStatement(
        'CREATE TABLE sales ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'reference_no TEXT NOT NULL UNIQUE, '
        'cashier_id INTEGER NOT NULL REFERENCES users (id), '
        'subtotal INTEGER NOT NULL, '
        'tax_total INTEGER NOT NULL, '
        'total INTEGER NOT NULL, '
        'status TEXT NOT NULL, '
        'shift_id INTEGER, '
        "created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')))",
      );
      await v2.customStatement(
        'CREATE TABLE payments ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'sale_id INTEGER NOT NULL REFERENCES sales (id), '
        'method TEXT NOT NULL, '
        'amount INTEGER NOT NULL, '
        'tendered INTEGER NOT NULL, '
        'change_due INTEGER NOT NULL, '
        "created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')))",
      );
      await v2.customStatement(
        'CREATE TABLE shifts ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'user_id INTEGER NOT NULL REFERENCES users (id), '
        'terminal_id TEXT NOT NULL, '
        'opening_float INTEGER NOT NULL, '
        'status TEXT NOT NULL, '
        "opened_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')), "
        'closed_at INTEGER, '
        'cash_sales_total INTEGER NOT NULL DEFAULT 0, '
        'pay_in_total INTEGER NOT NULL DEFAULT 0, '
        'pay_out_total INTEGER NOT NULL DEFAULT 0, '
        'expected_cash INTEGER, '
        'counted_cash INTEGER, '
        'variance INTEGER, '
        'closed_by INTEGER, '
        "note TEXT NOT NULL DEFAULT '', "
        "created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')))",
      );
      await v2.customStatement(
        "INSERT INTO users (username, password_hash, full_name, role) "
        "VALUES ('admin', 'h', 'Admin', 'manager')",
      );
      await v2.customStatement(
        "INSERT INTO sales (reference_no, cashier_id, subtotal, tax_total, "
        "total, status) VALUES ('S-001', 1, 1000, 0, 1000, 'completed')",
      );
      await v2.customStatement(
        'INSERT INTO payments (sale_id, method, amount, tendered, change_due) '
        "VALUES (1, 'cash', 1000, 1000, 0)",
      );
      await v2.customStatement(
        'INSERT INTO shifts (user_id, terminal_id, opening_float, status) '
        "VALUES (1, 'T1', 5000, 'open')",
      );
      await v2.customStatement('PRAGMA user_version = 2');
      await v2.close();

      // Re-open the SAME database file as a v3 AppDatabase. The
      // schemaVersion bump (2 -> 3) triggers the onUpgrade migration.
      final v3 = AppDatabase(NativeDatabase(dbFile));
      try {
        // Force the DB to open and run the migration.
        final users = await v3.select(v3.users).get();
        expect(users, hasLength(1));
        expect(users.single.username, 'admin'); // pre-existing data preserved

        // Pre-existing sale, payment and shift survive the upgrade.
        final sales = await v3.select(v3.sales).get();
        expect(sales, hasLength(1));
        expect(sales.single.referenceNo, 'S-001');

        final payments = await v3.select(v3.payments).get();
        expect(payments, hasLength(1));
        expect(payments.single.amount, 1000);
        expect(payments.single.returnId, isNull); // new column default

        final shifts = await v3.select(v3.shifts).get();
        expect(shifts, hasLength(1));
        expect(shifts.single.openingFloat, 5000);
        expect(shifts.single.refundTotal, 0); // new column default

        // New tables exist after upgrade.
        final tables = await v3
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table'",
            )
            .get();
        final tableNames =
            tables.map((r) => r.read<String>('name')).toSet();
        expect(tableNames, containsAll(<String>['returns', 'return_items']));

        // payments gained return_id.
        final payCols =
            await v3.customSelect("PRAGMA table_info('payments')").get();
        expect(
          payCols.map((r) => r.read<String>('name')),
          contains('return_id'),
        );

        // shifts gained refund_total.
        final shiftCols =
            await v3.customSelect("PRAGMA table_info('shifts')").get();
        expect(
          shiftCols.map((r) => r.read<String>('name')),
          contains('refund_total'),
        );

        // The unique index exists on an upgraded-v3 db too.
        final indexes = await v3
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index'",
            )
            .get();
        expect(
          indexes.map((r) => r.read<String>('name')),
          contains('returns_reference_no_unique'),
        );
      } finally {
        await v3.close();
      }
    });
  });
}
