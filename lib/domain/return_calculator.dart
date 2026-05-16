// lib/domain/return_calculator.dart
//
// Pure-Dart refund calculation helpers.
// Tax is rounded per line, consistent with the original sale's line-tax rounding.

/// Returns the total refund amount (in cents) for a single return line.
///
/// The refund is computed on the *discounted* (net) amount: subtract the
/// proportional line [discount] from `unitPrice * qty`, then add tax rounded
/// to the nearest cent: `(net * taxRate).round()`.
int refundForLine({
  required int unitPrice,
  required int qty,
  required double taxRate,
  int discount = 0,
}) {
  final subtotal = unitPrice * qty;
  final net = subtotal - discount;
  return net + (net * taxRate).round();
}

/// Sums [refundForLine] over a list of line records.
///
/// Each record is a Dart named-field record
/// `({int unitPrice, int qty, double taxRate, int discount})`.
/// Returns 0 for an empty list.
int refundTotal(
        List<({int unitPrice, int qty, double taxRate, int discount})>
            lines) =>
    lines.fold(
      0,
      (sum, l) =>
          sum +
          refundForLine(
            unitPrice: l.unitPrice,
            qty: l.qty,
            taxRate: l.taxRate,
            discount: l.discount,
          ),
    );
