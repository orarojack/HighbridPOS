import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/domain/return_calculator.dart';

void main() {
  test('refundForLine computes net subtotal + rounded tax', () {
    expect(refundForLine(unitPrice: 100, qty: 2, taxRate: 0.0), 200);
    expect(refundForLine(unitPrice: 199, qty: 1, taxRate: 0.16), 231);
    expect(refundForLine(unitPrice: 100, qty: 3, taxRate: 0.16), 348);
  });

  test('refundForLine subtracts the line discount before tax', () {
    // net = 900 - 160 = 740; tax (740 * 0.16).round() = 118; total 858.
    expect(
      refundForLine(unitPrice: 450, qty: 2, taxRate: 0.16, discount: 160),
      858,
    );
    // zero-tax line: net = 240 - 40 = 200.
    expect(
      refundForLine(unitPrice: 120, qty: 2, taxRate: 0.0, discount: 40),
      200,
    );
  });

  test('refundTotal sums selected line refunds', () {
    expect(
      refundTotal([
        (unitPrice: 100, qty: 2, taxRate: 0.0, discount: 0),
        (unitPrice: 199, qty: 1, taxRate: 0.16, discount: 0),
      ]),
      431,
    );
    expect(refundTotal([]), 0);
  });

  test('refundTotal accounts for per-line discounts', () {
    expect(
      refundTotal([
        (unitPrice: 450, qty: 2, taxRate: 0.16, discount: 160),
        (unitPrice: 120, qty: 2, taxRate: 0.0, discount: 40),
      ]),
      858 + 200,
    );
  });
}
