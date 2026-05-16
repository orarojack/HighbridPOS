// test/repositories_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/data/repositories/auth_repository.dart';
import 'package:highbrid_pos/data/repositories/product_repository.dart';
import 'package:highbrid_pos/data/repositories/report_repository.dart';
import 'package:highbrid_pos/data/repositories/sale_repository.dart';
import 'package:highbrid_pos/data/repositories/shift_repository.dart';
import 'package:highbrid_pos/domain/models.dart';

void main() {
  late AppDatabase db;
  // An open shift for the cashier so cash sales have a shift to link to.
  late int shiftId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedIfEmpty(db);
    final shift = await ShiftRepository(db).openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 0,
    );
    shiftId = shift.id;
  });

  tearDown(() async => db.close());

  test('seed creates an admin user and sample products', () async {
    final products = await ProductRepository(db).allProducts();
    expect(products.length, 4);
    final auth = await AuthRepository(db).login('admin', 'admin123');
    expect(auth, isNotNull);
    expect(auth!.role.canManageProducts, isTrue);
  });

  test('login rejects a wrong password', () async {
    expect(await AuthRepository(db).login('admin', 'wrong'), isNull);
  });

  test('search finds a product by barcode and by name substring', () async {
    final repo = ProductRepository(db);
    expect((await repo.search('1000000000017')).single.name, 'White Bread 400g');
    expect((await repo.search('cola')).single.sku, 'DRK-001');
  });

  test('completeCashSale records the sale and deducts stock', () async {
    final products = ProductRepository(db);
    final cola = (await products.search('cola')).single;
    final before = cola.stockQty;

    final sale = await SaleRepository(db).completeCashSale(
      cashierId: 1,
      shiftId: shiftId,
      lines: [CartLine(product: cola, qty: 3)],
      tendered: 1000,
    );

    expect(sale.referenceNo, matches(r'^\d{8}-0001$'));
    expect(sale.total, 348); // 3 * 100 = 300 subtotal, +48 tax (16%)
    expect(sale.changeDue, 652);

    final after = await products.getById(cola.id);
    expect(after.stockQty, before - 3);
  });

  test('completeCashSale throws when stock is insufficient', () async {
    final products = ProductRepository(db);
    final cola = (await products.search('cola')).single;
    expect(
      () => SaleRepository(db).completeCashSale(
        cashierId: 1,
        shiftId: shiftId,
        lines: [CartLine(product: cola, qty: cola.stockQty + 1)],
        tendered: 100000,
      ),
      throwsA(isA<InsufficientStockException>()),
    );
  });

  test('a failed sale rolls back completely — no partial rows, stock unchanged',
      () async {
    final products = ProductRepository(db);
    final cola = (await products.search('cola')).single;
    final water = (await products.search('water')).single;
    final colaBefore = cola.stockQty;
    final waterBefore = water.stockQty;

    // One valid line plus one line that exceeds available stock.
    // Await so the transaction has fully rolled back before we inspect the DB.
    await expectLater(
      SaleRepository(db).completeCashSale(
        cashierId: 1,
        shiftId: shiftId,
        lines: [
          CartLine(product: water, qty: 1),
          CartLine(product: cola, qty: cola.stockQty + 1),
        ],
        tendered: 100000,
      ),
      throwsA(isA<InsufficientStockException>()),
    );

    // Nothing should have been written: the transaction rolled back.
    expect((await db.select(db.sales).get()), isEmpty);
    expect((await db.select(db.saleItems).get()), isEmpty);
    expect((await db.select(db.payments).get()), isEmpty);
    final saleMovements = await (db.select(db.stockMovements)
          ..where((m) => m.type.equals('sale')))
        .get();
    expect(saleMovements, isEmpty);

    // Stock for both products is unchanged.
    expect((await products.getById(cola.id)).stockQty, colaBefore);
    expect((await products.getById(water.id)).stockQty, waterBefore);
  });

  test('sale references increment per day', () async {
    final products = ProductRepository(db);
    final water = (await products.search('water')).single;
    final repo = SaleRepository(db);
    final s1 = await repo.completeCashSale(
        cashierId: 1,
        shiftId: shiftId,
        lines: [CartLine(product: water, qty: 1)],
        tendered: 100);
    final s2 = await repo.completeCashSale(
        cashierId: 1,
        shiftId: shiftId,
        lines: [CartLine(product: water, qty: 1)],
        tendered: 100);
    expect(s1.referenceNo.endsWith('-0001'), isTrue);
    expect(s2.referenceNo.endsWith('-0002'), isTrue);
  });

  test('dailySummary aggregates today\'s sales', () async {
    final products = ProductRepository(db);
    final water = (await products.search('water')).single;
    await SaleRepository(db).completeCashSale(
        cashierId: 1,
        shiftId: shiftId,
        lines: [CartLine(product: water, qty: 2)],
        tendered: 200);

    final summary = await ReportRepository(db).dailySummary(DateTime.now());
    expect(summary.saleCount, 1);
    expect(summary.total, 120); // 2 * 60, no tax
    expect(summary.discountTotal, 0); // no discounts applied
    expect(summary.returnCount, 0);
    expect(summary.refundTotal, 0);
  });
}
