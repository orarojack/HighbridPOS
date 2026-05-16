// lib/data/repositories/shift_repository.dart
import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../domain/shift_calculator.dart';
import '../db/app_database.dart';

/// Thrown when a user tries to open a shift while one is already open.
class ShiftAlreadyOpenException implements Exception {
  ShiftAlreadyOpenException(this.userId);
  final int userId;
  @override
  String toString() => 'User $userId already has an open shift';
}

class ShiftRepository {
  ShiftRepository(this._db);
  final AppDatabase _db;

  /// Opens a new shift for [userId] on [terminalId] with [openingFloat] cents.
  /// Writes the shift row and a `shiftOpen` cash event in one transaction.
  /// Throws [ShiftAlreadyOpenException] if the user already has an open shift.
  Future<Shift> openShift({
    required int userId,
    required String terminalId,
    required int openingFloat,
  }) async {
    return _db.transaction(() async {
      final existing = await currentOpenShift(userId);
      if (existing != null) {
        throw ShiftAlreadyOpenException(userId);
      }
      final shiftId = await _db.into(_db.shifts).insert(
            ShiftsCompanion.insert(
              userId: userId,
              terminalId: terminalId,
              openingFloat: openingFloat,
              status: ShiftStatus.open.name,
            ),
          );
      await _db.into(_db.cashEvents).insert(
            CashEventsCompanion.insert(
              shiftId: shiftId,
              userId: userId,
              type: CashEventType.shiftOpen.name,
              amount: Value(openingFloat),
            ),
          );
      return _getShift(shiftId);
    });
  }

  /// Returns the user's current open shift, or `null` when none is open.
  Future<Shift?> currentOpenShift(int userId) async {
    final row = await (_db.select(_db.shifts)
          ..where((s) =>
              s.userId.equals(userId) &
              s.status.equals(ShiftStatus.open.name)))
        .getSingleOrNull();
    return row == null ? null : _toShift(row);
  }

  /// Adds [amount] cents of cash sales to the shift and writes a `sale`
  /// cash event — in one transaction.
  Future<CashEvent> recordCashSale({
    required int shiftId,
    required int userId,
    required int amount,
  }) async {
    return _db.transaction(() async {
      await (_db.update(_db.shifts)..where((s) => s.id.equals(shiftId))).write(
        ShiftsCompanion.custom(
          cashSalesTotal: _db.shifts.cashSalesTotal + Variable(amount),
        ),
      );
      final eventId = await _db.into(_db.cashEvents).insert(
            CashEventsCompanion.insert(
              shiftId: shiftId,
              userId: userId,
              type: CashEventType.sale.name,
              amount: Value(amount),
            ),
          );
      return _getCashEvent(eventId);
    });
  }

  /// Records a pay-in or pay-out cash movement: updates the matching shift
  /// total and writes the cash event — in one transaction.
  /// Throws [ArgumentError] if [type] is not `payIn` or `payOut`.
  Future<CashEvent> addCashMovement({
    required int shiftId,
    required int userId,
    required CashEventType type,
    required int amount,
    required String reason,
  }) async {
    if (type != CashEventType.payIn && type != CashEventType.payOut) {
      throw ArgumentError.value(
          type, 'type', 'addCashMovement expects payIn or payOut');
    }
    return _db.transaction(() async {
      final isPayIn = type == CashEventType.payIn;
      await (_db.update(_db.shifts)..where((s) => s.id.equals(shiftId))).write(
        ShiftsCompanion.custom(
          payInTotal: isPayIn
              ? _db.shifts.payInTotal + Variable(amount)
              : _db.shifts.payInTotal,
          payOutTotal: isPayIn
              ? _db.shifts.payOutTotal
              : _db.shifts.payOutTotal + Variable(amount),
        ),
      );
      final eventId = await _db.into(_db.cashEvents).insert(
            CashEventsCompanion.insert(
              shiftId: shiftId,
              userId: userId,
              type: type.name,
              amount: Value(amount),
              reason: Value(reason),
            ),
          );
      return _getCashEvent(eventId);
    });
  }

  /// Records a no-sale drawer open as a `noSale` cash event with the
  /// approving manager stored in `approvedBy`.
  Future<CashEvent> recordNoSale({
    required int shiftId,
    required int userId,
    required int approvedBy,
    required String reason,
  }) async {
    final eventId = await _db.into(_db.cashEvents).insert(
          CashEventsCompanion.insert(
            shiftId: shiftId,
            userId: userId,
            type: CashEventType.noSale.name,
            reason: Value(reason),
            approvedBy: Value(approvedBy),
          ),
        );
    return _getCashEvent(eventId);
  }

  /// Closes the shift: computes and stores `expectedCash`/`variance`, stamps
  /// `closedAt`, writes a `shiftClose` cash event — all in one transaction.
  Future<Shift> closeShift({
    required int shiftId,
    required int countedCash,
    required int closedBy,
    required String note,
  }) async {
    return _db.transaction(() async {
      final row = await (_db.select(_db.shifts)
            ..where((s) => s.id.equals(shiftId)))
          .getSingle();
      final expected = expectedCash(
        openingFloat: row.openingFloat,
        cashSales: row.cashSalesTotal,
        payIn: row.payInTotal,
        payOut: row.payOutTotal,
        refunds: row.refundTotal,
      );
      final variance = cashVariance(counted: countedCash, expected: expected);
      await (_db.update(_db.shifts)..where((s) => s.id.equals(shiftId))).write(
        ShiftsCompanion(
          status: Value(ShiftStatus.closed.name),
          closedAt: Value(DateTime.now()),
          expectedCash: Value(expected),
          countedCash: Value(countedCash),
          variance: Value(variance),
          closedBy: Value(closedBy),
          note: Value(note),
        ),
      );
      await _db.into(_db.cashEvents).insert(
            CashEventsCompanion.insert(
              shiftId: shiftId,
              userId: closedBy,
              type: CashEventType.shiftClose.name,
              amount: Value(countedCash),
            ),
          );
      return _getShift(shiftId);
    });
  }

  /// Returns a [ShiftSummary] with the shift, its cashier's name, and the
  /// count of cash events recorded against it.
  Future<ShiftSummary> shiftSummary(int shiftId) async {
    final shift = await _getShift(shiftId);
    final cashier = await (_db.select(_db.users)
          ..where((u) => u.id.equals(shift.userId)))
        .getSingle();
    final events = await (_db.select(_db.cashEvents)
          ..where((e) => e.shiftId.equals(shiftId)))
        .get();
    return ShiftSummary(
      shift: shift,
      cashierName: cashier.fullName,
      eventCount: events.length,
    );
  }

  Future<Shift> _getShift(int shiftId) async {
    final row = await (_db.select(_db.shifts)
          ..where((s) => s.id.equals(shiftId)))
        .getSingle();
    return _toShift(row);
  }

  Future<CashEvent> _getCashEvent(int eventId) async {
    final row = await (_db.select(_db.cashEvents)
          ..where((e) => e.id.equals(eventId)))
        .getSingle();
    return _toCashEvent(row);
  }

  Shift _toShift(ShiftRow row) => Shift(
        id: row.id,
        userId: row.userId,
        terminalId: row.terminalId,
        openingFloat: row.openingFloat,
        status: ShiftStatus.fromName(row.status),
        openedAt: row.openedAt,
        closedAt: row.closedAt,
        cashSalesTotal: row.cashSalesTotal,
        payInTotal: row.payInTotal,
        payOutTotal: row.payOutTotal,
        refundTotal: row.refundTotal,
        expectedCash: row.expectedCash,
        countedCash: row.countedCash,
        variance: row.variance,
        closedBy: row.closedBy,
        note: row.note,
      );

  CashEvent _toCashEvent(CashEventRow row) => CashEvent(
        id: row.id,
        shiftId: row.shiftId,
        userId: row.userId,
        type: CashEventType.fromName(row.type),
        amount: row.amount,
        reason: row.reason,
        approvedBy: row.approvedBy,
        createdAt: row.createdAt,
      );
}
