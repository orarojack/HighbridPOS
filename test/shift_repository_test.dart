// test/shift_repository_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/data/repositories/product_repository.dart';
import 'package:highbrid_pos/data/repositories/sale_repository.dart';
import 'package:highbrid_pos/data/repositories/shift_repository.dart';
import 'package:highbrid_pos/domain/enums.dart';
import 'package:highbrid_pos/domain/models.dart';

void main() {
  late AppDatabase db;
  late ShiftRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedIfEmpty(db);
    repo = ShiftRepository(db);
  });

  tearDown(() async => db.close());

  test('openShift creates an open shift and a shiftOpen cash event', () async {
    final shift = await repo.openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 10000,
    );

    expect(shift.status, ShiftStatus.open);
    expect(shift.userId, 1);
    expect(shift.terminalId, 'TILL-001');
    expect(shift.openingFloat, 10000);
    expect(shift.cashSalesTotal, 0);
    expect(shift.closedAt, isNull);

    final events = await db.select(db.cashEvents).get();
    expect(events.length, 1);
    expect(events.single.type, CashEventType.shiftOpen.name);
    expect(events.single.amount, 10000);
    expect(events.single.shiftId, shift.id);
  });

  test('currentOpenShift returns the open shift, or null when none', () async {
    expect(await repo.currentOpenShift(1), isNull);

    final opened = await repo.openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 5000,
    );
    final current = await repo.currentOpenShift(1);
    expect(current, isNotNull);
    expect(current!.id, opened.id);
  });

  test('currentOpenShift returns null after the shift is closed', () async {
    final opened = await repo.openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 5000,
    );
    await repo.closeShift(
      shiftId: opened.id,
      countedCash: 5000,
      closedBy: 1,
      note: 'end of day',
    );
    expect(await repo.currentOpenShift(1), isNull);
  });

  test('openShift throws when the user already has an open shift', () async {
    await repo.openShift(userId: 1, terminalId: 'TILL-001', openingFloat: 5000);
    expect(
      () => repo.openShift(userId: 1, terminalId: 'TILL-001', openingFloat: 5000),
      throwsA(isA<ShiftAlreadyOpenException>()),
    );
  });

  test('recordCashSale increases cashSalesTotal and writes a sale event',
      () async {
    final shift = await repo.openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 5000,
    );

    await repo.recordCashSale(shiftId: shift.id, userId: 1, amount: 1200);
    await repo.recordCashSale(shiftId: shift.id, userId: 1, amount: 800);

    final updated = await repo.currentOpenShift(1);
    expect(updated!.cashSalesTotal, 2000);

    final events = await (db.select(db.cashEvents)
          ..where((e) => e.type.equals(CashEventType.sale.name)))
        .get();
    expect(events.length, 2);
    expect(events.map((e) => e.amount).toList(), [1200, 800]);
  });

  test('addCashMovement updates payInTotal and writes a payIn event',
      () async {
    final shift = await repo.openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 5000,
    );

    final event = await repo.addCashMovement(
      shiftId: shift.id,
      userId: 1,
      type: CashEventType.payIn,
      amount: 3000,
      reason: 'float top-up',
    );

    expect(event.type, CashEventType.payIn);
    expect(event.amount, 3000);
    expect(event.reason, 'float top-up');

    final updated = await repo.currentOpenShift(1);
    expect(updated!.payInTotal, 3000);
    expect(updated.payOutTotal, 0);
  });

  test('addCashMovement updates payOutTotal and writes a payOut event',
      () async {
    final shift = await repo.openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 5000,
    );

    await repo.addCashMovement(
      shiftId: shift.id,
      userId: 1,
      type: CashEventType.payOut,
      amount: 1500,
      reason: 'supplier payment',
    );

    final updated = await repo.currentOpenShift(1);
    expect(updated!.payOutTotal, 1500);
    expect(updated.payInTotal, 0);
  });

  test('addCashMovement rejects a non-movement event type', () async {
    final shift = await repo.openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 5000,
    );
    expect(
      () => repo.addCashMovement(
        shiftId: shift.id,
        userId: 1,
        type: CashEventType.sale,
        amount: 100,
        reason: 'x',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('recordNoSale writes a noSale event with approvedBy set', () async {
    final shift = await repo.openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 5000,
    );

    final event = await repo.recordNoSale(
      shiftId: shift.id,
      userId: 1,
      approvedBy: 1,
      reason: 'drawer check',
    );

    expect(event.type, CashEventType.noSale);
    expect(event.amount, isNull);
    expect(event.approvedBy, 1);
    expect(event.reason, 'drawer check');

    final events = await (db.select(db.cashEvents)
          ..where((e) => e.type.equals(CashEventType.noSale.name)))
        .get();
    expect(events.single.approvedBy, 1);
  });

  test('closeShift closes the shift and computes expectedCash/variance',
      () async {
    final shift = await repo.openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 10000,
    );
    await repo.recordCashSale(shiftId: shift.id, userId: 1, amount: 5000);
    await repo.addCashMovement(
      shiftId: shift.id,
      userId: 1,
      type: CashEventType.payIn,
      amount: 2000,
      reason: 'top-up',
    );
    await repo.addCashMovement(
      shiftId: shift.id,
      userId: 1,
      type: CashEventType.payOut,
      amount: 1000,
      reason: 'expense',
    );

    // expected = 10000 + 5000 + 2000 - 1000 = 16000
    final closed = await repo.closeShift(
      shiftId: shift.id,
      countedCash: 15800,
      closedBy: 1,
      note: 'short by 200',
    );

    expect(closed.status, ShiftStatus.closed);
    expect(closed.expectedCash, 16000);
    expect(closed.countedCash, 15800);
    expect(closed.variance, -200);
    expect(closed.closedBy, 1);
    expect(closed.closedAt, isNotNull);
    expect(closed.note, 'short by 200');

    final closeEvents = await (db.select(db.cashEvents)
          ..where((e) => e.type.equals(CashEventType.shiftClose.name)))
        .get();
    expect(closeEvents.length, 1);
    expect(closeEvents.single.amount, 15800);
  });

  test('completeCashSale links the sale to the shift and feeds its cash total',
      () async {
    final shift = await repo.openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 10000,
    );

    final products = ProductRepository(db);
    final cola = (await products.search('cola')).single;

    final sale = await SaleRepository(db).completeCashSale(
      cashierId: 1,
      shiftId: shift.id,
      lines: [CartLine(product: cola, qty: 3)],
      tendered: 1000,
    );

    // The persisted sales row carries the shift id.
    final saleRow = await (db.select(db.sales)
          ..where((s) => s.id.equals(sale.id)))
        .getSingle();
    expect(saleRow.shiftId, shift.id);

    // The shift's cash total reflects the sale total.
    final updated = await repo.currentOpenShift(1);
    expect(updated!.cashSalesTotal, sale.total);

    // A `sale` cash event was written for the shift.
    final saleEvents = await (db.select(db.cashEvents)
          ..where((e) => e.type.equals(CashEventType.sale.name)))
        .get();
    expect(saleEvents.length, 1);
    expect(saleEvents.single.shiftId, shift.id);
    expect(saleEvents.single.amount, sale.total);
    expect(saleEvents.single.userId, 1);
  });

  test('shiftSummary returns the shift, cashier name and event count',
      () async {
    final shift = await repo.openShift(
      userId: 1,
      terminalId: 'TILL-001',
      openingFloat: 10000,
    );
    await repo.recordCashSale(shiftId: shift.id, userId: 1, amount: 5000);
    await repo.closeShift(
      shiftId: shift.id,
      countedCash: 15000,
      closedBy: 1,
      note: '',
    );

    final summary = await repo.shiftSummary(shift.id);
    expect(summary.shift.status, ShiftStatus.closed);
    expect(summary.cashierName, isNotEmpty);
    // shiftOpen + sale + shiftClose
    expect(summary.eventCount, 3);
  });
}
