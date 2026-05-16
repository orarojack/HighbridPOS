// lib/data/db/seed.dart
import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import 'app_database.dart';

/// Seeds an admin user and a sample catalog if the database is empty.
/// Idempotent: does nothing when a user already exists.
Future<void> seedIfEmpty(AppDatabase db) async {
  final existing = await db.select(db.users).get();
  if (existing.isNotEmpty) return;

  await db.transaction(() async {
    await db.into(db.users).insert(UsersCompanion.insert(
          username: 'admin',
          passwordHash: BCrypt.hashpw('admin123', BCrypt.gensalt()),
          fullName: 'Store Admin',
          role: UserRole.admin.name,
        ));

    final groceries = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'Groceries'),
        );
    final drinks = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'Drinks'),
        );

    final samples = <ProductsCompanion>[
      ProductsCompanion.insert(
        sku: 'GRC-001',
        barcode: const Value('1000000000017'),
        name: 'White Bread 400g',
        categoryId: Value(groceries),
        costPrice: const Value(80),
        sellPrice: 120,
        taxRate: const Value(0.0),
        stockQty: const Value(50),
        reorderLevel: const Value(10),
      ),
      ProductsCompanion.insert(
        sku: 'GRC-002',
        barcode: const Value('1000000000024'),
        name: 'Rice 2kg',
        categoryId: Value(groceries),
        costPrice: const Value(300),
        sellPrice: 450,
        taxRate: const Value(0.16),
        stockQty: const Value(40),
        reorderLevel: const Value(8),
      ),
      ProductsCompanion.insert(
        sku: 'DRK-001',
        barcode: const Value('1000000000031'),
        name: 'Cola 500ml',
        categoryId: Value(drinks),
        costPrice: const Value(60),
        sellPrice: 100,
        taxRate: const Value(0.16),
        stockQty: const Value(120),
        reorderLevel: const Value(24),
      ),
      ProductsCompanion.insert(
        sku: 'DRK-002',
        barcode: const Value('1000000000048'),
        name: 'Water 1L',
        categoryId: Value(drinks),
        costPrice: const Value(30),
        sellPrice: 60,
        taxRate: const Value(0.0),
        stockQty: const Value(200),
        reorderLevel: const Value(48),
      ),
    ];

    for (final p in samples) {
      final id = await db.into(db.products).insert(p);
      await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
            productId: id,
            type: MovementType.seed.name,
            qtyDelta: p.stockQty.value,
            note: const Value('Initial seed stock'),
          ));
    }
  });
}
