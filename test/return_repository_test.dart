// test/return_repository_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/data/repositories/return_repository.dart';
import 'package:highbrid_pos/data/repositories/sale_repository.dart';
import 'package:highbrid_pos/data/repositories/shift_repository.dart';
import 'package:highbrid_pos/domain/enums.dart';
import 'package:highbrid_pos/domain/models.dart';

void main() {
  late AppDatabase db;
  late ReturnRepository repo;
  late Shift shift;
  late SaleRecord sale;
  late Product rice; // taxed product, qty 4
  late Product bread; // zero-tax product, qty 2

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedIfEmpty(db);
    repo = ReturnRepository(db);

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

    sale = await SaleRepository(db).completeCashSale(
      cashierId: 1,
      shiftId: shift.id,
      lines: [
        CartLine(product: rice, qty: 4),
        CartLine(product: bread, qty: 2),
      ],
      tendered: 1000000,
    );
  });

  tearDown(() async => db.close());

  test('findSaleForReturn returns the sale with per-line returnable info',
      () async {
    final view = await repo.findSaleForReturn(sale.referenceNo);
    expect(view, isNotNull);
    expect(view!.originalSaleId, sale.id);
    expect(view.originalReference, sale.referenceNo);
    expect(view.lines.length, 2);

    final riceLine = view.lines.firstWhere((l) => l.productId == rice.id);
    expect(riceLine.soldQty, 4);
    expect(riceLine.alreadyReturnedQty, 0);
    expect(riceLine.returnableQty, 4);

    final breadLine = view.lines.firstWhere((l) => l.productId == bread.id);
    expect(breadLine.soldQty, 2);
    expect(breadLine.alreadyReturnedQty, 0);
    expect(breadLine.returnableQty, 2);
  });

  test('findSaleForReturn returns null for an unknown reference', () async {
    expect(await repo.findSaleForReturn('NOPE-9999'), isNull);
  });

  test('recordReturn writes return, items, refund payment, movements, event',
      () async {
    final view = (await repo.findSaleForReturn(sale.referenceNo))!;
    // Return 2 of the 4 rice units.
    final riceLine = view.lines.firstWhere((l) => l.productId == rice.id);

    final record = await repo.recordReturn(
      originalSaleId: sale.id,
      cashierId: 1,
      shiftId: shift.id,
      reason: 'damaged',
      approvedBy: 1,
      selectedLines: [riceLine.copyWith(selectedQty: 2)],
    );

    // RET-YYYYMMDD-NNNN reference.
    expect(record.referenceNo, matches(RegExp(r'^RET-\d{8}-\d{4}$')));
    expect(record.originalSaleId, sale.id);
    expect(record.cashierId, 1);
    expect(record.shiftId, shift.id);
    expect(record.reason, 'damaged');
    expect(record.approvedBy, 1);
    expect(record.lines.length, 1);

    // refund total: 450 * 2 = 900 subtotal, tax (900 * 0.16).round() = 144.
    expect(record.refundTotal, 1044);
    expect(record.lines.single.qty, 2);
    expect(record.lines.single.lineTotal, 1044);

    // returns row persisted.
    final returnRows = await db.select(db.returns).get();
    expect(returnRows.length, 1);
    expect(returnRows.single.referenceNo, record.referenceNo);

    // return_items row persisted.
    final itemRows = await db.select(db.returnItems).get();
    expect(itemRows.length, 1);
    expect(itemRows.single.qty, 2);

    // refund payment: negative amount, cash, returnId set, saleId = original.
    final refundPayment = await (db.select(db.payments)
          ..where((p) => p.returnId.equals(record.id)))
        .getSingle();
    expect(refundPayment.amount, -1044);
    expect(refundPayment.method, PaymentMethod.cash.name);
    expect(refundPayment.saleId, sale.id);

    // stock movement: type 'return', positive qtyDelta.
    final movements = await (db.select(db.stockMovements)
          ..where((m) => m.type.equals('return')))
        .get();
    expect(movements.length, 1);
    expect(movements.single.qtyDelta, 2);
    expect(movements.single.productId, rice.id);

    // refund cash event.
    final refundEvents = await (db.select(db.cashEvents)
          ..where((e) => e.type.equals(CashEventType.refund.name)))
        .get();
    expect(refundEvents.length, 1);
    expect(refundEvents.single.amount, 1044);
    expect(refundEvents.single.shiftId, shift.id);

    // shift refundTotal incremented.
    final shiftRow = await (db.select(db.shifts)
          ..where((s) => s.id.equals(shift.id)))
        .getSingle();
    expect(shiftRow.refundTotal, 1044);

    // product stock restored: rice started at 40, sold 4 -> 36, returned 2 -> 38.
    final riceRow = await (db.select(db.products)
          ..where((p) => p.id.equals(rice.id)))
        .getSingle();
    expect(riceRow.stockQty, 38);
  });

  test('findSaleForReturn reflects alreadyReturnedQty after a return',
      () async {
    final view = (await repo.findSaleForReturn(sale.referenceNo))!;
    final riceLine = view.lines.firstWhere((l) => l.productId == rice.id);
    await repo.recordReturn(
      originalSaleId: sale.id,
      cashierId: 1,
      shiftId: shift.id,
      reason: 'damaged',
      approvedBy: 1,
      selectedLines: [riceLine.copyWith(selectedQty: 3)],
    );

    final after = (await repo.findSaleForReturn(sale.referenceNo))!;
    final riceAfter = after.lines.firstWhere((l) => l.productId == rice.id);
    expect(riceAfter.soldQty, 4);
    expect(riceAfter.alreadyReturnedQty, 3);
    expect(riceAfter.returnableQty, 1);
  });

  test('recordReturn throws OverReturnException when qty exceeds returnable',
      () async {
    final view = (await repo.findSaleForReturn(sale.referenceNo))!;
    final riceLine = view.lines.firstWhere((l) => l.productId == rice.id);

    expect(
      () => repo.recordReturn(
        originalSaleId: sale.id,
        cashierId: 1,
        shiftId: shift.id,
        reason: 'too many',
        approvedBy: 1,
        selectedLines: [riceLine.copyWith(selectedQty: 5)],
      ),
      throwsA(isA<OverReturnException>()),
    );
  });

  test('recordReturn throws OverReturnException when cumulative qty exceeds',
      () async {
    final view = (await repo.findSaleForReturn(sale.referenceNo))!;
    final riceLine = view.lines.firstWhere((l) => l.productId == rice.id);
    await repo.recordReturn(
      originalSaleId: sale.id,
      cashierId: 1,
      shiftId: shift.id,
      reason: 'first',
      approvedBy: 1,
      selectedLines: [riceLine.copyWith(selectedQty: 3)],
    );

    // Only 1 left returnable; requesting 2 must throw, and write nothing.
    final after = (await repo.findSaleForReturn(sale.referenceNo))!;
    final riceAfter = after.lines.firstWhere((l) => l.productId == rice.id);
    expect(
      () => repo.recordReturn(
        originalSaleId: sale.id,
        cashierId: 1,
        shiftId: shift.id,
        reason: 'second',
        approvedBy: 1,
        selectedLines: [riceAfter.copyWith(selectedQty: 2)],
      ),
      throwsA(isA<OverReturnException>()),
    );

    // No second return was written (transaction rolled back).
    expect((await db.select(db.returns).get()).length, 1);
  });

  test('return references increment per day', () async {
    final view = (await repo.findSaleForReturn(sale.referenceNo))!;
    final riceLine = view.lines.firstWhere((l) => l.productId == rice.id);
    final breadLine = view.lines.firstWhere((l) => l.productId == bread.id);

    final first = await repo.recordReturn(
      originalSaleId: sale.id,
      cashierId: 1,
      shiftId: shift.id,
      reason: 'a',
      approvedBy: 1,
      selectedLines: [riceLine.copyWith(selectedQty: 1)],
    );
    final second = await repo.recordReturn(
      originalSaleId: sale.id,
      cashierId: 1,
      shiftId: shift.id,
      reason: 'b',
      approvedBy: 1,
      selectedLines: [breadLine.copyWith(selectedQty: 1)],
    );

    expect(first.referenceNo, endsWith('-0001'));
    expect(second.referenceNo, endsWith('-0002'));
  });

  test('getReturn returns the persisted record with its lines', () async {
    final view = (await repo.findSaleForReturn(sale.referenceNo))!;
    final riceLine = view.lines.firstWhere((l) => l.productId == rice.id);
    final created = await repo.recordReturn(
      originalSaleId: sale.id,
      cashierId: 1,
      shiftId: shift.id,
      reason: 'damaged',
      approvedBy: 1,
      selectedLines: [riceLine.copyWith(selectedQty: 2)],
    );

    final loaded = await repo.getReturn(created.id);
    expect(loaded, created);
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
