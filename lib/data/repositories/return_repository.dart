// lib/data/repositories/return_repository.dart
import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../db/app_database.dart';

/// Thrown when a requested return quantity exceeds the line's currently
/// returnable quantity (sold minus already-returned).
class OverReturnException implements Exception {
  OverReturnException(this.productName, {required this.requested, required this.returnable});
  final String productName;
  final int requested;
  final int returnable;
  @override
  String toString() => 'Cannot return $requested of $productName: only '
      '$returnable returnable';
}

class ReturnRepository {
  ReturnRepository(this._db);
  final AppDatabase _db;

  /// Loads the sale identified by [referenceNo] and builds a [ReturnDraft]
  /// the controller can edit: each line carries its `soldQty`,
  /// `alreadyReturnedQty` (sum of prior `return_items.qty`) and a starting
  /// `selectedQty` of 0. Returns `null` when no sale has that reference.
  Future<ReturnDraft?> findSaleForReturn(String referenceNo) async {
    final sale = await (_db.select(_db.sales)
          ..where((s) => s.referenceNo.equals(referenceNo)))
        .getSingleOrNull();
    if (sale == null) return null;

    final items = await (_db.select(_db.saleItems)
          ..where((i) => i.saleId.equals(sale.id)))
        .get();

    final lines = <ReturnLineDraft>[];
    for (final item in items) {
      final returned = await _alreadyReturnedQty(item.id);
      lines.add(ReturnLineDraft(
        saleItemId: item.id,
        productId: item.productId,
        nameSnapshot: item.nameSnapshot,
        unitPrice: item.unitPrice,
        taxRate: item.taxRate,
        soldQty: item.qty,
        alreadyReturnedQty: returned,
        selectedQty: 0,
      ));
    }

    return ReturnDraft(
      originalSaleId: sale.id,
      originalReference: sale.referenceNo,
      lines: lines,
      reason: '',
    );
  }

  /// Records a return in ONE atomic transaction: re-checks every selected
  /// line's returnable quantity (throws [OverReturnException] on conflict),
  /// generates a `RET-YYYYMMDD-NNNN` reference, writes the `returns` and
  /// `return_items` rows, restocks each product, writes `return`
  /// `stock_movements`, inserts one negative-amount refund `payments` row, a
  /// `refund` `cash_events` row, and increments the shift's `refundTotal`.
  /// Returns the persisted [ReturnRecord].
  Future<ReturnRecord> recordReturn({
    required int originalSaleId,
    required int cashierId,
    required int shiftId,
    required String reason,
    required int approvedBy,
    required List<ReturnLineDraft> selectedLines,
  }) async {
    final lines = selectedLines.where((l) => l.selectedQty > 0).toList();
    if (lines.isEmpty) {
      throw ArgumentError('Cannot record a return with no selected lines');
    }

    return _db.transaction(() async {
      // Re-check returnable quantities inside the transaction.
      for (final line in lines) {
        final returned = await _alreadyReturnedQty(line.saleItemId);
        final returnable = line.soldQty - returned;
        if (line.selectedQty > returnable) {
          throw OverReturnException(
            line.nameSnapshot,
            requested: line.selectedQty,
            returnable: returnable,
          );
        }
      }

      final refundTotal = lines.fold<int>(
        0,
        (sum, l) => sum + l.lineTotal,
      );

      final reference = await _nextReference();
      final returnId = await _db.into(_db.returns).insert(
            ReturnsCompanion.insert(
              referenceNo: reference,
              originalSaleId: originalSaleId,
              cashierId: cashierId,
              shiftId: Value(shiftId),
              reason: Value(reason),
              refundTotal: refundTotal,
              approvedBy: approvedBy,
            ),
          );

      for (final line in lines) {
        await _db.into(_db.returnItems).insert(
              ReturnItemsCompanion.insert(
                returnId: returnId,
                saleItemId: line.saleItemId,
                productId: line.productId,
                nameSnapshot: line.nameSnapshot,
                qty: line.selectedQty,
                unitPrice: line.unitPrice,
                taxRate: line.taxRate,
                lineTax: line.lineTax,
                lineTotal: line.lineTotal,
              ),
            );
        // Restock the product atomically.
        await (_db.update(_db.products)
              ..where((p) => p.id.equals(line.productId)))
            .write(ProductsCompanion.custom(
          stockQty: _db.products.stockQty + Variable(line.selectedQty),
        ));
        await _db.into(_db.stockMovements).insert(
              StockMovementsCompanion.insert(
                productId: line.productId,
                type: 'return',
                qtyDelta: line.selectedQty,
                refType: const Value('return'),
                refId: Value(returnId),
              ),
            );
      }

      // One refund payment row: negative amount, cash, linked to the return
      // and to the original sale.
      await _db.into(_db.payments).insert(PaymentsCompanion.insert(
            saleId: originalSaleId,
            method: PaymentMethod.cash.name,
            amount: -refundTotal,
            tendered: 0,
            changeDue: 0,
            returnId: Value(returnId),
          ));

      // Refund cash event and shift running total — same transaction.
      await _db.into(_db.cashEvents).insert(CashEventsCompanion.insert(
            shiftId: shiftId,
            userId: cashierId,
            type: CashEventType.refund.name,
            amount: Value(refundTotal),
          ));
      await (_db.update(_db.shifts)..where((s) => s.id.equals(shiftId)))
          .write(ShiftsCompanion.custom(
        refundTotal: _db.shifts.refundTotal + Variable(refundTotal),
      ));

      return _getReturn(returnId);
    });
  }

  /// Loads a persisted [ReturnRecord] with its lines (for the receipt).
  Future<ReturnRecord> getReturn(int id) => _getReturn(id);

  Future<ReturnRecord> _getReturn(int id) async {
    final row = await (_db.select(_db.returns)..where((r) => r.id.equals(id)))
        .getSingle();
    final items = await (_db.select(_db.returnItems)
          ..where((i) => i.returnId.equals(id)))
        .get();
    final sale = await (_db.select(_db.sales)
          ..where((s) => s.id.equals(row.originalSaleId)))
        .getSingle();
    return _toReturnRecord(row, items, sale.referenceNo);
  }

  /// Sum of `return_items.qty` already returned against [saleItemId].
  Future<int> _alreadyReturnedQty(int saleItemId) async {
    final rows = await (_db.select(_db.returnItems)
          ..where((i) => i.saleItemId.equals(saleItemId)))
        .get();
    return rows.fold<int>(0, (sum, r) => sum + r.qty);
  }

  /// Builds the next per-day return reference: RET-YYYYMMDD-NNNN.
  Future<String> _nextReference() async {
    final now = DateTime.now();
    final datePart = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final prefix = 'RET-$datePart';
    final todayCount = await (_db.select(_db.returns)
          ..where((r) => r.referenceNo.like('$prefix-%')))
        .get();
    final seq = (todayCount.length + 1).toString().padLeft(4, '0');
    return '$prefix-$seq';
  }

  ReturnRecord _toReturnRecord(
    ReturnRow row,
    List<ReturnItemRow> items,
    String originalReference,
  ) =>
      ReturnRecord(
        id: row.id,
        referenceNo: row.referenceNo,
        originalSaleId: row.originalSaleId,
        originalReference: originalReference,
        cashierId: row.cashierId,
        shiftId: row.shiftId,
        reason: row.reason,
        refundTotal: row.refundTotal,
        approvedBy: row.approvedBy,
        createdAt: row.createdAt,
        lines: items.map(_toReturnLine).toList(),
      );

  ReturnLine _toReturnLine(ReturnItemRow row) => ReturnLine(
        id: row.id,
        returnId: row.returnId,
        saleItemId: row.saleItemId,
        productId: row.productId,
        nameSnapshot: row.nameSnapshot,
        qty: row.qty,
        unitPrice: row.unitPrice,
        taxRate: row.taxRate,
        lineTax: row.lineTax,
        lineTotal: row.lineTotal,
      );
}
