// lib/domain/shift_calculator.dart

/// Cash the drawer should hold = float + cash sales + pay-ins − pay-outs −
/// refunds. All cents.
int expectedCash({
  required int openingFloat,
  required int cashSales,
  required int payIn,
  required int payOut,
  required int refunds,
}) =>
    openingFloat + cashSales + payIn - payOut - refunds;

/// Variance = counted − expected. Negative means a shortage. All cents.
int cashVariance({required int counted, required int expected}) =>
    counted - expected;
