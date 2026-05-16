import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/domain/shift_calculator.dart';

void main() {
  test('expectedCash sums float, cash sales, pay-ins minus pay-outs', () {
    expect(
      expectedCash(openingFloat: 5000, cashSales: 42000, payIn: 0, payOut: 0),
      47000,
    );
    expect(
      expectedCash(openingFloat: 5000, cashSales: 42000, payIn: 1000, payOut: 500),
      47500,
    );
  });

  test('variance is counted minus expected', () {
    expect(cashVariance(counted: 46500, expected: 47000), -500);
    expect(cashVariance(counted: 47000, expected: 47000), 0);
    expect(cashVariance(counted: 47200, expected: 47000), 200);
  });
}
