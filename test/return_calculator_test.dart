import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/domain/return_calculator.dart';

void main() {
  test('refundForLine computes subtotal + rounded tax', () {
    expect(refundForLine(unitPrice: 100, qty: 2, taxRate: 0.0), 200);
    expect(refundForLine(unitPrice: 199, qty: 1, taxRate: 0.16), 231);
    expect(refundForLine(unitPrice: 100, qty: 3, taxRate: 0.16), 348);
  });

  test('refundTotal sums selected line refunds', () {
    expect(
      refundTotal([
        (unitPrice: 100, qty: 2, taxRate: 0.0),
        (unitPrice: 199, qty: 1, taxRate: 0.16),
      ]),
      431,
    );
    expect(refundTotal([]), 0);
  });
}
