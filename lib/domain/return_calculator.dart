// lib/domain/return_calculator.dart
//
// Pure-Dart refund calculation helpers.
// Tax is rounded per line, consistent with the original sale's line-tax rounding.

/// Returns the total refund amount (in cents) for a single return line.
///
/// Computes `unitPrice * qty` as the subtotal, then adds tax rounded to the
/// nearest cent: `(subtotal * taxRate).round()`.
int refundForLine({
  required int unitPrice,
  required int qty,
  required double taxRate,
}) {
  final subtotal = unitPrice * qty;
  return subtotal + (subtotal * taxRate).round();
}

/// Sums [refundForLine] over a list of line records.
///
/// Each record is a Dart named-field record
/// `({int unitPrice, int qty, double taxRate})`.
/// Returns 0 for an empty list.
int refundTotal(List<({int unitPrice, int qty, double taxRate})> lines) =>
    lines.fold(
      0,
      (sum, l) =>
          sum + refundForLine(unitPrice: l.unitPrice, qty: l.qty, taxRate: l.taxRate),
    );
