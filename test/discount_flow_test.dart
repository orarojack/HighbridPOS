// test/discount_flow_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/features/auth/auth_controller.dart';
import 'package:highbrid_pos/features/pos/cart_controller.dart';
import 'package:highbrid_pos/features/pos/sale_screen.dart';
import 'package:highbrid_pos/providers.dart';

/// HighbridPOS is a desktop POS terminal; the sale screen is a wide two-pane
/// layout, so widen the test surface before pumping and reset it afterwards.
void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Boots the Sell screen with an in-memory seeded DB, a signed-in admin and an
/// open shift (the screen is gated on a shift), then adds one Cola to the cart.
Future<ProviderContainer> _pumpSellScreenWithCola(WidgetTester tester) async {
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
  await container.read(shiftRepositoryProvider).openShift(
      userId: 1, terminalId: 'TILL-001', openingFloat: 0);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: SaleScreen()),
  ));
  await tester.pumpAndSettle();

  // Cola 500ml is seeded at 100c with a 16% tax rate.
  await tester.tap(find.text('Cola 500ml').first);
  await tester.pumpAndSettle();
  expect(container.read(cartControllerProvider).single.qty, 1);
  return container;
}

void main() {
  testWidgets(
      'a small fixed discount applies with no approval and updates the totals',
      (tester) async {
    final container = await _pumpSellScreenWithCola(tester);

    // 1 Cola: subtotal 100, tax 16, total 116 — no Discount row yet.
    expect(container.read(cartControllerProvider.notifier).totals.total, 116);
    expect(find.text('Discount'), findsNothing);

    // Open the line's discount dialog.
    await tester.tap(find.byTooltip('Discount'));
    await tester.pumpAndSettle();
    expect(find.text('Line discount'), findsOneWidget);

    // A 10c fixed discount is 10% of the line — below the 15% threshold.
    await tester.enterText(
        find.widgetWithText(TextField, 'Discount amount'), '10');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    // No manager-approval dialog was shown.
    expect(find.textContaining('Approve:'), findsNothing);

    // Discount applied: net 90, tax 14, total 104; discountTotal 10.
    final line = container.read(cartControllerProvider).single;
    expect(line.discount, 10);
    final totals = container.read(cartControllerProvider.notifier).totals;
    expect(totals.discountTotal, 10);
    expect(totals.total, 104);

    // The totals panel now shows a Discount row.
    expect(find.text('Discount'), findsOneWidget);
  });

  testWidgets(
      'an above-threshold percentage discount applies only after approval',
      (tester) async {
    final container = await _pumpSellScreenWithCola(tester);

    await tester.tap(find.byTooltip('Discount'));
    await tester.pumpAndSettle();

    // Switch to Percent mode and enter 20% — at/above the 15% threshold.
    await tester.tap(find.text('Percent'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Discount (%)'), '20');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    // The manager-approval dialog appears; the discount is not yet applied.
    expect(find.text('Approve: Apply discount'), findsOneWidget);
    expect(container.read(cartControllerProvider).single.discount, 0);

    // Approve with the seeded admin's Staff ID + PIN.
    await tester.enterText(
        find.widgetWithText(TextField, 'Staff ID'), 'ADM-001');
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '000000');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    // 20% of 100c = 20c discount: net 80, tax 13, total 93.
    final line = container.read(cartControllerProvider).single;
    expect(line.discount, 20);
    final totals = container.read(cartControllerProvider.notifier).totals;
    expect(totals.discountTotal, 20);
    expect(totals.total, 93);
  });

  testWidgets(
      'cancelling the approval leaves the line discount unchanged',
      (tester) async {
    final container = await _pumpSellScreenWithCola(tester);

    await tester.tap(find.byTooltip('Discount'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Percent'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Discount (%)'), '20');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    // Cancel the manager-approval dialog.
    expect(find.text('Approve: Apply discount'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // The line keeps its previous (zero) discount; totals unchanged.
    expect(container.read(cartControllerProvider).single.discount, 0);
    final totals = container.read(cartControllerProvider.notifier).totals;
    expect(totals.discountTotal, 0);
    expect(totals.total, 116);
  });
}
