// lib/data/repositories/report_repository.dart
import 'package:drift/drift.dart';

import '../../domain/models.dart';
import '../db/app_database.dart';

class ReportRepository {
  ReportRepository(this._db);
  final AppDatabase _db;

  /// Aggregates all completed sales for the given calendar day.
  Future<DailySummary> dailySummary(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final sales = await (_db.select(_db.sales)
          ..where((s) =>
              s.createdAt.isBiggerOrEqualValue(start) &
              s.createdAt.isSmallerThanValue(end)))
        .get();
    var subtotal = 0;
    var discountTotal = 0;
    var taxTotal = 0;
    var total = 0;
    for (final s in sales) {
      subtotal += s.subtotal;
      discountTotal += s.discountTotal;
      taxTotal += s.taxTotal;
      total += s.total;
    }
    final returns = await (_db.select(_db.returns)
          ..where((r) =>
              r.createdAt.isBiggerOrEqualValue(start) &
              r.createdAt.isSmallerThanValue(end)))
        .get();
    var refundTotal = 0;
    for (final r in returns) {
      refundTotal += r.refundTotal;
    }
    return DailySummary(
      day: start,
      saleCount: sales.length,
      subtotal: subtotal,
      discountTotal: discountTotal,
      taxTotal: taxTotal,
      total: total,
      returnCount: returns.length,
      refundTotal: refundTotal,
    );
  }
}
