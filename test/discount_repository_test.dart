// test/discount_repository_test.dart
//
// Slice 4 Task 3: discounts persisted in sale and return repositories.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/data/repositories/return_repository.dart';
import 'package:highbrid_pos/data/repositories/sale_repository.dart';
import 'package:highbrid_pos/data/repositories/shift_repository.dart';
import 'package:highbrid_pos/domain/models.dart';

void main() {
  late AppDatabase db;
  late Shift shift;
  late Product rice; // sellPrice 450, taxRate 0.16
  late Product bread; // sellPrice 120, taxRate 0.0

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedIfEmpty(db);

    shift = await ShiftRepository(db).openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 10000,
    );

    rice = (await (db.select(db.products)
              ..where((p) => p.sku.equals('GRC-002')))
            .getSingle())
        .let(_toProduct);
    bread = (await (db.select(db.products)
              ..where((p) => p.sku.equals('GRC-001')))
            .getSingle())
        .let(_toProduct);
  });

  tearDown(() async => db.close());

  test('completeCashSale persists per-line discount and sale discountTotal',
      () async {
    // Rice: 450 * 4 = 1800 subtotal; discount 300 -> net 1500;
    //   tax (1500 * 0.16).round() = 240; total 1740.
    // Bread: 120 * 2 = 240 subtotal; discount 40 -> net 200; tax 0; total 200.
    final sale = await SaleRepository(db).completeCashSale(
      cashierId: 1,
      shiftId: shift.id,
      lines: [
        CartLine(product: rice, qty: 4, discount: 300),
        CartLine(product: bread, qty: 2, discount: 40),
      ],
      tendered: 1000000,
    );

    // sale_items.discount persisted per line.
    final saleItems = await (db.select(db.saleItems)
          ..where((i) => i.saleId.equals(sale.id)))
        .get();
    final riceItem = saleItems.firstWhere((i) => i.productId == rice.id);
    final breadItem = saleItems.firstWhere((i) => i.productId == bread.id);
    expect(riceItem.discount, 300);
    expect(riceItem.lineTax, 240);
    expect(riceItem.lineTotal, 1740);
    expect(breadItem.discount, 40);
    expect(breadItem.lineTax, 0);
    expect(breadItem.lineTotal, 200);

    // sales.discountTotal = 300 + 40 = 340.
    final saleRow = await (db.select(db.sales)
          ..where((s) => s.id.equals(sale.id)))
        .getSingle();
    expect(saleRow.discountTotal, 340);

    // SaleRecord totals reflect the discounted math.
    expect(sale.subtotal, 1800 + 240); // gross subtotal
    expect(sale.taxTotal, 240);
    expect(sale.total, 1740 + 200);

    // SaleRecord lines carry the discount.
    final riceLine =
        sale.lines.firstWhere((l) => l.nameSnapshot == rice.name);
    expect(riceLine.discount, 300);
    expect(riceLine.lineTotal, 1740);
  });

  test('return of a discounted sale line refunds the discounted amount',
      () async {
    // Rice: 450 * 4 = 1800; discount 320 over 4 units.
    final sale = await SaleRepository(db).completeCashSale(
      cashierId: 1,
      shiftId: shift.id,
      lines: [CartLine(product: rice, qty: 4, discount: 320)],
      tendered: 1000000,
    );

    final repo = ReturnRepository(db);
    final view = (await repo.findSaleForReturn(sale.referenceNo))!;
    final riceLine = view.lines.firstWhere((l) => l.productId == rice.id);
    // Original sale_item discount snapshotted onto the draft.
    expect(riceLine.saleItemDiscount, 320);

    // Return 2 of 4 units.
    // proportionalDiscount = (320 * 2 / 4).round() = 160
    // lineSubtotal = 450 * 2 = 900; lineNet = 900 - 160 = 740
    // lineTax = (740 * 0.16).round() = 118; lineTotal = 858.
    final selected = riceLine.copyWith(selectedQty: 2);
    expect(selected.lineDiscount, 160);
    expect(selected.lineNet, 740);
    expect(selected.lineTax, 118);
    expect(selected.lineTotal, 858);

    final record = await repo.recordReturn(
      originalSaleId: sale.id,
      cashierId: 1,
      shiftId: shift.id,
      reason: 'damaged',
      approvedBy: 1,
      selectedLines: [selected],
    );

    // Refund is the DISCOUNTED amount, not full price (full would be 1044).
    expect(record.refundTotal, 858);
    expect(record.lines.single.discount, 160);
    expect(record.lines.single.lineTotal, 858);

    // return_items.discount persisted.
    final itemRows = await db.select(db.returnItems).get();
    expect(itemRows.single.discount, 160);
    expect(itemRows.single.lineTotal, 858);
  });
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

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
