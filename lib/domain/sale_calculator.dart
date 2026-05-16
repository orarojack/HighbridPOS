// lib/domain/sale_calculator.dart
import 'models.dart';

/// Aggregates a set of cart lines into subtotal, tax, and grand total.
CartTotals calculateTotals(List<CartLine> lines) {
  var subtotal = 0;
  var taxTotal = 0;
  for (final line in lines) {
    subtotal += line.lineSubtotal;
    taxTotal += line.lineTax;
  }
  return CartTotals(
    subtotal: subtotal,
    taxTotal: taxTotal,
    total: subtotal + taxTotal,
  );
}

/// Change owed to the customer. Never negative when tender is sufficient.
int changeDue({required int tendered, required int total}) => tendered - total;

/// True when the cash tendered covers the sale total.
bool isSufficientTender({required int tendered, required int total}) =>
    tendered >= total;
