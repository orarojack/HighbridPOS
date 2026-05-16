// lib/data/repositories/sale_repository.dart
import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../domain/sale_calculator.dart';
import '../db/app_database.dart';

class InsufficientStockException implements Exception {
  InsufficientStockException(this.productName);
  final String productName;
  @override
  String toString() => 'Insufficient stock for $productName';
}

class SaleRepository {
  SaleRepository(this._db);
  final AppDatabase _db;

  /// Records a completed cash sale: writes sale, items, payment, and stock
  /// movements, deducts product stock, links the sale to [shiftId], and feeds
  /// the shift's cash total with a `sale` cash event — all in one transaction.
  /// Throws [InsufficientStockException] if any line exceeds available stock.
  Future<SaleRecord> completeCashSale({
    required int cashierId,
    required int shiftId,
    required List<CartLine> lines,
    required int tendered,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('Cannot complete a sale with an empty cart');
    }
    final totals = calculateTotals(lines);

    return _db.transaction(() async {
      // Re-check stock inside the transaction.
      for (final line in lines) {
        final current = await (_db.select(_db.products)
              ..where((p) => p.id.equals(line.product.id)))
            .getSingle();
        if (current.stockQty < line.qty) {
          throw InsufficientStockException(current.name);
        }
      }

      final reference = await _nextReference();
      final saleId = await _db.into(_db.sales).insert(SalesCompanion.insert(
            referenceNo: reference,
            cashierId: cashierId,
            shiftId: Value(shiftId),
            subtotal: totals.subtotal,
            discountTotal: Value(totals.discountTotal),
            taxTotal: totals.taxTotal,
            total: totals.total,
            status: SaleStatus.completed.name,
          ));

      for (final line in lines) {
        await _db.into(_db.saleItems).insert(SaleItemsCompanion.insert(
              saleId: saleId,
              productId: line.product.id,
              nameSnapshot: line.product.name,
              unitPrice: line.unitPrice,
              taxRate: line.product.taxRate,
              qty: line.qty,
              discount: Value(line.lineDiscount),
              lineTax: line.lineTax,
              lineTotal: line.lineTotal,
            ));
        await (_db.update(_db.products)
              ..where((p) => p.id.equals(line.product.id)))
            .write(ProductsCompanion.custom(
          stockQty: _db.products.stockQty - Variable(line.qty),
        ));
        await _db.into(_db.stockMovements).insert(
              StockMovementsCompanion.insert(
                productId: line.product.id,
                type: MovementType.sale.name,
                qtyDelta: -line.qty,
                refType: const Value('sale'),
                refId: Value(saleId),
              ),
            );
      }

      await _db.into(_db.payments).insert(PaymentsCompanion.insert(
            saleId: saleId,
            method: PaymentMethod.cash.name,
            amount: totals.total,
            tendered: tendered,
            changeDue: changeDue(tendered: tendered, total: totals.total),
          ));

      // Feed the shift's cash total and record a `sale` cash event — kept
      // atomic with the sale by running inside this same transaction.
      await (_db.update(_db.shifts)..where((s) => s.id.equals(shiftId)))
          .write(ShiftsCompanion.custom(
        cashSalesTotal: _db.shifts.cashSalesTotal + Variable(totals.total),
      ));
      await _db.into(_db.cashEvents).insert(CashEventsCompanion.insert(
            shiftId: shiftId,
            userId: cashierId,
            type: CashEventType.sale.name,
            amount: Value(totals.total),
          ));

      return getById(saleId);
    });
  }

  Future<SaleRecord> getById(int saleId) async {
    final sale = await (_db.select(_db.sales)
          ..where((s) => s.id.equals(saleId)))
        .getSingle();
    final cashier = await (_db.select(_db.users)
          ..where((u) => u.id.equals(sale.cashierId)))
        .getSingle();
    final payment = await (_db.select(_db.payments)
          ..where((p) => p.saleId.equals(saleId)))
        .getSingle();
    final items = await (_db.select(_db.saleItems)
          ..where((i) => i.saleId.equals(saleId)))
        .get();
    return SaleRecord(
      id: sale.id,
      referenceNo: sale.referenceNo,
      cashierId: sale.cashierId,
      cashierName: cashier.fullName,
      subtotal: sale.subtotal,
      taxTotal: sale.taxTotal,
      total: sale.total,
      tendered: payment.tendered,
      changeDue: payment.changeDue,
      createdAt: sale.createdAt,
      lines: items.map(_toSaleLine).toList(),
    );
  }

  SaleLine _toSaleLine(SaleItem row) => SaleLine(
        nameSnapshot: row.nameSnapshot,
        unitPrice: row.unitPrice,
        taxRate: row.taxRate,
        qty: row.qty,
        discount: row.discount,
        lineTax: row.lineTax,
        lineTotal: row.lineTotal,
      );

  /// Builds the next per-day sale reference: YYYYMMDD-NNNN.
  Future<String> _nextReference() async {
    final now = DateTime.now();
    final prefix = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final todayCount = await (_db.select(_db.sales)
          ..where((s) => s.referenceNo.like('$prefix-%')))
        .get();
    final seq = (todayCount.length + 1).toString().padLeft(4, '0');
    return '$prefix-$seq';
  }
}
