// test/sale_screen_test.dart
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
}
