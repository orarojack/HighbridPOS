// test/discount_migration_test.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';

void main() {
  group('schema v4 — forward path (onCreate)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    test('schemaVersion is 4', () {
      expect(db.schemaVersion, 4);
    });

    test('a fresh v4 database has sale_items.discount', () async {
      final cols =
          await db.customSelect("PRAGMA table_info('sale_items')").get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('discount'));
    });

    test('a fresh v4 database has sales.discount_total', () async {
      final cols = await db.customSelect("PRAGMA table_info('sales')").get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('discount_total'));
    });

    test('a fresh v4 database has return_items.discount', () async {
      final cols =
          await db.customSelect("PRAGMA table_info('return_items')").get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('discount'));
    });

    test('the new discount columns default to 0', () async {
      final userId = await db.into(db.users).insert(
            UsersCompanion.insert(
              username: 'mgr',
              passwordHash: 'h',
              fullName: 'Manager',
              role: 'manager',
            ),
          );
      final productId = await db.into(db.products).insert(
            ProductsCompanion.insert(sku: 'P-1', name: 'Widget', sellPrice: 500),
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
      final sale = await (db.select(db.sales)
            ..where((t) => t.id.equals(saleId)))
          .getSingle();
      expect(sale.discountTotal, 0); // new column default

      final saleItemId = await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: productId,
              nameSnapshot: 'Widget',
              unitPrice: 500,
              taxRate: 0.0,
              qty: 2,
              lineTax: 0,
              lineTotal: 1000,
            ),
          );
      final saleItem = await (db.select(db.saleItems)
            ..where((t) => t.id.equals(saleItemId)))
          .getSingle();
      expect(saleItem.discount, 0); // new column default
    });
  });

  group('schema v4 — upgrade path (v3 -> v4)', () {
    late Directory tmpDir;
    late File dbFile;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('hbpos_v4_migration_');
      dbFile = File('${tmpDir.path}/app.db');
    });

    tearDown(() async {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    });

    test('a v3-shaped database upgrades to v4 without data loss', () async {
      // Build a true v3-shaped database on an on-disk file: drop every table
      // drift's createAll() made and recreate the Slice 3 (v3) schema by raw
      // SQL — sales without discount_total, sale_items without discount,
      // return_items without discount. An on-disk file lets us close the v3
      // connection and re-open the same DB as v4 to trigger onUpgrade.
      final v3 = AppDatabase(NativeDatabase(dbFile));
      await v3.customStatement('PRAGMA foreign_keys = OFF');
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
        await v3.customStatement('DROP TABLE IF EXISTS "$t"');
      }
      await v3.customStatement(
          'DROP INDEX IF EXISTS returns_reference_no_unique');
      // Recreate only the v3 tables the v3->v4 migration touches, plus the
      // FK targets needed to insert rows. A v3 sales table has no
      // discount_total; v3 sale_items / return_items have no discount.
      await v3.customStatement(
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
      await v3.customStatement(
        'CREATE TABLE products ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'sku TEXT NOT NULL UNIQUE, '
        'barcode TEXT, '
        'name TEXT NOT NULL, '
        "description TEXT NOT NULL DEFAULT '', "
        'category_id INTEGER, '
        'cost_price INTEGER NOT NULL DEFAULT 0, '
        'sell_price INTEGER NOT NULL, '
        'tax_rate REAL NOT NULL DEFAULT 0.0, '
        'stock_qty INTEGER NOT NULL DEFAULT 0, '
        'reorder_level INTEGER NOT NULL DEFAULT 0, '
        'active INTEGER NOT NULL DEFAULT 1, '
        "created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')), "
        "updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')))",
      );
      await v3.customStatement(
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
      await v3.customStatement(
        'CREATE TABLE sale_items ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'sale_id INTEGER NOT NULL REFERENCES sales (id), '
        'product_id INTEGER NOT NULL REFERENCES products (id), '
        'name_snapshot TEXT NOT NULL, '
        'unit_price INTEGER NOT NULL, '
        'tax_rate REAL NOT NULL, '
        'qty INTEGER NOT NULL, '
        'line_tax INTEGER NOT NULL, '
        'line_total INTEGER NOT NULL)',
      );
      await v3.customStatement(
        'CREATE TABLE returns ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'reference_no TEXT NOT NULL, '
        'original_sale_id INTEGER NOT NULL REFERENCES sales (id), '
        'cashier_id INTEGER NOT NULL REFERENCES users (id), '
        'shift_id INTEGER, '
        "reason TEXT NOT NULL DEFAULT '', "
        'refund_total INTEGER NOT NULL, '
        'approved_by INTEGER NOT NULL REFERENCES users (id), '
        "created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')))",
      );
      await v3.customStatement(
        'CREATE TABLE return_items ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'return_id INTEGER NOT NULL REFERENCES returns (id), '
        'sale_item_id INTEGER NOT NULL REFERENCES sale_items (id), '
        'product_id INTEGER NOT NULL REFERENCES products (id), '
        'name_snapshot TEXT NOT NULL, '
        'qty INTEGER NOT NULL, '
        'unit_price INTEGER NOT NULL, '
        'tax_rate REAL NOT NULL, '
        'line_tax INTEGER NOT NULL, '
        'line_total INTEGER NOT NULL)',
      );
      await v3.customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS returns_reference_no_unique '
        'ON returns (reference_no)',
      );
      // Seed data into the v3 tables.
      await v3.customStatement(
        "INSERT INTO users (username, password_hash, full_name, role) "
        "VALUES ('admin', 'h', 'Admin', 'manager')",
      );
      await v3.customStatement(
        "INSERT INTO products (sku, name, sell_price) "
        "VALUES ('P-1', 'Widget', 500)",
      );
      await v3.customStatement(
        "INSERT INTO sales (reference_no, cashier_id, subtotal, tax_total, "
        "total, status) VALUES ('S-001', 1, 1000, 0, 1000, 'completed')",
      );
      await v3.customStatement(
        'INSERT INTO sale_items (sale_id, product_id, name_snapshot, '
        'unit_price, tax_rate, qty, line_tax, line_total) '
        "VALUES (1, 1, 'Widget', 500, 0.0, 2, 0, 1000)",
      );
      await v3.customStatement(
        'INSERT INTO returns (reference_no, original_sale_id, cashier_id, '
        'refund_total, approved_by) VALUES ('
        "'R-001', 1, 1, 500, 1)",
      );
      await v3.customStatement(
        'INSERT INTO return_items (return_id, sale_item_id, product_id, '
        'name_snapshot, qty, unit_price, tax_rate, line_tax, line_total) '
        "VALUES (1, 1, 1, 'Widget', 1, 500, 0.0, 0, 500)",
      );
      await v3.customStatement('PRAGMA user_version = 3');
      await v3.close();

      // Re-open the SAME database file as a v4 AppDatabase. The
      // schemaVersion bump (3 -> 4) triggers the onUpgrade migration.
      final v4 = AppDatabase(NativeDatabase(dbFile));
      try {
        // Force the DB to open and run the migration.
        final users = await v4.select(v4.users).get();
        expect(users, hasLength(1));
        expect(users.single.username, 'admin'); // pre-existing data preserved

        // Pre-existing sale survives and gained discount_total default.
        final sales = await v4.select(v4.sales).get();
        expect(sales, hasLength(1));
        expect(sales.single.referenceNo, 'S-001');
        expect(sales.single.subtotal, 1000);
        expect(sales.single.discountTotal, 0); // new column default

        // Pre-existing sale item survives and gained discount default.
        final saleItems = await v4.select(v4.saleItems).get();
        expect(saleItems, hasLength(1));
        expect(saleItems.single.nameSnapshot, 'Widget');
        expect(saleItems.single.qty, 2);
        expect(saleItems.single.discount, 0); // new column default

        // Pre-existing return item survives and gained discount default.
        final returnItems = await v4.select(v4.returnItems).get();
        expect(returnItems, hasLength(1));
        expect(returnItems.single.nameSnapshot, 'Widget');
        expect(returnItems.single.lineTotal, 500);
        expect(returnItems.single.discount, 0); // new column default

        // sales gained discount_total.
        final salesCols =
            await v4.customSelect("PRAGMA table_info('sales')").get();
        expect(
          salesCols.map((r) => r.read<String>('name')),
          contains('discount_total'),
        );

        // sale_items gained discount.
        final saleItemCols =
            await v4.customSelect("PRAGMA table_info('sale_items')").get();
        expect(
          saleItemCols.map((r) => r.read<String>('name')),
          contains('discount'),
        );

        // return_items gained discount.
        final returnItemCols =
            await v4.customSelect("PRAGMA table_info('return_items')").get();
        expect(
          returnItemCols.map((r) => r.read<String>('name')),
          contains('discount'),
        );
      } finally {
        await v4.close();
      }
    });
  });
}
