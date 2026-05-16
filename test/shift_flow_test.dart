// test/shift_flow_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highbrid_pos/data/db/app_database.dart';
import 'package:highbrid_pos/data/db/seed.dart';
import 'package:highbrid_pos/domain/enums.dart';
import 'package:highbrid_pos/features/auth/auth_controller.dart';
import 'package:highbrid_pos/features/pos/sale_screen.dart';
import 'package:highbrid_pos/features/shift/end_shift_screen.dart';
import 'package:highbrid_pos/features/shift/shift_controller.dart';
import 'package:highbrid_pos/features/shift/shift_screen.dart';
import 'package:highbrid_pos/features/shift/shift_summary.dart';
import 'package:highbrid_pos/providers.dart';
import 'package:highbrid_pos/shared/theme.dart';

/// HighbridPOS is a desktop POS terminal; shift screens live in a wide shell.
/// The default 800x600 test viewport is too narrow, so widen the surface
/// before pumping and reset it afterwards.
void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Builds a container backed by a fresh in-memory database with the
/// `cashier` seeded user already signed in.
Future<ProviderContainer> _signedInContainer(WidgetTester tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  await seedIfEmpty(db);
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  await container
      .read(authControllerProvider.notifier)
      .login('cashier', 'cashier123');
  return container;
}

Widget _host(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

void main() {
  testWidgets('Sell screen shows the shift gate when no shift is open',
      (tester) async {
    _useDesktopViewport(tester);
    final container = await _signedInContainer(tester);

    await tester.pumpWidget(_host(container, const SaleScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Start your shift to begin selling'), findsOneWidget);
    // The sale UI is not shown.
    expect(find.text('Take cash payment'), findsNothing);
  });

  testWidgets('starting a shift from the gate makes the Sell screen usable',
      (tester) async {
    _useDesktopViewport(tester);
    final container = await _signedInContainer(tester);

    await tester.pumpWidget(_host(container, const SaleScreen()));
    await tester.pumpAndSettle();

    // Open the start-shift screen from the gate.
    await tester.tap(find.widgetWithText(FilledButton, 'Start shift'));
    await tester.pumpAndSettle();

    // Enter an opening float and start the shift.
    await tester.enterText(
        find.widgetWithText(TextField, 'Opening float'), '100');
    await tester.tap(find.widgetWithText(FilledButton, 'Start shift'));
    await tester.pumpAndSettle();

    // The gate is gone; the sale UI is now visible.
    expect(find.text('Start your shift to begin selling'), findsNothing);
    expect(find.text('Take cash payment'), findsOneWidget);

    // A shift row was persisted for the cashier.
    final shift =
        await container.read(shiftRepositoryProvider).currentOpenShift(2);
    expect(shift, isNotNull);
    expect(shift!.openingFloat, 10000);
  });

  testWidgets('ending a shift with a zero variance shows the summary',
      (tester) async {
    _useDesktopViewport(tester);
    final container = await _signedInContainer(tester);

    // Open a shift with a 5000-cent float and no sales: expected == 5000.
    await container.read(shiftControllerProvider.notifier).start(5000);

    await tester.pumpWidget(_host(container, const ShiftScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(EndShiftScreen), findsOneWidget);
    expect(find.text('Expected cash'), findsOneWidget);

    // Count exactly the expected cash — zero variance, no approval needed.
    await tester.enterText(
        find.widgetWithText(TextField, 'Counted cash'), '50.00');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
    await tester.pumpAndSettle();

    // The summary replaces the form; no approval dialog appeared.
    expect(find.byType(ShiftSummaryView), findsOneWidget);
    expect(find.text('Shift summary'), findsOneWidget);

    // The shift is closed in the database with a zero variance.
    final shifts = await container.read(databaseProvider).select(
          container.read(databaseProvider).shifts,
        ).get();
    expect(shifts.single.status, ShiftStatus.closed.name);
    expect(shifts.single.variance, 0);
  });

  testWidgets('ending a shift with a non-zero variance requires approval',
      (tester) async {
    _useDesktopViewport(tester);
    final container = await _signedInContainer(tester);

    await container.read(shiftControllerProvider.notifier).start(5000);

    await tester.pumpWidget(_host(container, const ShiftScreen()));
    await tester.pumpAndSettle();

    // Count more than expected — a non-zero variance.
    await tester.enterText(
        find.widgetWithText(TextField, 'Counted cash'), '60.00');
    await tester.pumpAndSettle();
    expect(find.textContaining('needs manager approval'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
    await tester.pumpAndSettle();

    // The manager-approval dialog must appear before the shift can close.
    expect(find.textContaining('Approve:'), findsOneWidget);
    // The shift has not closed yet.
    var shifts = await container
        .read(databaseProvider)
        .select(container.read(databaseProvider).shifts)
        .get();
    expect(shifts.single.status, ShiftStatus.open.name);

    // Approve with the admin's username + password.
    await tester.enterText(
        find.widgetWithText(TextField, 'Username'), 'admin');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'admin123');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    // The summary appears; the shift closed with the approver as closedBy.
    expect(find.byType(ShiftSummaryView), findsOneWidget);
    shifts = await container
        .read(databaseProvider)
        .select(container.read(databaseProvider).shifts)
        .get();
    expect(shifts.single.status, ShiftStatus.closed.name);
    expect(shifts.single.variance, 1000);
    expect(shifts.single.closedBy, 1); // admin is user id 1.
  });
}
