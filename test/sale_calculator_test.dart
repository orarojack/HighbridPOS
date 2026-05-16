// test/sale_calculator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/domain/models.dart';
import 'package:highbrid_pos/domain/sale_calculator.dart';

Product _product({int sellPrice = 100, double taxRate = 0.0}) => Product(
      id: 1,
      sku: 'SKU1',
      barcode: null,
      name: 'Test',
      description: '',
      categoryId: null,
      costPrice: 50,
      sellPrice: sellPrice,
      taxRate: taxRate,
      stockQty: 100,
      reorderLevel: 0,
      active: true,
    );

void main() {
  test('totals of an empty cart are all zero', () {
    expect(calculateTotals(const []), CartTotals.empty);
  });

  test('totals sum line subtotals and taxes', () {
    final lines = [
      CartLine(product: _product(sellPrice: 200, taxRate: 0.10), qty: 2),
      CartLine(product: _product(sellPrice: 150, taxRate: 0.00), qty: 1),
    ];
    final totals = calculateTotals(lines);
    expect(totals.subtotal, 550); // 400 + 150
    expect(totals.taxTotal, 40); // round(400*0.10) + 0
    expect(totals.total, 590);
  });

  test('line tax rounds to nearest cent', () {
    final line = CartLine(product: _product(sellPrice: 199, taxRate: 0.16), qty: 1);
    expect(line.lineTax, 32); // round(199 * 0.16 = 31.84)
    expect(line.lineTotal, 231);
  });

  test('a fixed-amount discount nets out before tax', () {
    final line = CartLine(
      product: _product(sellPrice: 200, taxRate: 0.10),
      qty: 2,
      discount: 100,
    );
    expect(line.lineSubtotal, 400);
    expect(line.lineDiscount, 100);
    expect(line.lineNet, 300);
    expect(line.lineTax, 30); // round(300 * 0.10)
    expect(line.lineTotal, 330);
  });

  test('totals mix a discounted and an undiscounted line', () {
    final lines = [
      CartLine(
        product: _product(sellPrice: 200, taxRate: 0.10),
        qty: 2,
        discount: 100,
      ),
      CartLine(product: _product(sellPrice: 150, taxRate: 0.00), qty: 1),
    ];
    final totals = calculateTotals(lines);
    expect(totals.subtotal, 550); // 400 + 150 gross
    expect(totals.discountTotal, 100);
    expect(totals.taxTotal, 30); // round(300*0.10) + 0
    expect(totals.total, 480); // 550 - 100 + 30
  });

  test('a discount larger than the subtotal is clamped', () {
    final line = CartLine(
      product: _product(sellPrice: 200, taxRate: 0.10),
      qty: 2,
      discount: 5000,
    );
    expect(line.lineDiscount, 400); // clamped to subtotal
    expect(line.lineNet, 0);
    expect(line.lineTax, 0);
    expect(line.lineTotal, 0); // never negative
    final totals = calculateTotals([line]);
    expect(totals.subtotal, 400);
    expect(totals.discountTotal, 400);
    expect(totals.taxTotal, 0);
    expect(totals.total, 0);
  });

  test('changeDue is tendered minus total', () {
    expect(changeDue(tendered: 1000, total: 590), 410);
    expect(changeDue(tendered: 590, total: 590), 0);
    expect(changeDue(tendered: 500, total: 590), -90); // insufficient tender yields negative
  });

  test('isSufficientTender is false when tendered is below total', () {
    expect(isSufficientTender(tendered: 500, total: 590), isFalse);
    expect(isSufficientTender(tendered: 590, total: 590), isTrue);
    expect(isSufficientTender(tendered: 1000, total: 590), isTrue);
  });
}
