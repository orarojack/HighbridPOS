// lib/data/repositories/product_repository.dart
import 'package:drift/drift.dart';

import '../../domain/models.dart';
import '../db/app_database.dart';

class ProductRepository {
  ProductRepository(this._db);
  final AppDatabase _db;

  Future<List<Product>> allProducts({bool activeOnly = false}) async {
    final query = _db.select(_db.products);
    if (activeOnly) query.where((p) => p.active.equals(true));
    query.orderBy([(p) => OrderingTerm(expression: p.name)]);
    final rows = await query.get();
    return rows.map(_toProduct).toList();
  }

  /// Active-product lookup by exact barcode, SKU, or case-insensitive name
  /// substring. Used by the POS search box.
  Future<List<Product>> search(String term) async {
    final t = term.trim();
    if (t.isEmpty) return allProducts(activeOnly: true);
    final like = '%${t.toLowerCase()}%';
    final query = _db.select(_db.products)
      ..where((p) =>
          p.active.equals(true) &
          (p.barcode.equals(t) |
              p.sku.equals(t) |
              p.name.lower().like(like)))
      ..orderBy([(p) => OrderingTerm(expression: p.name)]);
    final rows = await query.get();
    return rows.map(_toProduct).toList();
  }

  Future<Product> getById(int id) async {
    final row = await (_db.select(_db.products)..where((p) => p.id.equals(id)))
        .getSingle();
    return _toProduct(row);
  }

  Future<int> create({
    required String sku,
    String? barcode,
    required String name,
    String description = '',
    int? categoryId,
    required int costPrice,
    required int sellPrice,
    required double taxRate,
    required int stockQty,
    required int reorderLevel,
  }) async {
    return _db.transaction(() async {
      final id = await _db.into(_db.products).insert(ProductsCompanion.insert(
            sku: sku,
            barcode: Value(barcode),
            name: name,
            description: Value(description),
            categoryId: Value(categoryId),
            costPrice: Value(costPrice),
            sellPrice: sellPrice,
            taxRate: Value(taxRate),
            stockQty: Value(stockQty),
            reorderLevel: Value(reorderLevel),
          ));
      if (stockQty != 0) {
        await _db.into(_db.stockMovements).insert(
              StockMovementsCompanion.insert(
                productId: id,
                type: 'adjustment',
                qtyDelta: stockQty,
                note: const Value('Opening stock on product create'),
              ),
            );
      }
      return id;
    });
  }

  Future<void> update(
    int id, {
    required String sku,
    String? barcode,
    required String name,
    String description = '',
    int? categoryId,
    required int costPrice,
    required int sellPrice,
    required double taxRate,
    required int reorderLevel,
    required bool active,
  }) async {
    await (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        sku: Value(sku),
        barcode: Value(barcode),
        name: Value(name),
        description: Value(description),
        categoryId: Value(categoryId),
        costPrice: Value(costPrice),
        sellPrice: Value(sellPrice),
        taxRate: Value(taxRate),
        reorderLevel: Value(reorderLevel),
        active: Value(active),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Deactivates a product (soft delete — keeps sale history intact).
  Future<void> deactivate(int id) async {
    await (_db.update(_db.products)..where((p) => p.id.equals(id)))
        .write(ProductsCompanion(
      active: const Value(false),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<List<Category>> allCategories() async {
    final rows = await (_db.select(_db.categories)
          ..orderBy([(c) => OrderingTerm(expression: c.name)]))
        .get();
    return rows.map((c) => Category(id: c.id, name: c.name)).toList();
  }

  Product _toProduct(ProductData row) => Product(
        id: row.id,
        sku: row.sku,
        barcode: row.barcode,
        name: row.name,
        description: row.description,
        categoryId: row.categoryId,
        costPrice: row.costPrice,
        sellPrice: row.sellPrice,
        taxRate: row.taxRate,
        stockQty: row.stockQty,
        reorderLevel: row.reorderLevel,
        active: row.active,
      );
}
