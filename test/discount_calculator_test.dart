import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/domain/discount_calculator.dart';

void main() {
  test('resolveDiscount: fixed amount clamps to the subtotal', () {
    expect(resolveDiscount(lineSubtotal: 1000, isPercent: false, value: 250), 250);
    expect(resolveDiscount(lineSubtotal: 1000, isPercent: false, value: 5000), 1000);
    expect(resolveDiscount(lineSubtotal: 1000, isPercent: false, value: -5), 0);
  });

  test('resolveDiscount: percent of the subtotal, rounded and clamped', () {
    expect(resolveDiscount(lineSubtotal: 1000, isPercent: true, value: 10), 100);
    expect(resolveDiscount(lineSubtotal: 999, isPercent: true, value: 10), 100); // 99.9 -> 100
    expect(resolveDiscount(lineSubtotal: 1000, isPercent: true, value: 150), 1000);
    expect(resolveDiscount(lineSubtotal: 1000, isPercent: true, value: 0), 0);
  });

  test('discountNeedsApproval at or above the threshold', () {
    expect(discountNeedsApproval(lineDiscount: 100, lineSubtotal: 1000), false); // 10%
    expect(discountNeedsApproval(lineDiscount: 150, lineSubtotal: 1000), true);  // 15%
    expect(discountNeedsApproval(lineDiscount: 300, lineSubtotal: 1000), true);  // 30%
    expect(discountNeedsApproval(lineDiscount: 0, lineSubtotal: 0), false);
  });
}
