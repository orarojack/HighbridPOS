// test/money_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/shared/money.dart';

void main() {
  test('formatMoney renders cents as 2-decimal currency', () {
    expect(formatMoney(0), '0.00');
    expect(formatMoney(5), '0.05');
    expect(formatMoney(199), '1.99');
    expect(formatMoney(123456), '1234.56');
  });

  test('parseMoney converts a decimal string to cents', () {
    expect(parseMoney('0'), 0);
    expect(parseMoney('1.99'), 199);
    expect(parseMoney('1.5'), 150);
    expect(parseMoney('1234.56'), 123456);
  });

  test('parseMoney returns null for invalid input', () {
    expect(parseMoney(''), isNull);
    expect(parseMoney('abc'), isNull);
    expect(parseMoney('-5'), isNull);
  });
}
