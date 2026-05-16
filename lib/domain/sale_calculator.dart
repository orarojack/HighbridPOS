// lib/domain/sale_calculator.dart
import 'models.dart';

/// Aggregates a set of cart lines into subtotal, tax, and grand total.
///
/// Tax is summed from per-line rounded values so it matches line-level display.
CartTotals calculateTotals(List<CartLine> lines) {
  var subtotal = 0;
  var discountTotal = 0;
  var taxTotal = 0;
  var total = 0;
  for (final line in lines) {
    subtotal += line.lineSubtotal;
    discountTotal += line.lineDiscount;
    taxTotal += line.lineTax;
    total += line.lineTotal;
  }
  return CartTotals(
    subtotal: subtotal,
    discountTotal: discountTotal,
    taxTotal: taxTotal,
    total: total,
  );
}

/// Returns change owed to the customer (tendered − total).
/// Caller must ensure [isSufficientTender] is true first; otherwise the result is negative.
int changeDue({required int tendered, required int total}) => tendered - total;

/// True when the cash tendered covers the sale total.
bool isSufficientTender({required int tendered, required int total}) =>
    tendered >= total;
