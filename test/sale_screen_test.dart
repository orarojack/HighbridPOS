// test/sale_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/features/auth/auth_controller.dart';
import 'package:highbrid_pos/features/pos/cart_controller.dart';
import 'package:highbrid_pos/features/pos/payment_dialog.dart';
import 'package:highbrid_pos/features/pos/sale_screen.dart';
import 'package:highbrid_pos/providers.dart';

/// HighbridPOS is a desktop POS terminal; the sale screen is a wide two-pane
/// layout. The default 800x600 test viewport is too narrow, so widen the
/// surface before pumping and reset it afterwards.
void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('adding a product shows it in the cart with totals',
      (tester) async {
    _useDesktopViewport(tester);
    final db = AppDatabase(NativeDatabase.memory());
    await seedIfEmpty(db);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    // Log in so the checkout path has a cashier.
    await container
        .read(authControllerProvider.notifier)
        .login('admin', 'admin123');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SaleScreen()),
    ));
    await tester.pumpAndSettle();

    // Tap the first product card.
    await tester.tap(find.text('Cola 500ml').first);
    await tester.pumpAndSettle();

    expect(container.read(cartControllerProvider).length, 1);
    expect(container.read(cartControllerProvider.notifier).totals.total, 116);
  });

  testWidgets('stock guard blocks adding more units than available stock',
      (tester) async {
    _useDesktopViewport(tester);
    final db = AppDatabase(NativeDatabase.memory());
    await seedIfEmpty(db);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login('admin', 'admin123');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SaleScreen()),
    ));
    await tester.pumpAndSettle();

    // Rice 2kg is the seeded product with the smallest stock (40 units).
    const productName = 'Rice 2kg';
    const stockQty = 40;

    // Add exactly up to the stock limit; each tap is a successful add.
    for (var i = 0; i < stockQty; i++) {
      await tester.tap(find.text(productName).first);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(container.read(cartControllerProvider).single.qty, stockQty);

    // One more tap must be rejected and surface the stock-guard SnackBar.
    await tester.tap(find.text(productName).first);
    await tester.pumpAndSettle();

    expect(find.text('Not enough stock for $productName.'), findsOneWidget);
    // The cart quantity must not exceed the product's stock.
    expect(container.read(cartControllerProvider).single.qty, stockQty);
  });

  testWidgets('completing a cash sale records the sale and clears the cart',
      (tester) async {
    _useDesktopViewport(tester);
    final db = AppDatabase(NativeDatabase.memory());
    await seedIfEmpty(db);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await container
        .read(authControllerProvider.notifier)
        .login('admin', 'admin123');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SaleScreen()),
    ));
    await tester.pumpAndSettle();

    // Add one product to the cart.
    await tester.tap(find.text('Cola 500ml').first);
    await tester.pumpAndSettle();
    final total = container.read(cartControllerProvider.notifier).totals.total;
    expect(total, 116);

    // Open the payment dialog via the checkout button.
    await tester.tap(find.text('Take cash payment'));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentDialog), findsOneWidget);

    // Enter a tendered amount that covers the total.
    await tester.enterText(
        find.widgetWithText(TextField, 'Cash tendered'), '200');
    await tester.pumpAndSettle();

    // Complete the sale.
    await tester.tap(find.widgetWithText(FilledButton, 'Complete sale'));
    await tester.pumpAndSettle();

    // A receipt confirmation dialog appears after completion; dismiss it.
    if (find.text('Close').evaluate().isNotEmpty) {
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }

    // The sale was persisted to the in-memory database.
    final sales = await db.select(db.sales).get();
    expect(sales, hasLength(1));
    final saleItems = await db.select(db.saleItems).get();
    expect(saleItems, hasLength(1));
    expect(saleItems.single.lineTotal, total);
    final payments = await db.select(db.payments).get();
    expect(payments, hasLength(1));
    expect(payments.single.tendered, 20000); // '200' parsed to cents
    expect(payments.single.amount, total);

    // The cart was cleared after the sale completed.
    expect(container.read(cartControllerProvider), isEmpty);
    expect(find.text('Cart is empty.'), findsOneWidget);
  });
}
