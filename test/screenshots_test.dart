// test/screenshots_test.dart
//
// Preview-generation test. NOT a feature test — it renders the real app
// screens and writes PNG previews to doc/preview/ via golden files.
//
// Run with:  flutter test test/screenshots_test.dart --update-goldens
//
// Generating goldens always "passes"; the point is the PNG artifacts.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/features/auth/auth_controller.dart';
import 'package:highbrid_pos/features/auth/login_screen.dart';
import 'package:highbrid_pos/features/home_shell.dart';
import 'package:highbrid_pos/features/pos/sale_screen.dart';
import 'package:highbrid_pos/features/products/product_list_screen.dart';
import 'package:highbrid_pos/features/reports/daily_summary_screen.dart';
import 'package:highbrid_pos/features/shift/end_shift_screen.dart';
import 'package:highbrid_pos/features/shift/start_shift_screen.dart';
import 'package:highbrid_pos/providers.dart';
import 'package:highbrid_pos/shared/theme.dart';

/// Real Roboto faces shipped inside the Flutter SDK cache. By default
/// `flutter test` renders text as black boxes because no font is loaded;
/// loading these under the family name `'Roboto'` (the family the default
/// Material text theme expects) makes every Text widget render readably.
const _fontFiles = <String, List<String>>{
  'Roboto': [
    '/home/oraro/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    '/home/oraro/flutter/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf',
    '/home/oraro/flutter/bin/cache/artifacts/material_fonts/Roboto-Medium.ttf',
    '/home/oraro/flutter/bin/cache/artifacts/material_fonts/Roboto-Light.ttf',
  ],
  // Loading the real Material icon font makes Icon widgets render as proper
  // glyphs instead of empty placeholder boxes.
  'MaterialIcons': [
    '/home/oraro/flutter/bin/cache/artifacts/material_fonts/'
        'MaterialIcons-Regular.otf',
  ],
};

Future<void> _loadRealFonts() async {
  for (final entry in _fontFiles.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = await file.readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<ProviderContainer> _seededContainer(WidgetTester tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  await seedIfEmpty(db);
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  return container;
}

Widget _host(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: child,
      ),
    );

/// Captures the currently pumped MaterialApp into doc/preview/<name>.
/// `matchesGoldenFile` paths are relative to this test file's directory,
/// so `../doc/preview/...` lands the PNGs in /home/oraro/HighbridPOS/doc/preview.
Future<void> _capture(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../doc/preview/$name'),
  );
}

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('01 - login (Staff PIN)', (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer(tester);
    await tester.pumpWidget(_host(container, const LoginScreen()));
    await tester.pumpAndSettle();
    await _capture(tester, '01-login-pin.png');
  });

  testWidgets('02 - login (Manager)', (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer(tester);
    await tester.pumpWidget(_host(container, const LoginScreen()));
    await tester.pumpAndSettle();
    // Switch to the Manager segment before capturing.
    await tester.tap(find.text('Manager'));
    await tester.pumpAndSettle();
    await _capture(tester, '02-login-manager.png');
  });

  testWidgets('03 - sell screen (shift gate)', (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer(tester);
    // Logged in as cashier with NO open shift -> the "start your shift" gate.
    await container
        .read(authControllerProvider.notifier)
        .login('cashier', 'cashier123');
    await tester.pumpWidget(_host(container, const SaleScreen()));
    await tester.pumpAndSettle();
    await _capture(tester, '03-sell-gated.png');
  });

  testWidgets('04 - sell screen (active, cart with items)', (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer(tester);
    await container
        .read(authControllerProvider.notifier)
        .login('cashier', 'cashier123');
    // Open a shift so the sale UI is usable.
    await container.read(shiftRepositoryProvider).openShift(
        userId: 2, terminalId: 'TILL-001', openingFloat: 10000);
    await tester.pumpWidget(_host(container, const SaleScreen()));
    await tester.pumpAndSettle();
    // Tap a couple of product cards so the cart shows items + totals.
    await tester.tap(find.text('Cola 500ml').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('White Bread 400g').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cola 500ml').first);
    await tester.pumpAndSettle();
    await _capture(tester, '04-sell-active.png');
  });

  testWidgets('05 - start shift', (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer(tester);
    await container
        .read(authControllerProvider.notifier)
        .login('cashier', 'cashier123');
    await tester.pumpWidget(_host(container, const StartShiftScreen()));
    await tester.pumpAndSettle();
    await _capture(tester, '05-start-shift.png');
  });

  testWidgets('06 - end shift', (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer(tester);
    await container
        .read(authControllerProvider.notifier)
        .login('cashier', 'cashier123');
    final repo = container.read(shiftRepositoryProvider);
    final shift = await repo.openShift(
        userId: 2, terminalId: 'TILL-001', openingFloat: 10000);
    // Record a couple of cash sales so the shift has activity.
    await repo.recordCashSale(shiftId: shift.id, userId: 2, amount: 11600);
    await repo.recordCashSale(shiftId: shift.id, userId: 2, amount: 8400);
    final withSales = await repo.currentOpenShift(2);
    await tester.pumpWidget(
        _host(container, EndShiftScreen(shift: withSales!)));
    await tester.pumpAndSettle();
    await _capture(tester, '06-end-shift.png');
  });

  testWidgets('07 - product list', (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer(tester);
    await container
        .read(authControllerProvider.notifier)
        .login('admin', 'admin123');
    await tester.pumpWidget(_host(container, const ProductListScreen()));
    await tester.pumpAndSettle();
    await _capture(tester, '07-products.png');
  });

  testWidgets('08 - daily summary', (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer(tester);
    await container
        .read(authControllerProvider.notifier)
        .login('admin', 'admin123');
    await tester.pumpWidget(_host(container, const DailySummaryScreen()));
    await tester.pumpAndSettle();
    await _capture(tester, '08-daily-summary.png');
  });

  testWidgets('09 - home shell', (tester) async {
    _useDesktopViewport(tester);
    final container = await _seededContainer(tester);
    await container
        .read(authControllerProvider.notifier)
        .login('admin', 'admin123');
    await tester.pumpWidget(_host(container, const HomeShell()));
    await tester.pumpAndSettle();
    await _capture(tester, '09-home-shell.png');
  });
}
